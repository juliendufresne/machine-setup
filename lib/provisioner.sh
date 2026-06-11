#!/usr/bin/env bash
set -euo pipefail
# The provisioner framework: the engine behind the post-install provisioners (the
# workspace, the dotfiles). A provisioner is not software the toolkit installs but
# personal configuration it applies last, once every tool is in place: it fetches
# the repository's self-contained installer script and runs it, and that script
# downloads the repository and lays it down on its own. The provisioners are
# identical but for a name, a header, and a default installer, so both the per-piece
# record (PROVISIONERS, PROVISIONER_TITLES, PROVISIONER_INSTALLERS) and the behaviour
# live here: provisioner::provision sets the PROVISIONER_* globals for the one it is
# about to run and calls provisioner::run, provisioner::choose offers the toggle menu,
# and provisioner::provision_all runs the chosen ones in order. The orchestrator
# (bin/machine-setup) just drives the menu and the run.
#
# Unlike a software unit (see lib/runner.sh) a provisioner has no install/configure
# split and no ordering: its one input is collected at provision time, not up front,
# so the installer location is asked right before it runs, and the installer itself
# asks the user for whatever it needs. Provisioning is the only action: the
# orchestrator runs the provisioners after every software unit, in the same process,
# under the session it already owns. There is no checkout the toolkit owns and
# nothing to track, so there is no status to report and nothing to remove: the
# external installer owns the repository it places. Sourced by bin/machine-setup.

