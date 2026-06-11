#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the jetbrains-toolbox unit. The unit::* contract below drives
# these through output::run so each appears as one announced step. JetBrains
# Toolbox ships only as a tarball (no apt repository or .deb), so this unit
# extracts it into /opt and links its launcher onto PATH rather than using dpkg.

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::_install_dir
#
# Description:
#   Prints the directory the JetBrains Toolbox tarball is extracted into. The
#   install, uninstall, and is_managed steps all call this so they agree on one
#   location without a shared variable. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   jetbrains::toolbox::_install_dir
#--------------------------------------------------
jetbrains::toolbox::_install_dir() {
    printf '%s' /opt/jetbrains-toolbox
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::_install_dir

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::_symlink_path
#
# Description:
#   Prints the path of the launcher symlink placed on PATH so the jetbrains-toolbox
#   command resolves. The install and uninstall steps both call this so they agree
#   on one location. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   jetbrains::toolbox::_symlink_path
#--------------------------------------------------
jetbrains::toolbox::_symlink_path() {
    printf '%s' /usr/local/bin/jetbrains-toolbox
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::_symlink_path

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::_tarball_path
#
# Description:
#   Prints the path the JetBrains Toolbox tarball is downloaded to and extracted
#   from, under the temp directory ($TMPDIR, or /tmp) so it never litters the tree.
#   The download and install steps both call this so they agree on one path
#   without a shared variable. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   jetbrains::toolbox::_tarball_path
#--------------------------------------------------
jetbrains::toolbox::_tarball_path() {
    printf '%s' "${TMPDIR:-/tmp}/jetbrains-toolbox.tar.gz"
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::_tarball_path

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::_download_archive
#
# Description:
#   Downloads the latest JetBrains Toolbox tarball to the path
#   jetbrains::toolbox::_tarball_path reports. JetBrains publishes a download
#   redirect that always points at the current Linux build, so the URL is that
#   endpoint and curl follows the redirect. Writes the file and discards curl's
#   progress output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   curl's exit status when the download fails
#
# Example:
#   jetbrains::toolbox::_download_archive
#--------------------------------------------------
jetbrains::toolbox::_download_archive() {
    local tarball

    tarball="$(jetbrains::toolbox::_tarball_path)"

    curl -fsSL 'https://data.services.jetbrains.com/products/download?platform=linux&code=TBA' -o "$tarball"
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::_download_archive

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::_install_archive
#
# Description:
#   Installs the downloaded JetBrains Toolbox tarball: creates the install
#   directory, extracts the archive into it (stripping the versioned top-level
#   directory so the layout is stable across releases), links the launcher onto
#   PATH, then removes the tarball. The extracted launcher lives at
#   bin/jetbrains-toolbox under the install directory. Needs root through sudo for
#   the writes under /opt and /usr/local/bin. Discards tar's output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when a step fails
#
# Example:
#   jetbrains::toolbox::_install_archive
#--------------------------------------------------
jetbrains::toolbox::_install_archive() {
    local dir
    local link
    local tarball

    dir="$(jetbrains::toolbox::_install_dir)"
    link="$(jetbrains::toolbox::_symlink_path)"
    tarball="$(jetbrains::toolbox::_tarball_path)"

    sudo mkdir -p "$dir" || return $?
    sudo tar -xzf "$tarball" -C "$dir" --strip-components=1 || return $?
    sudo ln -sf "$dir/bin/jetbrains-toolbox" "$link" || return $?
    rm -f "$tarball"
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::_install_archive

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether JetBrains Toolbox can be installed on this host. JetBrains
#   Toolbox is a GUI application, so it requires a graphical desktop and is
#   unavailable on a headless server. Writes nothing.
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
#   Reports whether JetBrains Toolbox is present on the host by any means, by
#   resolving the jetbrains-toolbox command. This is the broad "is it usable"
#   check, distinct from unit::is_managed, which asks only whether it came from our
#   mechanism. command -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when jetbrains-toolbox is present
#   1 when jetbrains-toolbox is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v jetbrains-toolbox &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether JetBrains Toolbox is installed through the mechanism this unit
#   uses, by checking for the launcher this unit extracts into its install
#   directory. JetBrains Toolbox is not a dpkg package, so this is a file-presence
#   check rather than a dpkg query. The runner compares this against
#   unit::is_installed to refuse adopting a copy that arrived another way.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when our extracted launcher is present
#   1 when it is not present
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    [[ -e "$(jetbrains::toolbox::_install_dir)/bin/jetbrains-toolbox" ]]
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   JetBrains Toolbox has no inputs to collect. It only warms the sudo session,
#   because the install and uninstall steps write under /opt and /usr/local/bin.
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
#   Installs JetBrains Toolbox from its tarball: refreshes the package lists,
#   installs the prerequisites needed to fetch and unpack it, downloads the
#   tarball, then extracts it and links its launcher onto PATH. Re-running
#   re-extracts over the same directory, so install is idempotent. Each step is
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
    output::run 'Installing prerequisite packages' sudo apt-get install -y ca-certificates curl tar || return $?
    output::run 'Downloading JetBrains Toolbox' jetbrains::toolbox::_download_archive || return $?
    output::run 'Installing the JetBrains Toolbox archive' jetbrains::toolbox::_install_archive
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Removes JetBrains Toolbox: deletes the launcher symlink, then removes the
#   install directory it was extracted into. Uninstall is unconditional, so a user
#   who asks to uninstall always gets a clean removal. Each step is announced
#   through output::run. Needs root through sudo.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing step's exit status when a step fails
#
# Example:
#   unit::uninstall
#--------------------------------------------------
unit::uninstall() {
    output::run 'Removing the jetbrains-toolbox launcher' sudo rm -f "$(jetbrains::toolbox::_symlink_path)" || return $?
    output::run 'Removing the JetBrains Toolbox install directory' sudo rm -rf "$(jetbrains::toolbox::_install_dir)"
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   jetbrains::toolbox::main [<action>]
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
#   jetbrains::toolbox::main install
#--------------------------------------------------
jetbrains::toolbox::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f jetbrains::toolbox::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || jetbrains::toolbox::main "$@"
