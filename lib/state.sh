#!/usr/bin/env bash
set -euo pipefail
# The persistent state store under $XDG_STATE_HOME/machine-setup
# (default ~/.local/state/machine-setup). It holds:
#
#   inputs/         saved input values, keyed by input name.
#   managed/        one marker per unit we manage, written once its install and
#                   configure succeed; pre-ticks the menu on a later run.
#   config/<id>/    the prior value of each configuration variable we set, so
#                   unconfigure restores it exactly.
#   manifests/<id>  the paths a workspace instance created.
#
# <id> is runner::id: the unit name, or name@instance for an instanceable unit.
#
# During a run an inputs overlay is layered on top of inputs/: when
# MACHINE_SETUP_INPUTS_WORKING points at a unit's working area (lib/session.sh,
# execution-in-progress/<unit>/inputs), writes land there and reads prefer it,
# falling back to the committed inputs/. The value moves down to inputs/ only once
# the action it drives is performed (state::commit*), so a run abandoned partway
# leaves no half-entered inputs behind. With the variable unset - tests, a status
# query, anything outside a run - the store behaves as the plain inputs/ directory.
# Sourced by lib/runner.sh.

! declare -F state::_root &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   state::_root
#
# Description:
#   Prints the store root path, $XDG_STATE_HOME/machine-setup (default
#   ~/.local/state/machine-setup). Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   state::_root
#--------------------------------------------------
state::_root() {
    printf '%s/machine-setup' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_root

#--------------------------------------------------
# Function:
#   state::_dir <subdir>
#
# Description:
#   Ensures a sub-directory of the store exists, creating it with mkdir -p, and
#   prints its path. Writes the path to stdout and may create directories.
#
# Arguments:
#   <subdir>  The sub-directory under the store root
#
# Returns:
#   0 on success
#   non-zero when the directory cannot be created
#
# Example:
#   state::_dir inputs
#--------------------------------------------------
state::_dir() {
    local dir

    dir="$(state::_root)/$1"
    mkdir -p "$dir"

    printf '%s' "$dir"
}
[[ -v TEST_FLAG ]] || readonly -f state::_dir

#--------------------------------------------------
# Function:
#   state::_key <id>
#
# Description:
#   Prints a filesystem-safe token for an <id>, replacing every character
#   outside [A-Za-z0-9._@-] with an underscore (a workspace id holds a path with
#   slashes). Writes the token to stdout.
#
# Arguments:
#   <id>  The id to sanitise
#
# Returns:
#   0 on success
#
# Example:
#   state::_key 'workspaces/api@/srv/api'
#--------------------------------------------------
state::_key() {
    printf '%s' "${1//[^A-Za-z0-9._@-]/_}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_key

#--------------------------------------------------
# Function:
#   state::_envname <name>
#
# Description:
#   Prints the environment variable name an input is read from, upper-casing the
#   input name and replacing every non-alphanumeric character with an underscore
#   (for example git.name -> GIT_NAME), so a non-interactive run can supply
#   inputs without prompting. Writes the name to stdout.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 on success
#
# Example:
#   state::_envname git.name
#--------------------------------------------------
state::_envname() {
    local name

    name="${1//[^A-Za-z0-9]/_}"

    printf '%s' "${name^^}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_envname

#--------------------------------------------------
# Function:
#   state::_put <file> <value>
#
# Description:
#   Writes <value> to <file>, creating the parent directory first, with no
#   trailing newline so reads round-trip. Writes a file.
#
# Arguments:
#   <file>   The destination path
#   <value>  The value to store
#
# Returns:
#   0 on success
#   non-zero when the write fails
#
# Example:
#   state::_put "$dir/git.name" 'Ada'
#--------------------------------------------------
state::_put() {
    local file
    local value

    file="$1"
    value="$2"
    mkdir -p "$(dirname "$file")"

    printf '%s' "$value" >"$file"
}
[[ -v TEST_FLAG ]] || readonly -f state::_put

#--------------------------------------------------
# Function:
#   state::set <name> <value>
#
# Description:
#   Writes an input value unconditionally, the write-side counterpart to
#   state::input (which reads) and to state::ask (which resolves an input once and
#   skips when already saved). A flow that drives its own prompts - showing
#   defaults, re-prompting on a duplicate or on Esc, things state::ask's
#   resolve-once-skip model cannot do - persists the result here. Writes the input
#   file with no trailing newline so reads round-trip.
#
# Arguments:
#   <name>   The input name
#   <value>  The value to store
#
# Returns:
#   0 on success
#   non-zero when the write fails
#
# Example:
#   state::set workspace.personal.path /home/ada/Workspace/Personal
#--------------------------------------------------
state::set() {
    local name
    local value
    local working

    name="$1"
    value="$2"
    working="${MACHINE_SETUP_INPUTS_WORKING:-}"

    if [[ -n "$working" ]]
    then
        state::_put "$working/$name" "$value"
    else
        state::_put "$(state::_root)/inputs/$name" "$value"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::set

#--------------------------------------------------
# Function:
#   state::input <name>
#
# Description:
#   Prints a saved input value to stdout. Writes an error to stderr when no
#   value was saved.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 when the value is found
#   1 when no saved input exists
#
# Example:
#   state::input git.name
#--------------------------------------------------
state::input() {
    local committed
    local working

    working="${MACHINE_SETUP_INPUTS_WORKING:-}"
    if [[ -n "$working" && -f "$working/$1" ]]
    then
        cat "$working/$1"

        return 0
    fi

    committed="$(state::_root)/inputs/$1"
    if [[ ! -f "$committed" ]]
    then
        output::fatal "no saved input: $1"

        return 1
    fi

    cat "$committed"
}
[[ -v TEST_FLAG ]] || readonly -f state::input

#--------------------------------------------------
# Function:
#   state::unset <name>
#
# Description:
#   Removes a saved input, the delete-side counterpart to state::set. Idempotent:
#   removing an input that was never saved is a no-op, not an error. Removes the
#   input file.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 on success
#
# Example:
#   state::unset workspace.list
#--------------------------------------------------
state::unset() {
    rm -f "$(state::_root)/inputs/$1"

    if [[ -n "${MACHINE_SETUP_INPUTS_WORKING:-}" ]]
    then
        rm -f "$MACHINE_SETUP_INPUTS_WORKING/$1"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::unset

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling library is sourced regardless of
# the caller's working directory. Defined only when not already set, and made
# readonly outside tests so specs can reassign it.
if [[ -z "${LIB_DIR:-}" ]]
then
    LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    [[ -v TEST_FLAG ]] || readonly LIB_DIR
fi

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/screen.sh
source "$LIB_DIR/screen.sh"
