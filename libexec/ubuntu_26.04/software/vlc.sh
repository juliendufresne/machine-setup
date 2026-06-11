#!/usr/bin/env bash
set -euo pipefail

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether VLC can be installed on this host. VLC is a GUI application,
#   so it requires a graphical desktop and is unavailable on a headless server.
#   Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a desktop is present
#   1 when the host is headless
#
# Example:
#   unit::is_available
#--------------------------------------------------
unit::is_available() {
    host::has_desktop
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_available

#--------------------------------------------------
# Function:
#   unit::is_installed
#
# Description:
#   Reports whether VLC is present on the host by any means, by resolving the vlc
#   command. This is the broad "is it usable" check, distinct from
#   unit::is_managed, which asks only whether it came from our package. command
#   -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when vlc is present
#   1 when vlc is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v vlc &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether VLC is installed through the mechanism this unit uses, the vlc
#   apt/dpkg package, by querying dpkg. The runner compares this against
#   unit::is_installed to refuse adopting a copy that arrived another way. dpkg's
#   own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the vlc package is installed
#   1 when it is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s vlc &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   VLC has no inputs to collect. It only warms the sudo session, because the
#   install and uninstall steps need root.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   unit::request_inputs
#--------------------------------------------------
unit::request_inputs() {
    sudo::warmup
}
[[ -v TEST_FLAG ]] || readonly -f unit::request_inputs

#--------------------------------------------------
# Function:
#   unit::install
#
# Description:
#   Installs VLC from Ubuntu's own apt repository, where it ships: refreshes the
#   package lists, then installs the vlc package. apt-get install upgrades an
#   already-present package, so re-running install is idempotent. Each step is
#   announced through output::run. Needs root through sudo.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing step's exit status when a step fails
#
# Example:
#   unit::install
#--------------------------------------------------
unit::install() {
    output::run 'Updating the package lists' sudo apt-get update -qq || return $?
    output::run 'Installing the vlc package' sudo apt-get install -y vlc
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Purges the vlc package with apt-get, announced through output::run. Uninstall
#   is unconditional, so a user who asks to uninstall always gets a clean removal.
#   Needs root through sudo.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   apt-get's exit status when it fails
#
# Example:
#   unit::uninstall
#--------------------------------------------------
unit::uninstall() {
    output::run 'Purging the vlc package' sudo apt-get purge -y vlc
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   vlc::main [<action>]
#
# Description:
#   Entry point for direct execution. Hands the requested action to the shared
#   runner, which drives the install/uninstall/status step sequence using the
#   unit::* contract functions defined above.
#
# Arguments:
#   <action>  install (default), uninstall, or status
#
# Returns:
#   the runner's exit status for the action
#
# Example:
#   vlc::main install
#--------------------------------------------------
vlc::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f vlc::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || vlc::main "$@"
