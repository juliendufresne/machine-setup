#!/usr/bin/env bash
set -euo pipefail
# The software module: everything the orchestrator does with a piece of software, the
# per-OS file libexec/<os>_<version>/software/<name>.sh (the OS token resolved through
# lib/os.sh). It discovers the pieces this host can run, runs one action against one
# piece (the single seam install, uninstall, and status all funnel through), resolves
# a piece's status to a single word, drives the interactive checklists (set-up and
# removal), refreshes the host package manager once for the whole run, stages and runs
# the install and uninstall phases, and renders the status table. The provisioners are
# not software and are never handled here: they are a fixed post-install step driven
# through lib/provisioner.sh. Sourced by bin/machine-setup.

! declare -F software::discover &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   software::discover
#
# Description:
#   Lists the software names, one per line on stdout: one file per piece under the
#   host OS token's software/ directory (libexec/<os>_<version>/software/<name>.sh,
#   the OS token resolved through lib/os.sh), named by its basename minus .sh and
#   glob-sorted so the listing is stable. Only software is discovered; the workspace
#   and dotfiles provisioners are a fixed post-install step (PROVISIONERS), never
#   listed here. Reads the software directory only; no side effects.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always
#
# Example:
#   software::discover
#--------------------------------------------------
software::discover() {
    local entry
    local name

    # One file per piece of software under the host OS token's software/ directory.
    # With no matching file the unexpanded glob fails the -f test and is skipped.
    for entry in "$LIBEXEC_DIR/$(os::file_token)/software"/*.sh
    do
        [[ -f "$entry" ]] || continue

        name="$(basename "$entry")"
        printf '%s\n' "${name%.sh}"
    done
}
[[ -v TEST_FLAG ]] || readonly -f software::discover

#--------------------------------------------------
# Function:
#   software::run <name> <action>
#
# Description:
#   Runs one action against one piece of software by executing its per-OS file with
#   the action: libexec/<os>_<version>/software/<name>.sh, the OS token resolved
#   through lib/os.sh. The single seam through which the orchestrator reaches a piece
#   of software, so install, uninstall, and status all funnel through here (and the
#   suite stubs it to drive the higher-level helpers without real software). Carries
#   the software's own output and exit status straight through.
#
# Arguments:
#   <name>    The software name (a per-OS software file basename)
#   <action>  The action to run (install, uninstall, status, step-install-inputs, ...)
#
# Returns:
#   the exit status the software executable propagates
#
# Example:
#   software::run tree status
#--------------------------------------------------
software::run() {
    local action
    local name

    name="${1:?software name required}"
    action="${2:?action required}"

    "$LIBEXEC_DIR/$(os::file_token)/software/$name.sh" "$action"
}
[[ -v TEST_FLAG ]] || readonly -f software::run

#--------------------------------------------------
# Function:
#   software::status_of <name>
#
# Description:
#   Resolves a piece of software's status to a single word and prints it to stdout,
#   by running its status action (one of unavailable, available, unmanaged,
#   installed, configured). The single-value form the menus need to decide
#   availability and pre-ticking. The status action always succeeds for software
#   that can run on this host; a failure (a missing executable for a bad name)
#   propagates.
#
# Arguments:
#   <name>  The software name whose status to resolve
#
# Returns:
#   0 when the status was read (the word is printed)
#   the exit status the software propagates on failure
#
# Example:
#   software::status_of tree
#--------------------------------------------------
software::status_of() {
    local name

    name="${1:?software name required}"

    software::run "$name" status
}
[[ -v TEST_FLAG ]] || readonly -f software::status_of

#--------------------------------------------------
# Function:
#   software::description_of <name>
#
# Description:
#   Prints a software unit's one-line description to stdout, read from
#   share/machine-setup/<name>/description, or nothing when the file is absent. Only
#   the first line is used, so a stray trailing newline never widens the menu. Reads
#   the description file only; no side effects.
#
# Arguments:
#   <name>  The software unit name whose description to read
#
# Returns:
#   0 always (the description, possibly empty, is printed)
#
# Example:
#   software::description_of tree
#--------------------------------------------------
software::description_of() {
    local description
    local file
    local name

    name="${1:?name required}"
    file="$SHARE_DIR/$name/description"
    [[ -f "$file" ]] || return 0

    IFS= read -r description <"$file" || true

    printf '%s' "$description"
}
[[ -v TEST_FLAG ]] || readonly -f software::description_of

#--------------------------------------------------
# Function:
#   software::mark <flag>
#
# Description:
#   Prints a status cell: a green check when <flag> is non-zero (true), a red cross
#   when it is 0 (false), or a dimmed dash when it is '-' (not applicable, for a column
#   that carries no meaning - an unavailable unit is neither installed nor not). The
#   colour is gated on stdout being a terminal, so a captured report receives the bare
#   glyph and stays plain (and stable for tests). The glyph is one visible column wide
#   either way, so the caller can pad around it. Writes the cell to stdout.
#
# Arguments:
#   <flag>  1 (or any non-zero number) for true, 0 for false, '-' for not applicable
#
# Returns:
#   0 always
#
# Example:
#   software::mark 1
#--------------------------------------------------
software::mark() {
    local color
    local glyph

    case "$1" in
        -)
            glyph='-'
            color="$OUTPUT_DIM"
            ;;
        0)
            glyph="$OUTPUT_GLYPH_ERROR"
            color="$OUTPUT_RED"
            ;;
        *)
            glyph="$OUTPUT_GLYPH_SUCCESS"
            color="$OUTPUT_GREEN"
            ;;
    esac

    if output::color_enabled 1
    then
        printf '%b%s%b' "$color" "$glyph" "$OUTPUT_RESET"
    else
        printf '%s' "$glyph"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f software::mark

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

# Directory holding the software executables: the per-OS software files under
# <os>_<version>/software/. The provisioners own no executable here; they are driven
# in-process through the framework (lib/provisioner.sh). Overridable through
# MACHINE_SETUP_LIBEXEC_DIR so the suite can point it at fixtures.
LIBEXEC_DIR="${MACHINE_SETUP_LIBEXEC_DIR:-${LIB_DIR%/*}/libexec}"
[[ -v TEST_FLAG ]] || readonly LIBEXEC_DIR

# Directory holding the per-name descriptions (share/machine-setup/<name>/description),
# for both software and the provisioners. Overridable through MACHINE_SETUP_SHARE_DIR
# so the suite can point it at fixtures.
SHARE_DIR="${MACHINE_SETUP_SHARE_DIR:-${LIB_DIR%/*}/share/machine-setup}"
[[ -v TEST_FLAG ]] || readonly SHARE_DIR

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/os.sh
source "$LIB_DIR/os.sh"
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/menu.sh
source "$LIB_DIR/menu.sh"
# shellcheck source=lib/screen.sh
source "$LIB_DIR/screen.sh"
