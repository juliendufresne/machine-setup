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

#--------------------------------------------------
# Function:
#   software::cell <flag> <width>
#
# Description:
#   Prints a status cell (software::mark) left-aligned in a column <width>
#   visible columns wide, padding with trailing spaces after the one-column glyph.
#   Padding is by visible width, not byte count, so the columns line up whether or
#   not the glyph carries colour codes. For the last column of a row, print the mark
#   directly instead, so no trailing whitespace is emitted. Writes the padded cell to
#   stdout.
#
# Arguments:
#   <flag>   1 for true, 0 for false (see software::mark)
#   <width>  The column width in visible columns
#
# Returns:
#   0 always
#
# Example:
#   software::cell 1 9
#--------------------------------------------------
software::cell() {
    software::mark "$1"
    printf '%*s' "$(($2 - 1))" ''
}
[[ -v TEST_FLAG ]] || readonly -f software::cell

#--------------------------------------------------
# Function:
#   software::status_table
#
# Description:
#   Renders the software status table to stdout, reading one line per unit from stdin.
#   Each line is '<name>\t<word>\t<managed>' and it prints the four-column table
#   (name, available, installed, managed): the status word fixes available (every word
#   but 'unavailable') and installed (every word from 'unmanaged' on, present on the
#   host), while managed comes from the explicit <managed> flag (1 or 0), so it
#   reflects the state store's ownership marker - whether we installed and configured
#   it - not the unit's is_managed word, which for a package only asks whether the
#   package is present. The name column is right-padded to its widest entry (at least
#   the 'name' header) so the table lines up; the cells are green checks or red crosses
#   (software::mark). A unit the host cannot run (not available) shows a dimmed dash
#   rather than a cross in the installed and managed columns it leaves false, since
#   being absent is not a failure for software that cannot run here. With no input
#   lines it prints nothing (the caller skips the section). Reads stdin; writes the
#   table to stdout.
#
# Arguments:
#   (none)
#
# Returns:
#   0 always
#
# Example:
#   printf 'git\tconfigured\t1\n' | software::status_table
#--------------------------------------------------
software::status_table() {
    local -i available
    local -i installed
    local installed_cell
    local line
    local -i managed
    local managed_cell
    local name
    local -i namew
    local rest
    local -a rows
    local word

    mapfile -t rows
    ((${#rows[@]} > 0)) || return 0

    # The name column is as wide as its widest entry, never narrower than its header.
    namew=4
    for line in "${rows[@]}"
    do
        name="${line%%$'\t'*}"
        ((${#name} <= namew)) || namew=${#name}
    done

    printf '%-*s  %-9s  %-9s  %s\n' "$namew" 'name' 'available' 'installed' 'managed'
    for line in "${rows[@]}"
    do
        name="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        word="${rest%%$'\t'*}"
        # managed is the explicit state-ownership flag, not derived from the word.
        managed="${rest##*$'\t'}"

        # The word fixes availability and presence; ownership comes from the flag.
        available=0
        [[ "$word" == unavailable ]] || available=1

        installed=0
        case "$word" in
            unmanaged | installed | configured) installed=1 ;;
        esac

        # An unavailable unit cannot be installed or managed here, so a cross would
        # read as a failure where there is none: show a dash for whichever of the two
        # is false. A unit present by other means still reads as a check.
        installed_cell="$installed"
        managed_cell="$managed"
        if ((!available))
        then
            ((installed)) || installed_cell='-'
            ((managed)) || managed_cell='-'
        fi

        printf '%-*s  ' "$namew" "$name"
        software::cell "$available" 9
        printf '  '
        software::cell "$installed_cell" 9
        printf '  '
        software::mark "$managed_cell"
        printf '\n'
    done
}
[[ -v TEST_FLAG ]] || readonly -f software::status_table

#--------------------------------------------------
# Function:
#   software::status_report [name]...
#
# Description:
#   Reports each piece of software's status as one aligned table on stdout (name,
#   available, installed, managed). With names given it reports exactly those; with
#   none it reports every discovered piece. The provisioners are not software, so a
#   provisioner name resolves to no software file and is reported as a read error
#   like any other unknown name. Each piece's status word is read once
#   (software::status_of) and handed to the table (software::status_table),
#   which maps it to the boolean columns. The managed column comes from the state
#   store's ownership marker (state::owned), set only when our own install and
#   configure succeeded, not from the status word, so software present by other means
#   (an apt install by hand) reads as installed but not managed. A piece whose status
#   cannot be read (a bad name with no executable) is reported as an error on stderr
#   and does not abandon the rest; the worst exit status seen is returned. Writes the
#   report to stdout and any diagnostics to stderr.
#
# Arguments:
#   [name]...  Zero or more software names; when none, every discovered piece is reported
#
# Returns:
#   0 when every unit was reported
#   N the worst exit status seen across the units
#
# Example:
#   software::status_report git tree
#--------------------------------------------------
software::status_report() {
    local -i exit_status
    local -i failure
    local listing
    local -i managed
    local name
    local -a names
    local -a software
    local word

    if (($# > 0))
    then
        names=("$@")
    else
        listing="$(software::discover)"
        names=()
        [[ -z "$listing" ]] || mapfile -t names <<<"$listing"
    fi

    # Read each piece's status once. A piece whose status cannot be read is reported
    # and skipped, the worst status carried out. A software line also carries its
    # managed flag: the state store's ownership marker (state::owned), set only when
    # our own install and configure succeeded, rather than the unit's is_managed word
    # - which for a package only asks whether the package is present, so an apt install
    # by hand would satisfy it and wrongly read as managed.
    exit_status=0
    software=()
    for name in "${names[@]}"
    do
        if word="$(software::status_of "$name")"
        then
            managed=0
            ! state::owned "$name" || managed=1
            software+=("$(printf '%s\t%s\t%d' "$name" "$word" "$managed")")
        else
            failure=$?
            output::fatal "could not read the status of '$name'."
            ((failure <= exit_status)) || exit_status=$failure
        fi
    done

    if ((${#software[@]} > 0))
    then
        printf '%s\n' "${software[@]}" | software::status_table
    fi

    return "$exit_status"
}
[[ -v TEST_FLAG ]] || readonly -f software::status_report

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
