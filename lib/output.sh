#!/usr/bin/env bash
set -euo pipefail
# Consistent terminal output: a magenta stage header per unit, indented
# per-command lines (success, info, error) beneath it, a spinner that announces
# a long command and shows its output only on failure, and program-level fatal
# diagnostics. Colours are gated per call by output::color_enabled, so a pipe, a
# log file, or the test runner gets plain text. Sourced by lib/runner.sh and the
# unit scripts; never executed on its own.

! declare -F output::color_enabled &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   output::color_enabled <fd>
#
# Description:
#   Reports whether coloured output should be emitted on the given file
#   descriptor, that is whether that descriptor is attached to a terminal. Output
#   redirected to a file or a pipe (CI logs, command substitution, the shellspec
#   capture) is therefore left uncoloured. Writes nothing.
#
# Arguments:
#   <fd>  File descriptor number to test (1 for stdout, 2 for stderr)
#
# Returns:
#   0 when the descriptor is a terminal
#   1 otherwise
#
# Example:
#   output::color_enabled 1 && printf 'colours on\n'
#--------------------------------------------------
output::color_enabled() {
    [[ -t "$1" ]]
}
[[ -v TEST_FLAG ]] || readonly -f output::color_enabled

#--------------------------------------------------
# Function:
#   output::stage <message>
#
# Description:
#   Opens a stage, the top-level header for one unit's action, shown as
#   "▶ <message>" in bold magenta when stdout is a terminal. The stage is
#   preceded by a blank line so consecutive units are visually separated. Writes
#   to stdout.
#
# Arguments:
#   <message>  Stage title (for example "Installing git")
#
# Returns:
#   0 on success
#
# Example:
#   output::stage 'Installing git'
#--------------------------------------------------
output::stage() {
    local message

    message="$1"

    if output::color_enabled 1
    then
        printf '\n%b%s %s%b\n' "$OUTPUT_MAGENTA" "$OUTPUT_GLYPH_STAGE" "$message" "$OUTPUT_RESET"

        return 0
    fi

    printf '\n%s %s\n' "$OUTPUT_GLYPH_STAGE" "$message"
}
[[ -v TEST_FLAG ]] || readonly -f output::stage

#--------------------------------------------------
# Function:
#   output::log <message>
#
# Description:
#   Opens a run phase, the top-level heading that groups several unit stages
#   (collecting inputs, installing, configuring, and so on). Shown as "» <message>"
#   in bold when stderr is a terminal. A level above output::stage, which heads a
#   single unit's action. Written to stderr so stdout is left clean for callers that
#   capture a unit's output (for example the status report).
#
# Arguments:
#   <message>  Phase title (for example "Installing the selected units...")
#
# Returns:
#   0 on success
#
# Example:
#   output::log 'Installing the selected units...'
#--------------------------------------------------
output::log() {
    local message

    message="$1"

    if output::color_enabled 2
    then
        printf '%b%s %s%b\n' "$OUTPUT_BOLD" "$OUTPUT_GLYPH_PHASE" "$message" "$OUTPUT_RESET" >&2

        return 0
    fi

    printf '%s %s\n' "$OUTPUT_GLYPH_PHASE" "$message" >&2
}
[[ -v TEST_FLAG ]] || readonly -f output::log

#--------------------------------------------------
# Function:
#   output::success <message>
#
# Description:
#   Writes an indented success line, "  ✓ <message>", beneath the current stage,
#   rendered green when stdout is a terminal. Reports a command that completed.
#   Writes to stdout.
#
# Arguments:
#   <message>  Text to print
#
# Returns:
#   0 on success
#
# Example:
#   output::success 'Installing the git package'
#--------------------------------------------------
output::success() {
    local message

    message="$1"

    if output::color_enabled 1
    then
        printf '%s%b%s %s%b\n' "$OUTPUT_INDENT" "$OUTPUT_GREEN" "$OUTPUT_GLYPH_SUCCESS" "$message" "$OUTPUT_RESET"

        return 0
    fi

    printf '%s%s %s\n' "$OUTPUT_INDENT" "$OUTPUT_GLYPH_SUCCESS" "$message"
}
[[ -v TEST_FLAG ]] || readonly -f output::success

#--------------------------------------------------
# Function:
#   output::info <message>
#
# Description:
#   Writes an indented info line, "  • <message>", beneath the current stage,
#   rendered dim when stdout is a terminal. The neutral level for routine
#   progress (already installed, nothing to do). Writes to stdout.
#
# Arguments:
#   <message>  Text to print
#
# Returns:
#   0 on success
#
# Example:
#   output::info 'already installed'
#--------------------------------------------------
output::info() {
    local message

    message="$1"

    if output::color_enabled 1
    then
        printf '%s%b%s %s%b\n' "$OUTPUT_INDENT" "$OUTPUT_DIM" "$OUTPUT_GLYPH_INFO" "$message" "$OUTPUT_RESET"

        return 0
    fi

    printf '%s%s %s\n' "$OUTPUT_INDENT" "$OUTPUT_GLYPH_INFO" "$message"
}
[[ -v TEST_FLAG ]] || readonly -f output::info

