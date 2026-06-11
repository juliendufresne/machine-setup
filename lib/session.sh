#!/usr/bin/env bash
set -euo pipefail
# The execution session: a short-lived working area under the state store,
# $XDG_STATE_HOME/machine-setup/execution-in-progress, that marks a run in
# progress and holds each unit's not-yet-performed inputs (lib/state.sh's working
# overlay) until the underlying action commits them to inputs/. Its presence is
# the lock: a leftover area means a previous run did not finish, so the next run
# warns and offers to discard it.
#
# One process owns the session - the orchestrator, or a unit run on its own - and
# exports MACHINE_SETUP_SESSION so every child unit subprocess inherits it and
# skips re-acquiring or cleaning, exactly as the secret store inherits
# MACHINE_SETUP_SECRET_FD. Only the owner removes the area at the end. Sourced by
# lib/runner.sh and bin/machine-setup.

! declare -F session::begin &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   session::dir
#
# Description:
#   Prints the session working area path,
#   $XDG_STATE_HOME/machine-setup/execution-in-progress. Writes the path to
#   stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   session::dir
#--------------------------------------------------
session::dir() {
    printf '%s/execution-in-progress' "$(state::_root)"
}
[[ -v TEST_FLAG ]] || readonly -f session::dir

#--------------------------------------------------
# Function:
#   session::active
#
# Description:
#   Reports whether a session is in progress for this process, that is whether
#   MACHINE_SETUP_SESSION is set - because this process began one or inherited it
#   from a parent. Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a session is active
#   1 otherwise
#
# Example:
#   session::active && ...
#--------------------------------------------------
session::active() {
    [[ -n "${MACHINE_SETUP_SESSION:-}" ]]
}
[[ -v TEST_FLAG ]] || readonly -f session::active

#--------------------------------------------------
# Function:
#   session::begin
#
# Description:
#   Starts the execution session, or joins one already in progress. When
#   MACHINE_SETUP_SESSION is already set this process is a child of the run's
#   owner, so it does nothing and succeeds, letting the owner's area stand. As the
#   owner it checks for a leftover area (a previous run that did not finish): on a
#   terminal it asks whether to discard it and continue, aborting the run when the
#   answer is no; with no terminal it warns and continues unattended. It then
#   recreates the area fresh, writes the machine-setup.lock marker, exports
#   MACHINE_SETUP_SESSION so child subprocesses inherit the session, and records
#   that this process owns it so session::end cleans up. Writes a warning or a
#   prompt, creates the session area, and exports the session marker.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the session is active (begun or inherited)
#   1 when the user declined to discard a leftover session
#
# Example:
#   session::begin || return $?
#--------------------------------------------------
session::begin() {
    local choice
    local dir
    local input
    local output

    session::active && return 0                   # inherited from the owner

    dir="$(session::dir)"

    # A non-empty area means a previous run left work behind. Confirm the discard
    # on a terminal; warn and continue when unattended (the same tty probe the
    # interactive helpers use, so a /dev/tty that cannot be opened counts as no
    # terminal).
    if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]
    then
        input="${PROMPT_INPUT:-/dev/tty}"
        output="${PROMPT_OUTPUT:-/dev/tty}"
        if { : <"$input"; } 2>/dev/null && { : >>"$output"; } 2>/dev/null
        then
            printf 'A previous run did not finish. Discard it and continue? [y/N] ' >"$output"
            read -r choice <"$input" || choice=''
            [[ "$choice" == [Yy]* ]] || return 1
        else
            output::warn 'discarding an unfinished previous run'
        fi
    fi

    rm -rf -- "$dir"
    mkdir -p -- "$dir/machine-setup"
    : >"$dir/machine-setup.lock"

    export MACHINE_SETUP_SESSION=1
    SESSION_OWNED=1                                # this process cleans up at the end

    return 0
}
[[ -v TEST_FLAG ]] || readonly -f session::begin

#--------------------------------------------------
# Function:
#   session::end
#
# Description:
#   Ends the execution session, removing the working area, but only for the
#   process that owns it (the one whose session::begin started it, not a child
#   that inherited MACHINE_SETUP_SESSION). A child, or a call with no session
#   open, is a no-op. Clears the session markers so a later begin in the same
#   process starts cleanly. Removes the session area.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   session::end
#--------------------------------------------------
session::end() {
    [[ -n "${SESSION_OWNED:-}" ]] || return 0     # only the owner cleans up

    rm -rf -- "$(session::dir)"
    unset SESSION_OWNED
    unset MACHINE_SETUP_SESSION
}
[[ -v TEST_FLAG ]] || readonly -f session::end

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling libraries are sourced regardless
# of the caller's working directory. Defined only when not already set, and made
# readonly outside tests so specs can reassign it.
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
