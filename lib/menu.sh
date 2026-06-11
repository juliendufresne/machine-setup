#!/usr/bin/env bash
set -euo pipefail
# An interactive checkbox menu over a list of units. menu::select draws a
# checklist, lets the user move with the arrow keys (or j/k), toggle with space,
# and confirm with Enter, and prints the names left selected. The draw loop reads
# keystrokes from MENU_INPUT and draws to MENU_OUTPUT (both default to /dev/tty
# and are overridable to make it testable); with nothing to choose from or no
# terminal it emits the pre-selected entries as-is, so an unattended run still
# resolves a selection. Sourced by bin/machine-setup.

! declare -F menu::read_key &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   menu::read_key <fd>
#
# Description:
#   Reads one keystroke from file descriptor <fd> and prints a logical key token
#   to stdout: 'up', 'down', 'toggle', 'confirm', or 'cancel'. The mapping covers
#   both arrow keys (the ESC '[A' / ESC '[B' sequences) and the vi-style 'j'/'k'
#   keys for movement, the space bar for toggling, Enter for confirming, and a
#   bare Escape or 'q' for cancelling. An unrecognised key prints nothing so the
#   caller ignores it. Reads from <fd> only (with echo suppressed); no other side
#   effects.
#
# Arguments:
#   <fd>  An open file descriptor to read the keystroke from
#
# Returns:
#   0 when a keystroke was read (its token, if any, is printed)
#   1 when <fd> is at end of input, so the caller can treat it as a confirm
#
# Example:
#   key="$(menu::read_key "$fd")" || key='confirm'
#--------------------------------------------------
menu::read_key() {
    local fd
    local key
    local rest

    fd="${1:?file descriptor required}"

    IFS= read -rsn1 -u "$fd" key || return 1

    case "$key" in
        '')
            printf 'confirm'
            ;;
        ' ')
            printf 'toggle'
            ;;
        j | J)
            printf 'down'
            ;;
        k | K)
            printf 'up'
            ;;
        q | Q)
            printf 'cancel'
            ;;
        $'\e')
            # An escape sequence: the two trailing bytes name the arrow key. A
            # short timeout means a lone Escape falls through as a cancel.
            read -rsn2 -t 1 -u "$fd" rest || rest=''

            case "$rest" in
                '[A')
                    printf 'up'
                    ;;
                '[B')
                    printf 'down'
                    ;;
                *)
                    printf 'cancel'
                    ;;
            esac
            ;;
        *)
            : # Unrecognised key; print nothing so the caller ignores it.
            ;;
    esac
}
[[ -v TEST_FLAG ]] || readonly -f menu::read_key

#--------------------------------------------------
# Function:
#   menu::select <entry>...
#
# Description:
#   Drives an interactive checklist over the given entries and prints the names
#   the user leaves selected, one per line, to stdout. Each <entry> is a
#   tab-separated '<state>\t<name>\t<description>' triple, where <state> is 1 for
#   pre-selected and 0 otherwise. The arrow keys (or j/k) move the highlight,
#   space toggles the entry under it, and Enter confirms; the checklist is drawn
#   to MENU_OUTPUT and keystrokes are read from MENU_INPUT (both default to
#   /dev/tty, and are overridable to make the loop testable). When there is
#   nothing to choose from, or no terminal is available (MENU_INPUT or
#   MENU_OUTPUT cannot be opened, as in an unattended run), it skips the
#   interaction and emits the pre-selected entries as-is, so a selection still
#   resolves. The header line printed above the checklist is MENU_PROMPT,
#   defaulting to the set-up wording, so a caller (such as the uninstall menu)
#   can make clear what toggling an entry on will do. When a sticky-header screen
#   is open it first clears the region and prints the SCREEN_HELP help line to
#   SCREEN_OUTPUT (a no-op otherwise). Draws the checklist to MENU_OUTPUT and
#   consumes keystrokes from MENU_INPUT; stdout carries only the result.
#
# Arguments:
#   <entry>...  Zero or more '<state>\t<name>\t<description>' triples
#
# Returns:
#   0 when a selection was produced (possibly empty)
#
# Example:
#   menu::select "$(printf '1\tgit\tVersion control')" "$(printf '0\tdiscord\tChat')"
#--------------------------------------------------
menu::select() {
    local box
    local -i cursor
    local -a descs
    local -i drawn
    local -i fd
    local -i index
    local input
    local interactive
    local item
    local key
    local marker
    local -a names
    local output
    local prompt
    local -a states

    input="${MENU_INPUT:-/dev/tty}"
    output="${MENU_OUTPUT:-/dev/tty}"

    names=()
    descs=()
    states=()
    for item in "$@"
    do
        states+=("${item%%$'\t'*}")
        item="${item#*$'\t'}"
        names+=("${item%%$'\t'*}")
        descs+=("${item#*$'\t'}")
    done

    # Drive the checklist only when there is something to choose from and the
    # terminal can actually be opened, for reading keystrokes and drawing to;
    # otherwise fall through to the final emit, which prints the pre-selected
    # entries as-is so an unattended run still resolves a selection. A permission
    # test (-r/-w) is not enough: a /dev/tty device node can pass it yet fail to
    # open when there is no controlling terminal (an unattended run, such as the
    # install-test container), so probe by opening each descriptor and discarding
    # the open error.
    interactive=''
    if ((${#names[@]} > 0)) \
        && { : <"$input"; } 2>/dev/null \
        && { : >>"$output"; } 2>/dev/null
    then
        interactive=1
    fi

    if [[ -n "$interactive" ]]
    then
        # Clear the region under any open sticky header and draw the help line
        # once, before the list and its redraw loop, so navigation does not
        # flicker them. Both are no-ops when no screen is open.
        screen::region
        screen::help

        prompt="${MENU_PROMPT:-Select units to set up. Arrows or j/k move, space toggles, Enter confirms.}"
        printf '%s\n' "$prompt" >"$output"

        cursor=0
        drawn=0
        exec {fd}<"$input"

        while true
        do
            # Redraw in place: after the first frame, jump the cursor back up over
            # the rows just drawn, then clear and rewrite each line.
            ((! drawn)) || printf '%b' "\033[${#names[@]}A" >"$output"
            drawn=1

            for ((index = 0; index < ${#names[@]}; index++))
            do
                marker=' '
                ((index != cursor)) || marker='>'
                box='[ ]'
                ((! states[index])) || box='[x]'

                printf '%b  %s %s %-12s %s\n' "\033[2K" "$marker" "$box" "${names[index]}" "${descs[index]}" >"$output"
            done

            key="$(menu::read_key "$fd")" || key='confirm'
            case "$key" in
                up)
                    ((cursor > 0)) && cursor=$((cursor - 1)) || cursor=$((${#names[@]} - 1))
                    ;;
                down)
                    ((cursor < ${#names[@]} - 1)) && cursor=$((cursor + 1)) || cursor=0
                    ;;
                toggle)
                    states[cursor]=$((1 - states[cursor]))
                    ;;
                confirm | cancel)
                    break
                    ;;
                *)
                    : # Unrecognised key; redraw unchanged.
                    ;;
            esac
        done

        exec {fd}<&-
    fi

    for ((index = 0; index < ${#names[@]}; index++))
    do
        ((! states[index])) || printf '%s\n' "${names[index]}"
    done
}
[[ -v TEST_FLAG ]] || readonly -f menu::select

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
