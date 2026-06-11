#!/usr/bin/env bash
set -euo pipefail
# The provisioner: the engine behind the post-install provisioners (the workspace, the
# dotfiles). A provisioner applies personal configuration on top of the freshly
# installed software: it fetches a repository's self-contained installer script and
# runs it, and that script downloads the repository and lays it down on its own. The
# provisioners are identical but for a name, a confirm question, and a fixed installer,
# so both the per-piece record (PROVISIONERS, PROVISIONER_CONFIRMS, PROVISIONER_INSTALLERS)
# and the behaviour live here: provisioner::confirm asks whether to run one,
# provisioner::run fetches and runs its installer, and provisioner::main walks the pair,
# confirming and running each in turn. The installer URL is fixed (an arbitrary URL's
# behaviour is unknown, and the side installers can be run by hand afterwards), and the
# installer itself asks the user for whatever it needs. The orchestrator
# (bin/machine-setup) runs this file as a subprocess after the software, and a user can
# run it directly to (re)apply the provisioners on their own.

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   provisioner::confirm <name>
#
# Description:
#   Asks whether to run the named provisioner: a plain [Y/n] prompt (the
#   provisioner's question from PROVISIONER_CONFIRMS), modelled on the session
#   discard confirm. The default is yes, so an empty answer or any answer that does
#   not start with n/N confirms. Uses PROMPT_INPUT / PROMPT_OUTPUT (defaulting to
#   /dev/tty) with the same tty probe the other interactive helpers use: with no
#   terminal it asks nothing and confirms, so a piped, unattended run still
#   provisions both (the way the old toggle menu fell back to its ticked set). May
#   prompt on the terminal; writes nothing else.
#
# Arguments:
#   <name>  The provisioner name (workspace or dotfiles)
#
# Returns:
#   0 when the provisioner is confirmed (or there is no terminal)
#   1 when the user declined
#
# Example:
#   provisioner::confirm workspace || continue
#--------------------------------------------------
provisioner::confirm() {
    local choice
    local input
    local name
    local output

    name="${1:?provisioner name required}"

    input="${PROMPT_INPUT:-/dev/tty}"
    output="${PROMPT_OUTPUT:-/dev/tty}"

    # Confirm on a terminal; with no terminal say yes (the same tty probe the other
    # interactive helpers use, so a /dev/tty that cannot be opened counts as no
    # terminal and a piped run still provisions both).
    if { : <"$input"; } 2>/dev/null && { : >>"$output"; } 2>/dev/null
    then
        printf '%s [Y/n] ' "${PROVISIONER_CONFIRMS[$name]}" >"$output"
        read -r choice <"$input" || choice=''
        [[ "$choice" != [Nn]* ]] || return 1
    fi

    return 0
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::confirm

#--------------------------------------------------
# Function:
#   provisioner::run <name>
#
# Description:
#   Applies one named provisioner, last, after every software unit: fetches its fixed
#   installer (PROVISIONER_INSTALLERS) to a temporary file (wget, or curl when wget is
#   absent) and runs it with sh, removing the file afterwards. Downloading to a file
#   and running it - rather than piping the download straight into sh - keeps the
#   installer's standard input on the terminal, so it (and the tools it runs) can
#   prompt the user; a pipe would make stdin the download itself. The installer runs
#   in the foreground so its own output streams, and it downloads the repository and
#   lays it down on its own. The orchestrator already owns the session, so this
#   neither begins nor ends one, and there is no checkout to own, so nothing is
#   recorded. Errors when neither fetcher is on PATH. Creates and removes a temporary
#   file. Returns the fetch's exit status when the download fails, otherwise the
#   installer's.
#
# Arguments:
#   <name>  The provisioner name (workspace or dotfiles)
#
# Returns:
#   0 when the fetched installer succeeds
#   1 when neither wget nor curl is available
#   the fetch's exit status when the download fails
#   the installer's exit status when it fails
#
# Example:
#   provisioner::run workspace
#--------------------------------------------------
provisioner::run() {
    local -i exit_status
    local name
    local script
    local url

    name="${1:?provisioner name required}"
    url="${PROVISIONER_INSTALLERS[$name]}"
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
        output::fatal "neither wget nor curl is available to fetch the $name installer."

        return 1
    fi

    if ((exit_status == 0))
    then
        sh "$script" || exit_status=$?
    fi

    rm -f "$script"

    return "$exit_status"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::run

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   provisioner::main
#
# Description:
#   Runs the post-install provisioners, last, now that every tool is installed: the
#   entry point for direct execution and the orchestrator's subprocess call. It walks
#   the pair in PROVISIONERS order (the workspace before the dotfiles), asking for each
#   whether to
#   run it (provisioner::confirm) and fetching and running the confirmed ones
#   (provisioner::run), so the confirm and the run interleave: confirm the workspace,
#   run it, then confirm the dotfiles, run them. A declined provisioner is skipped; a
#   failing one does not abandon the rest, the loop continues and the worst exit status
#   seen is returned. Writes progress to stderr; each provisioner's own output is left
#   untouched.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when every confirmed provisioner ran (or all were declined)
#   N the worst exit status seen across the provisioners
#
# Example:
#   provisioner::main
#--------------------------------------------------
provisioner::main() {
    local -i exit_status
    local -i failure
    local name

    exit_status=0

    output::log 'Running the post-install provisioners...'
    # Confirm and run each provisioner in the fixed PROVISIONERS order, so the
    # workspace is asked about and applied before the dotfiles.
    for name in "${PROVISIONERS[@]}"
    do
        provisioner::confirm "$name" || continue

        failure=0
        provisioner::run "$name" || failure=$?
        ((failure <= exit_status)) || exit_status=$failure
    done

    return "$exit_status"
}
[[ -v TEST_FLAG ]] || readonly -f provisioner::main

# ─── Constants / globals ────────────────────────────────────────────────────────

# The post-install provisioners, in the order they run: not software but external
# repositories whose self-contained installer script the toolkit fetches and runs
# (the workspace, the dotfiles). They are never discovered or listed beside the
# software; the interactive flow asks about each one with a [Y/n] confirm after the
# install. The orchestrator runs them last, after every piece of software, in this
# list order (the workspace before the dotfiles), so the dotfiles land on top of the
# workspace.
PROVISIONERS=('workspace' 'dotfiles')
[[ -v TEST_FLAG ]] || readonly PROVISIONERS

# Each provisioner's [Y/n] question, asked by provisioner::confirm right before it
# runs. The provisioners are identical but for these values, so the framework holds
# the behaviour and provisioner::confirm reads the matching question by name.
declare -A PROVISIONER_CONFIRMS=(
    [workspace]='Do you want to create workspace(s)?'
    [dotfiles]='Do you want to install dotfiles?'
)
[[ -v TEST_FLAG ]] || readonly PROVISIONER_CONFIRMS

# Each provisioner's fixed installer: the self-contained script provisioner::run
# fetches and runs, looked up by name. The URL is locked, not overridable: an
# arbitrary URL's behaviour is unknown, and the side installers can be run by hand
# afterwards.
declare -A PROVISIONER_INSTALLERS=(
    [workspace]='https://raw.githubusercontent.com/juliendufresne/machine-workspace/main/install.sh'
    [dotfiles]='https://raw.githubusercontent.com/juliendufresne/dotfiles/main/install.sh'
)
[[ -v TEST_FLAG ]] || readonly PROVISIONER_INSTALLERS

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/output.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/output.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || provisioner::main "$@"
