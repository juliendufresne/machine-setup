#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the spotify unit. The unit::* contract below drives these
# through output::run so each appears as one announced step.

#--------------------------------------------------
# Function:
#   spotify::_add_apt_repository
#
# Description:
#   Sets up Spotify's apt repository the way the official instructions do: creates
#   the keyring directory, downloads Spotify's signing key and dearmors it into the
#   keyring (the published key is ASCII-armored, so gpg --dearmor converts it to
#   the binary form apt needs), makes the key world-readable, then writes the
#   repository definition to /etc/apt/sources.list.d/spotify.list pinned to that
#   key. Needs root through sudo. Writes the key and the sources list, and discards
#   the curl/gpg/tee output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when a step fails
#
# Example:
#   spotify::_add_apt_repository
#--------------------------------------------------
spotify::_add_apt_repository() {
    sudo install -m 0755 -d /etc/apt/keyrings || return $?
    curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/spotify.gpg || return $?
    sudo chmod a+r /etc/apt/keyrings/spotify.gpg || return $?

    printf 'deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free\n' \
        | sudo tee /etc/apt/sources.list.d/spotify.list >/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f spotify::_add_apt_repository

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether Spotify can be installed on this host. Spotify is a GUI
#   application, so it requires a graphical desktop and is unavailable on a
#   headless server. Writes nothing.
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
#   Reports whether Spotify is present on the host by any means, by resolving the
#   spotify command. This is the broad "is it usable" check, distinct from
#   unit::is_managed, which asks only whether it came from our package. command
#   -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when spotify is present
#   1 when spotify is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v spotify &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether Spotify is installed through the mechanism this unit uses, the
#   spotify-client apt/dpkg package, by querying dpkg. The runner compares this
#   against unit::is_installed to refuse adopting a copy that arrived another way.
#   dpkg's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the spotify-client package is installed
#   1 when it is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s spotify-client &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   Spotify has no inputs to collect. It only warms the sudo session, because the
#   repository, install, and uninstall steps need root.
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
#   Installs Spotify the way the official instructions direct: refreshes the
#   package lists, installs the prerequisites, adds Spotify's apt repository,
#   refreshes the lists again, then installs the spotify-client package. Each step
#   is announced through output::run. Needs root through sudo.
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
    output::run 'Installing prerequisite packages' sudo apt-get install -y ca-certificates curl gnupg || return $?
    output::run 'Adding the Spotify apt repository' spotify::_add_apt_repository || return $?
    output::run 'Updating the package lists' sudo apt-get update -qq || return $?
    output::run 'Installing the spotify-client package' sudo apt-get install -y spotify-client
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Purges the spotify-client package with apt-get, announced through output::run.
#   Uninstall is unconditional, so a user who asks to uninstall always gets a
#   clean removal. Needs root through sudo.
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
    output::run 'Purging the spotify-client package' sudo apt-get purge -y spotify-client
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   spotify::main [<action>]
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
#   spotify::main install
#--------------------------------------------------
spotify::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f spotify::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || spotify::main "$@"
