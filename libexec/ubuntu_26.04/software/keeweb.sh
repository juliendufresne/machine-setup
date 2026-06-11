#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the keeweb unit. The unit::* contract below drives these
# through output::run so each appears as one announced step.

#--------------------------------------------------
# Function:
#   keeweb::_deb_path
#
# Description:
#   Prints the path the KeeWeb .deb is downloaded to and installed from, under the
#   temp directory ($TMPDIR, or /tmp) so it never litters the tree. The download
#   and install steps both call this so they agree on one path without a shared
#   variable. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   keeweb::_deb_path
#--------------------------------------------------
keeweb::_deb_path() {
    printf '%s' "${TMPDIR:-/tmp}/keeweb.deb"
}
[[ -v TEST_FLAG ]] || readonly -f keeweb::_deb_path

#--------------------------------------------------
# Function:
#   keeweb::_latest_deb_url
#
# Description:
#   Resolves the download URL of the amd64 .deb from KeeWeb's most recent stable
#   release. KeeWeb publishes only per-release downloads (no apt repository), and
#   the asset name carries the version, so there is no fixed "latest" URL. This
#   queries the GitHub releases API, whose /releases/latest endpoint returns the
#   newest non-prerelease, non-draft release, and extracts that release's
#   linux.x64.deb asset URL. Writes the URL to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when the API query or extraction fails
#
# Example:
#   keeweb::_latest_deb_url
#--------------------------------------------------
keeweb::_latest_deb_url() {
    curl -fsSL https://api.github.com/repos/keeweb/keeweb/releases/latest \
        | grep -m1 -oE 'https://[^"]+linux\.x64\.deb'
}
[[ -v TEST_FLAG ]] || readonly -f keeweb::_latest_deb_url

#--------------------------------------------------
# Function:
#   keeweb::_download_package
#
# Description:
#   Downloads the latest KeeWeb .deb to the path keeweb::_deb_path reports,
#   resolving the release asset URL through keeweb::_latest_deb_url first so a
#   fresh install always takes the current stable version. Writes the file and
#   discards curl's progress output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   1 when no release URL could be resolved
#   curl's exit status when the download fails
#
# Example:
#   keeweb::_download_package
#--------------------------------------------------
keeweb::_download_package() {
    local deb
    local url

    deb="$(keeweb::_deb_path)"
    url="$(keeweb::_latest_deb_url)" || return $?
    [[ -n "$url" ]] || return 1

    curl -fsSL "$url" -o "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f keeweb::_download_package

#--------------------------------------------------
# Function:
#   keeweb::_install_package
#
# Description:
#   Installs the downloaded KeeWeb .deb with apt-get, which pulls its
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
#   keeweb::_install_package
#--------------------------------------------------
keeweb::_install_package() {
    local deb

    deb="$(keeweb::_deb_path)"

    sudo apt-get install -y "$deb" || return $?
    rm -f "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f keeweb::_install_package

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether KeeWeb can be installed on this host. KeeWeb is a GUI
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
#   Reports whether KeeWeb is present on the host by any means, by resolving the
#   keeweb command. This is the broad "is it usable" check, distinct from
#   unit::is_managed, which asks only whether it came from our package. command
#   -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when keeweb is present
#   1 when keeweb is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v keeweb &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether KeeWeb is installed through the mechanism this unit uses, the
#   keeweb-desktop dpkg package, by querying dpkg. The runner compares this against
#   unit::is_installed to refuse adopting a copy that arrived another way. dpkg's
#   own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the keeweb-desktop package is installed
#   1 when it is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s keeweb-desktop &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   KeeWeb has no inputs to collect. It only warms the sudo session, because the
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
#   Installs KeeWeb by downloading the .deb from its GitHub release and installing
#   it with apt-get (which resolves its dependencies): refreshes the package
#   lists, installs the prerequisites, downloads the .deb, then installs it. Each
#   step is announced through output::run. Needs root through sudo.
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
    output::run 'Downloading KeeWeb' keeweb::_download_package || return $?
    output::run 'Installing the keeweb package' keeweb::_install_package
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Purges the keeweb-desktop package with apt-get, announced through output::run.
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
    output::run 'Purging the keeweb package' sudo apt-get purge -y keeweb-desktop
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   keeweb::main [<action>]
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
#   keeweb::main install
#--------------------------------------------------
keeweb::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f keeweb::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || keeweb::main "$@"