! declare -F provisioner::run &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   provisioner::installer
#
# Description:
#   Prints the installer the provisioner fetches and runs: the <name>.installer
#   input when set (from the environment or this run), otherwise the default
#   installer. The value is either an URL (fetched to a temporary file and run) or a
#   path to a local executable (run directly), resolved at run time by
#   provisioner::run_installer. A soft read, so it resolves whether or not the input
#   has been collected yet. Writes the value to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   provisioner::installer
#--------------------------------------------------
provisioner::installer() {
    local installer

    installer="$(state::input "$PROVISIONER_NAME.installer" 2>/dev/null || true)"
    [[ -n "$installer" ]] || installer="$PROVISIONER_DEFAULT_INSTALLER"

    printf '%s' "$installer"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::installer

#--------------------------------------------------
# Function:
#   provisioner::is_url <value>
#
# Description:
#   Reports whether <value> is an URL (a scheme followed by ://, such as https://
#   or file://) rather than a local path, so provisioner::run_installer can tell a
#   remote installer to fetch from a local one to execute. Writes nothing.
#
# Arguments:
#   <value>  The installer value to classify
#
# Returns:
#   0 when <value> is an URL
#   1 otherwise
#
# Example:
#   provisioner::is_url https://example.com/install.sh
#--------------------------------------------------
provisioner::is_url() {
    [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::is_url

#--------------------------------------------------
# Function:
#   provisioner::_stage_inputs
#
# Description:
#   Points the provisioner's inputs overlay at its working area under the
#   orchestrator's session (execution-in-progress/<key>/inputs), so state::ask
#   writes there until provision commits them. The orchestrator owns the session
#   (provisioners run only through the set-up flow, after the software, in the same
#   process), so this joins that session rather than starting one. A no-op when no
#   session is active. Exports MACHINE_SETUP_INPUTS_WORKING and creates the working
#   directory.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always
#
# Example:
#   provisioner::_stage_inputs
#--------------------------------------------------
provisioner::_stage_inputs() {
    session::active || return 0

    MACHINE_SETUP_INPUTS_WORKING="$(session::dir)/$(state::_key "$PROVISIONER_NAME")/inputs"
    export MACHINE_SETUP_INPUTS_WORKING
    mkdir -p "$MACHINE_SETUP_INPUTS_WORKING"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::_stage_inputs

#--------------------------------------------------
# Function:
#   provisioner::request_inputs
#
# Description:
#   Collects the provisioner's one input, at provision time so the question is asked
#   right before the installer runs: where the installer comes from. The prompt and
#   help line show the default in square brackets, so blank keeps it. The answer is
#   either an URL to fetch and pipe to a shell or a path to a local executable to run.
#   The prompt is framed under the provisioner's pinned header (PROVISIONER_TITLE),
#   with a short help line (a no-op with no terminal).
#   May prompt on the terminal and writes the input file.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   provisioner::request_inputs
#--------------------------------------------------
provisioner::request_inputs() {
    screen::open "$PROVISIONER_TITLE" "Where the $PROVISIONER_NAME installer comes from and how it runs."

    SCREEN_HELP="The installer to fetch and run: an URL we download and run, or a local executable path. [$PROVISIONER_DEFAULT_INSTALLER]" \
        state::ask "$PROVISIONER_NAME.installer" "$PROVISIONER_NAME installer URL or path [$PROVISIONER_DEFAULT_INSTALLER]"

    screen::close
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::request_inputs

#--------------------------------------------------
# Function:
#   provisioner::run_remote <url>
#
# Description:
#   Fetches the installer at <url> to a temporary file (wget, or curl when wget is
#   absent) and then runs it with sh, removing the file afterwards. Downloading to a
#   file and running it - rather than piping the download straight into sh - keeps
#   the installer's standard input on the terminal, so it (and the tools it runs)
#   can prompt the user; a pipe would make stdin the download itself. The installer
#   runs in the foreground so its own output streams. Errors when neither fetcher is
#   on PATH. Creates and removes a temporary file. Returns the fetch's exit status
#   when the download fails, otherwise the installer's.
#
# Arguments:
#   <url>  The installer URL to fetch and run
#
# Returns:
#   0 when the fetched installer succeeds
#   1 when neither wget nor curl is available
#   the fetch's exit status when the download fails
#   the installer's exit status when it fails
#
# Example:
#   provisioner::run_remote https://example.com/install.sh
#--------------------------------------------------
provisioner::run_remote() {
    local -i exit_status
    local script
    local url

    url="$1"
    exit_status=0

    if command -v wget &>/dev/null
    then
        script="$(mktemp)"
        wget -qO "$script" "$url" || exit_status=$?
    elif command -v curl &>/dev/null
    then
        script="$(mktemp)"
        curl -fsSL "$url" -o "$script" || exit_status=$?
    else
        output::fatal "neither wget nor curl is available to fetch the $PROVISIONER_NAME installer."

        return 1
    fi

    if ((exit_status == 0))
    then
        sh "$script" || exit_status=$?
    fi

    rm -f "$script"

    return "$exit_status"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::run_remote

#--------------------------------------------------
# Function:
#   provisioner::run_installer
#
# Description:
#   Runs the installer the provisioner resolved (provisioner::installer): an URL is
#   fetched to a temporary file and run (provisioner::run_remote), and the installer
#   it carries downloads the repository and lays it down; a local path is run
#   directly when it is executable. Either way the installer runs in the foreground,
#   not through output::run, so its own output streams and it can prompt the user.
#   Errors when a local path is missing or not executable.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the installer succeeds
#   1 when a local installer path is missing or not executable
#   the installer's exit status when it fails
#
# Example:
#   provisioner::run_installer
#--------------------------------------------------
provisioner::run_installer() {
    local installer

    installer="$(provisioner::installer)"

    if provisioner::is_url "$installer"
    then
        provisioner::run_remote "$installer"

        return $?
    fi

    if [[ ! -x "$installer" ]]
    then
        output::fatal "the $PROVISIONER_NAME installer ($installer) is not an URL and is not an executable file."

        return 1
    fi

    "$installer"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::run_installer

#--------------------------------------------------
# Function:
#   provisioner::run
#
# Description:
#   Applies the provisioner: the entry point the orchestrator calls once it has set
#   the PROVISIONER_* globals, last, after every software unit. Provisioning is the
#   only action, so this is the whole of it: it points the inputs overlay at the run's
#   session (provisioner::_stage_inputs), collects the one input
#   (provisioner::request_inputs, the only interactive step the toolkit drives),
#   commits it so it survives to later runs, then fetches and runs the installer
#   (provisioner::run_installer), which downloads the repository and lays it down. The
#   orchestrator already owns the session, so this neither begins nor ends one, and
#   there is no checkout to own, so nothing is recorded. Stops at the first step that
#   fails. Opens a stage header and runs the installer.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the provisioner was applied
#   N propagated from the first step that fails
#
# Example:
#   provisioner::run
#--------------------------------------------------
provisioner::run() {
    output::stage "Provisioning the $PROVISIONER_NAME"

    provisioner::_stage_inputs                     # step 1: join the run's session for inputs
    provisioner::request_inputs                    # step 2: collect the input (interactive)
    state::commit_prefix "$PROVISIONER_NAME."      # keep the input for later runs
    provisioner::run_installer || return $?        # step 3: fetch and run the installer
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::run

#--------------------------------------------------
# Function:
#   provisioner::contains <needle> <item>...
#
# Description:
#   Reports whether <needle> is one of the following <item> arguments. A small set
#   helper, used by provisioner::provision_all to keep only the chosen provisioners.
#   Writes nothing.
#
# Arguments:
#   <needle>   The value to look for
#   <item>...  Zero or more values to search
#
# Returns:
#   0 when <needle> is among the items
#   1 otherwise
#
# Example:
#   provisioner::contains workspace "${selected[@]}"
#--------------------------------------------------
provisioner::contains() {
    local item
    local needle

    needle="$1"
    shift

    for item in "$@"
    do
        [[ "$item" != "$needle" ]] || return 0
    done

    return 1
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::contains

#--------------------------------------------------
# Function:
#   provisioner::choose
#
# Description:
#   Resolves which post-install provisioners to run and prints the chosen names, one
#   per line, to stdout. The provisioners are a fixed pair (PROVISIONERS, the
#   workspace then the dotfiles), not discovered software, so the menu always offers
#   exactly those two, both pre-ticked: the 'set up everything' default, with the
#   user unticking whichever they do not want. The entries are handed to
#   menu::select; with no terminal menu::select falls back to the pre-ticked set
#   (both), so a piped, no-argument run still provisions. Offered only in the
#   interactive set-up flow, after the software install; a named run never reaches
#   here. Reads the descriptions (PROVISIONER_DESCRIPTIONS); drives the checklist on
#   the terminal (see menu::select); stdout carries only the chosen names.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a selection was produced (possibly empty)
#
# Example:
#   provisioner::choose
#--------------------------------------------------
provisioner::choose() {
    local description
    local -a entries
    local name

    entries=()
    for name in "${PROVISIONERS[@]}"
    do
        # Both provisioners are offered ticked: provisioning is the default of the
        # interactive flow, and with no terminal the fallback emits the ticked set,
        # so a piped run provisions both.
        description="${PROVISIONER_DESCRIPTIONS[$name]}"
        entries+=("$(printf '1\t%s\t%s' "$name" "$description")")
    done

    # Pin a header over the toggle menu and clear the region under it; both bracket
    # calls are no-ops with no tty.
    screen::open 'Post-install provisioners' 'Tick the personal configuration to apply on top of the installed software.'
    MENU_PROMPT='Select provisioners to run. Arrows or j/k move, space toggles, Enter confirms.' \
        SCREEN_HELP='Space toggles a provisioner; ticked ones fetch and run their installer.' \
        menu::select "${entries[@]}"
    screen::close
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::choose

#--------------------------------------------------
# Function:
#   provisioner::provision <name>
#
# Description:
#   Provisions one post-install provisioner by driving the framework (provisioner::run)
#   in this process. It loads the named provisioner's record into the PROVISIONER_*
#   globals the framework reads (its header and default installer, from
#   PROVISIONER_TITLES and PROVISIONER_INSTALLERS) and calls provisioner::run.
#   Provisioning is the only action, so there is nothing to route: provisioners are
#   OS-agnostic, so there is no per-OS resolution, and they own no executable of their
#   own: the framework is the whole implementation and this is the only seam to it.
#   The suite stubs this to drive the higher-level helpers without a real fetch.
#   Carries the framework's own output and exit status straight through.
#
# Arguments:
#   <name>  The provisioner name (workspace or dotfiles)
#
# Returns:
#   the exit status provisioner::run propagates
#
# Example:
#   provisioner::provision workspace
#--------------------------------------------------
provisioner::provision() {
    local name

    name="${1:?provisioner name required}"

    PROVISIONER_NAME="$name"
    PROVISIONER_TITLE="${PROVISIONER_TITLES[$name]}"
    PROVISIONER_DEFAULT_INSTALLER="${PROVISIONER_INSTALLERS[$name]}"

    provisioner::run
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::provision

#--------------------------------------------------
# Function:
#   provisioner::provision_all <name>...
#
# Description:
#   Runs the post-install provisioners, last, now that every tool is installed. Each
#   chosen provisioner is run in PROVISIONERS order (the workspace before the
#   dotfiles, regardless of the order given), and gathers its one
#   input (where the installer comes from) right before it fetches and runs that
#   repository's installer script. A failing provisioner does not abandon the rest:
#   the loop continues and the worst exit status seen is returned. Skips silently when
#   none are given (a named run, or every provisioner unticked). Writes progress to
#   stderr; each provisioner's own output is left untouched.
#
# Arguments:
#   <name>...  Zero or more provisioner names to run (a subset of PROVISIONERS)
#
# Returns:
#   0 when every chosen provisioner ran or none were given
#   N the worst exit status seen across the provisioners
#
# Example:
#   provisioner::provision_all workspace dotfiles
#--------------------------------------------------
provisioner::provision_all() {
    local -i exit_status
    local -i failure
    local name

    (($# > 0)) || return 0

    exit_status=0

    output::log 'Running the post-install provisioners...'
    # Run in the fixed PROVISIONERS order, keeping only the ones that were chosen, so
    # the workspace always precedes the dotfiles whatever order the caller passed.
    for name in "${PROVISIONERS[@]}"
    do
        provisioner::contains "$name" "$@" || continue

        if provisioner::provision "$name"
        then
            : # Provisioned.
        else
            failure=$?
            ((failure <= exit_status)) || exit_status=$failure
        fi
    done

    return "$exit_status"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::provision_all

# ─── Constants / globals ────────────────────────────────────────────────────────

# The post-install provisioners, in the order they run: not software but external
# repositories whose self-contained installer script the toolkit fetches and runs
# (the workspace, the dotfiles). They are never discovered or listed beside the
# software; the interactive flow offers them their own toggle menu after the install.
# The orchestrator runs them last, after every piece of software, in this list order
# (the workspace before the dotfiles), so the dotfiles land on top of the workspace.
PROVISIONERS=('workspace' 'dotfiles')
[[ -v TEST_FLAG ]] || readonly PROVISIONERS

# Each provisioner's record: the header its input prompt sits under and the default
# installer used when the <name>.installer input is blank. The provisioners are
# identical but for these values, so the framework holds the behaviour and
# provisioner::provision loads the matching record into the PROVISIONER_* globals
# before driving it.
declare -A PROVISIONER_TITLES=(
    [workspace]='Workspace setup'
    [dotfiles]='Dotfiles setup'
)
[[ -v TEST_FLAG ]] || readonly PROVISIONER_TITLES

declare -A PROVISIONER_INSTALLERS=(
    [workspace]='https://raw.githubusercontent.com/juliendufresne/machine-workspace/main/install-repository.sh'
    [dotfiles]='https://raw.githubusercontent.com/juliendufresne/dotfiles/main/install-repository.sh'
)
[[ -v TEST_FLAG ]] || readonly PROVISIONER_INSTALLERS

# Each provisioner's one-line description, shown beside its name in the toggle menu
# (provisioner::choose). Held here rather than read from a share/<name>/description
# file (the way software units carry theirs): the provisioners are a fixed pair, not
# discovered units, so the framework owns this small map and never needs software.sh.
declare -A PROVISIONER_DESCRIPTIONS=(
    [workspace]='Create a workspace directory with its own dedicated SSH and GPG keys'
    [dotfiles]='Install your dotfiles: personal shell, editor, and tool configuration'
)
[[ -v TEST_FLAG ]] || readonly PROVISIONER_DESCRIPTIONS

# This library's own directory, so the sibling libraries are sourced regardless of
# the caller's location or the working directory. Defined only when not already set
# (the executable may have resolved it first), and made readonly outside tests so
# specs can reassign it.
if [[ -z "${LIB_DIR:-}" ]]
then
    LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    [[ -v TEST_FLAG ]] || readonly LIB_DIR
fi

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/session.sh
source "$LIB_DIR/session.sh"
# shellcheck source=lib/screen.sh
source "$LIB_DIR/screen.sh"
# shellcheck source=lib/menu.sh
source "$LIB_DIR/menu.sh"
