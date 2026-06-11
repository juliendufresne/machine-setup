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

# ─── Constants / globals ────────────────────────────────────────────────────────

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