#--------------------------------------------------
# Function:
#   output::warn <message>
#
# Description:
#   Writes an indented warning line, "  ! <message>", beneath the current stage to
#   stderr, rendered yellow when stderr is a terminal. Reports a non-fatal caution
#   the user should see but that does not fail the run (for example software still
#   present after an uninstall because it was installed by other means). Writes to
#   stderr.
#
# Arguments:
#   <message>  Text to print
#
# Returns:
#   0 on success
#
# Example:
#   output::warn 'git is still present; it may be installed by other means'
#--------------------------------------------------
output::warn() {
    local message

    message="$1"

    if output::color_enabled 2
    then
        printf '%s%b%s %s%b\n' "$OUTPUT_INDENT" "$OUTPUT_YELLOW" "$OUTPUT_GLYPH_WARN" "$message" "$OUTPUT_RESET" >&2

        return 0
    fi

    printf '%s%s %s\n' "$OUTPUT_INDENT" "$OUTPUT_GLYPH_WARN" "$message" >&2
}
[[ -v TEST_FLAG ]] || readonly -f output::warn

#--------------------------------------------------
# Function:
#   output::error <message>
#
# Description:
#   Writes an indented error line, "  ✗ <message>", beneath the current stage to
#   stderr, rendered red when stderr is a terminal. Reports a command within a
#   stage that failed. Writes to stderr.
#
# Arguments:
#   <message>  Text to print
#
# Returns:
#   0 on success
#
# Example:
#   output::error 'Installing the git package'
#--------------------------------------------------
output::error() {
    local message

    message="$1"

    if output::color_enabled 2
    then
        printf '%s%b%s %s%b\n' "$OUTPUT_INDENT" "$OUTPUT_RED" "$OUTPUT_GLYPH_ERROR" "$message" "$OUTPUT_RESET" >&2

        return 0
    fi

    printf '%s%s %s\n' "$OUTPUT_INDENT" "$OUTPUT_GLYPH_ERROR" "$message" >&2
}
[[ -v TEST_FLAG ]] || readonly -f output::error

#--------------------------------------------------
# Function:
#   output::fatal <message>
#
# Description:
#   Writes a flush-left, program-level error to stderr as "error: <message>",
#   rendered red when stderr is a terminal. Used for dispatch and usage failures
#   that abort the run around a stage (requirements not met, an unknown action, no
#   unit for the host, a missing input), as opposed to the in-stage command
#   failures output::error reports. Writes to stderr.
#
# Arguments:
#   <message>  Text to print
#
# Returns:
#   0 on success
#
# Example:
#   output::fatal 'requirements not met'
#--------------------------------------------------
output::fatal() {
    local message

    message="$1"

    if output::color_enabled 2
    then
        printf '%berror: %s%b\n' "$OUTPUT_RED" "$message" "$OUTPUT_RESET" >&2

        return 0
    fi

    printf 'error: %s\n' "$message" >&2
}
[[ -v TEST_FLAG ]] || readonly -f output::fatal

# ─── Constants / globals ────────────────────────────────────────────────────────

# ANSI escape sequences, emitted with printf '%b' and gated at the call site by
# output::color_enabled, so a non-terminal stream never receives them. Defined
# once (the guard above makes that exactly once).
OUTPUT_RESET='\033[0m'
OUTPUT_BOLD='\033[1m'
OUTPUT_MAGENTA='\033[1;35m'
OUTPUT_GREEN='\033[0;32m'
OUTPUT_DIM='\033[2m'
OUTPUT_RED='\033[0;31m'
OUTPUT_YELLOW='\033[0;33m'
[[ -v TEST_FLAG ]] || readonly OUTPUT_RESET OUTPUT_BOLD OUTPUT_MAGENTA OUTPUT_GREEN OUTPUT_DIM OUTPUT_RED OUTPUT_YELLOW

# Line vocabulary: the indent shared by every in-stage line and the glyph that
# prefixes each. A run phase (output::log) heads a group of stages with », a level
# above the per-unit stage ▶. Plain ASCII-width marks so alignment holds across
# terminals.
OUTPUT_INDENT='  '
OUTPUT_GLYPH_PHASE='»'
OUTPUT_GLYPH_STAGE='▶'
OUTPUT_GLYPH_SUCCESS='✓'
OUTPUT_GLYPH_INFO='•'
OUTPUT_GLYPH_WARN='!'
OUTPUT_GLYPH_ERROR='✗'
[[ -v TEST_FLAG ]] || readonly OUTPUT_INDENT OUTPUT_GLYPH_PHASE OUTPUT_GLYPH_STAGE OUTPUT_GLYPH_SUCCESS OUTPUT_GLYPH_INFO OUTPUT_GLYPH_WARN OUTPUT_GLYPH_ERROR
