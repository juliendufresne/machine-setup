#!/usr/bin/env bash
set -euo pipefail
# Host probing used by units to decide whether they can install here.
# Sourced by lib/runner.sh.

! declare -F host::has_desktop &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   host::_session_entries
#
# Description:
#   Prints the basename of every desktop-session entry installed on this host,
#   one per line. Display managers populate /usr/share/xsessions (X11) and
#   /usr/share/wayland-sessions (Wayland) from the desktop-environment and
#   window-manager packages, so an entry there means a desktop is installed and
#   selectable at login, whether or not a session is currently running and
#   regardless of the terminal this runs from. The two directories are read from
#   HOST_XSESSIONS_DIR and HOST_WAYLAND_SESSIONS_DIR so specs can redirect them.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always
#
# Example:
#   host::_session_entries
#--------------------------------------------------
host::_session_entries() {
    local dir entry

    for dir in "${HOST_XSESSIONS_DIR:-/usr/share/xsessions}" \
               "${HOST_WAYLAND_SESSIONS_DIR:-/usr/share/wayland-sessions}"; do
        [[ -d "$dir" ]] || continue
        for entry in "$dir"/*.desktop; do
            [[ -e "$entry" ]] && printf '%s\n' "${entry##*/}"
        done
    done

    return 0
}
[[ -v TEST_FLAG ]] || readonly -f host::_session_entries

#--------------------------------------------------
# Function:
#   host::has_desktop
#
# Description:
#   Reports whether a graphical desktop is installed, so GUI apps can declare
#   `is_available() { host::has_desktop; }` and be skipped where they cannot run.
#   True when any desktop-session entry is installed (see host::_session_entries).
#   A headless server installs none, and neither does WSL: WSLg exports DISPLAY
#   and WAYLAND_DISPLAY for app forwarding but installs no session, which is why
#   this probes installed sessions rather than trusting those variables. Writes
#   nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a desktop session is installed
#   1 when none is (a headless server, or WSL)
#
# Example:
#   host::has_desktop
#--------------------------------------------------
host::has_desktop() {
    [[ -n "$(host::_session_entries)" ]]
}
[[ -v TEST_FLAG ]] || readonly -f host::has_desktop
