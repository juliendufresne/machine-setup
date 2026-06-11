#!/usr/bin/env bash
set -euo pipefail
# A single sticky-header "screen" for the interactive input flows, the dialog feel
# without depending on dialog. screen::open clears the terminal and pins a short
# header describing what is being collected; the region below it is used for one
# input at a time. The interactive primitives (menu::select and state::ask) call
# screen::region to clear that region and redraw the header before each input, and
# screen::help to print the per-input help line, but only while a screen is open.
# With no screen open (every plain call site) and on any terminal that cannot be
# opened (an unattended or no-tty run) every function here is a no-op, so existing
# output is unchanged. Self-contained with no imports, so any library can source it
# safely; sourced by lib/menu.sh and lib/state.sh.

! declare -F screen::open &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   screen::supported
#
# Description:
#   Reports whether a screen can be drawn, by probing SCREEN_OUTPUT (default
#   /dev/tty) for writing. The same open-probe lib/menu.sh uses:
#   a /dev/tty device node can pass a permission test yet fail to open with no
#   controlling terminal, so the descriptor is opened and the open error
#   discarded. Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when SCREEN_OUTPUT can be opened for writing
#   1 otherwise
#
# Example:
#   screen::supported && screen::open 'Workspace setup'
#--------------------------------------------------
screen::supported() {
    local output

    output="${SCREEN_OUTPUT:-/dev/tty}"

    { : >>"$output"; } 2>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f screen::supported

#--------------------------------------------------
# Function:
#   screen::open <title> [<intro-line>...]
#
# Description:
#   Opens a sticky-header screen for a run of inputs. With no terminal
#   (screen::supported is false, as in an unattended run) it clears SCREEN_ACTIVE
#   and returns, so the flow falls back to plain, unframed prompts. Otherwise it
#   builds the header redrawn on every region clear - the <title>, a plain
#   separator rule, any intro lines, then a trailing blank line opening the region
#   below - marks the screen active, then clears the terminal and its scrollback,
#   homes the cursor, and draws the header. Sets SCREEN_ACTIVE and SCREEN_HEADER
#   and draws to SCREEN_OUTPUT.
#
# Arguments:
#   <title>          The header title naming what is being collected
#   <intro-line>...  Optional lines shown under the title (a one-line intro)
#
# Returns:
#   0 on success
#
# Example:
#   screen::open 'Workspace setup' 'Define one or more workspaces, then continue.'
#--------------------------------------------------
screen::open() {
    local intro
    local output
    local title

    title="${1:?title required}"
    shift

    if ! screen::supported
    then
        SCREEN_ACTIVE=''

        return 0
    fi

    SCREEN_HEADER="$title"$'\n'"$SCREEN_RULE"$'\n'
    for intro in "$@"
    do
        SCREEN_HEADER+="$intro"$'\n'
    done
    SCREEN_HEADER+=$'\n'                           # a blank line opens the region

    SCREEN_ACTIVE=1

    # Clear the screen and its scrollback, home the cursor, then draw the header.
    # Append, not truncate: on a terminal the two are identical (the cursor
    # escapes place the output, not the file offset), and appending lets a file
    # standing in for the terminal in a test accumulate the draws as the terminal
    # shows them.
    output="${SCREEN_OUTPUT:-/dev/tty}"
    printf '%b%s' '\033[2J\033[3J\033[H' "$SCREEN_HEADER" >>"$output"
}
[[ -v TEST_FLAG ]] || readonly -f screen::open

#--------------------------------------------------
# Function:
#   screen::region
#
# Description:
#   Clears the region under the sticky header, ready for the next input, and is the
#   first thing each interactive primitive calls. A no-op unless a screen is open
#   (SCREEN_ACTIVE), so a plain call site is unaffected. When active it homes the
#   cursor, reprints the header, then clears from the cursor to the end of the
#   screen, leaving the cursor in a fresh region below the header. Draws to
#   SCREEN_OUTPUT.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   screen::region
#--------------------------------------------------
screen::region() {
    local output

    [[ -n "${SCREEN_ACTIVE:-}" ]] || return 0

    output="${SCREEN_OUTPUT:-/dev/tty}"

    printf '%b%s%b' '\033[H' "$SCREEN_HEADER" '\033[0J' >>"$output"
}
[[ -v TEST_FLAG ]] || readonly -f screen::region

#--------------------------------------------------
# Function:
#   screen::help
#
# Description:
#   Prints the per-input help line into the region, the companion to
#   screen::region that each primitive calls right after clearing the region. A
#   no-op unless a screen is open (SCREEN_ACTIVE) and SCREEN_HELP is set, so a
#   plain call site - where SCREEN_HELP is unset - draws nothing. The help text and
#   a trailing blank line go to SCREEN_OUTPUT, leaving the cursor below them for the
#   prompt the primitive then draws. SCREEN_HELP is passed per input as a
#   command-prefix variable, the same convention as MENU_PROMPT.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   SCREEN_HELP='Where your repositories live.' state::ask workspace.path '...'
#--------------------------------------------------
screen::help() {
    local output

    [[ -n "${SCREEN_ACTIVE:-}" ]] || return 0
    [[ -n "${SCREEN_HELP:-}" ]] || return 0

    output="${SCREEN_OUTPUT:-/dev/tty}"

    printf '%s\n\n' "$SCREEN_HELP" >>"$output"
}
[[ -v TEST_FLAG ]] || readonly -f screen::help

#--------------------------------------------------
# Function:
#   screen::close
#
# Description:
#   Closes the screen a flow opened, so the scrolling output that follows starts
#   cleanly. A no-op unless a screen is open, so it is safe on every path. When
#   active it prints a trailing newline to SCREEN_OUTPUT, then clears SCREEN_ACTIVE
#   and SCREEN_HEADER. Draws to SCREEN_OUTPUT.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   screen::close
#--------------------------------------------------
screen::close() {
    local output

    [[ -n "${SCREEN_ACTIVE:-}" ]] || return 0

    output="${SCREEN_OUTPUT:-/dev/tty}"

    printf '\n' >>"$output"

    SCREEN_ACTIVE=''
    SCREEN_HEADER=''
}
[[ -v TEST_FLAG ]] || readonly -f screen::close

# ─── Constants / globals ────────────────────────────────────────────────────────

# A plain separator rule drawn under the header title. Fixed-width and ASCII so
# the header is deterministic without probing the terminal size and the spec
# assertions stay simple.
printf -v SCREEN_RULE '%*s' 60 ''
SCREEN_RULE="${SCREEN_RULE// /-}"
[[ -v TEST_FLAG ]] || readonly SCREEN_RULE

# The open-screen state, both mutable: SCREEN_ACTIVE is 1 while a screen is open
# and engaged (empty otherwise), and SCREEN_HEADER is the rendered sticky header
# redrawn on every region clear. Initialised empty so a no-tty run is a clean
# no-op.
SCREEN_ACTIVE=''
SCREEN_HEADER=''
