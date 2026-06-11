#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the discord unit. The unit::* contract below drives these
# through output::run so each appears as one announced step.

#--------------------------------------------------
# Function:
#   discord::_deb_path
#
# Description:
#   Prints the path the Discord .deb is downloaded to and installed from, under
#   the temp directory ($TMPDIR, or /tmp) so it never litters the tree. The
#   download and install steps both call this so they agree on one path without a
#   shared variable. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   discord::_deb_path
#--------------------------------------------------
discord::_deb_path() {
    printf '%s' "${TMPDIR:-/tmp}/discord.deb"
}
[[ -v TEST_FLAG ]] || readonly -f discord::_deb_path

#--------------------------------------------------
# Function:
#   discord::_download_package
#
# Description:
#   Downloads the latest Discord .deb from discord.com to the path
#   discord::_deb_path reports. Discord publishes only a direct download (no apt
#   repository), so the URL is the platform/format download endpoint, which
#   redirects to the current build; curl follows the redirect. Writes the file
#   and discards curl's progress output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   curl's exit status when the download fails
#
# Example:
#   discord::_download_package
#--------------------------------------------------
discord::_download_package() {
    local deb

    deb="$(discord::_deb_path)"

    curl -fsSL 'https://discord.com/api/download?platform=linux&format=deb' -o "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f discord::_download_package

#--------------------------------------------------
# Function:
#   discord::_install_package
#
# Description:
#   Installs the downloaded Discord .deb with apt-get, which pulls its
#   dependencies, then removes the .deb. Needs root through sudo. Discards
#   apt-get's output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   apt-get's exit status when the install fails
#
# Example:
#   discord::_install_package
#--------------------------------------------------
discord::_install_package() {
    local deb

    deb="$(discord::_deb_path)"

    sudo apt-get install -y "$deb" || return $?
    rm -f "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f discord::_install_package

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether Discord can be installed on this host. Discord is a GUI
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
#   Reports whether Discord is present on the host by any means, by resolving the
#   discord command. This is the broad "is it usable" check, distinct from
#   unit::is_managed, which asks only whether it came from our package. command
#   -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when discord is present
#   1 when discord is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v discord &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether Discord is installed through the mechanism this unit uses, the
#   discord dpkg package, by querying dpkg. The runner compares this against
#   unit::is_installed to refuse adopting a copy that arrived another way. dpkg's
#   own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the discord package is installed
#   1 when it is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s discord &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   Discord has no inputs to collect. It only warms the sudo session, because the
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
#   Installs Discord by downloading the .deb from discord.com and installing it
#   with apt-get (which resolves its dependencies): refreshes the package lists,
#   installs the prerequisites, downloads the .deb, then installs it. Each step is
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
    output::run 'Installing prerequisite packages' sudo apt-get install -y ca-certificates curl || return $?
    output::run 'Downloading Discord' discord::_download_package || return $?
    output::run 'Installing the discord package' discord::_install_package
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Purges the discord package with apt-get, announced through output::run.
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
    output::run 'Purging the discord package' sudo apt-get purge -y discord
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   discord::main [<action>]
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
#   discord::main install
#--------------------------------------------------
discord::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f discord::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || discord::main "$@"
