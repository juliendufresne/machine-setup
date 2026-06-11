#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the docker-desktop unit. The unit::* contract below drives
# these through output::run so each appears as one announced step.

#--------------------------------------------------
# Function:
#   docker::desktop::_deb_path
#
# Description:
#   Prints the path the Docker Desktop .deb is downloaded to and installed from,
#   under the temp directory ($TMPDIR, or /tmp) so it never litters the tree. The
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
#   docker::desktop::_deb_path
#--------------------------------------------------
docker::desktop::_deb_path() {
    printf '%s' "${TMPDIR:-/tmp}/docker-desktop-amd64.deb"
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_deb_path

#--------------------------------------------------
# Function:
#   docker::desktop::_codename
#
# Description:
#   Prints the Ubuntu release codename (the VERSION_CODENAME field of
#   /etc/os-release, for example "plucky"), which the Docker apt repository line
#   needs. Sourced in a subshell so it cannot leak os-release variables into the
#   caller. Writes the codename to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   docker::desktop::_codename
#--------------------------------------------------
docker::desktop::_codename() {
    (
        # shellcheck source=/dev/null
        source /etc/os-release
        printf '%s' "${VERSION_CODENAME:-}"
    )
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_codename

#--------------------------------------------------
# Function:
#   docker::desktop::_add_apt_repository
#
# Description:
#   Sets up Docker's apt repository the way the official Ubuntu instructions do,
#   so apt can resolve Docker Desktop's dependencies: creates the keyring
#   directory, downloads Docker's GPG key into it, makes the key world-readable,
#   then writes the repository definition to /etc/apt/sources.list.d/docker.list,
#   pinned to this host's architecture and release codename. Needs root through
#   sudo. Writes the key and the sources list, and discards the curl/tee output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when a step fails
#
# Example:
#   docker::desktop::_add_apt_repository
#--------------------------------------------------
docker::desktop::_add_apt_repository() {
    local arch
    local codename

    sudo install -m 0755 -d /etc/apt/keyrings || return $?
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || return $?
    sudo chmod a+r /etc/apt/keyrings/docker.asc || return $?

    arch="$(dpkg --print-architecture)"
    codename="$(docker::desktop::_codename)"

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' "$arch" "$codename" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_add_apt_repository

#--------------------------------------------------
# Function:
#   docker::desktop::_download_package
#
# Description:
#   Downloads the latest Docker Desktop .deb for amd64 from desktop.docker.com to
#   the path docker::desktop::_deb_path reports, as the official instructions
#   direct (the package is not in the apt repository). Writes the file and
#   discards curl's progress output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   curl's exit status when the download fails
#
# Example:
#   docker::desktop::_download_package
#--------------------------------------------------
docker::desktop::_download_package() {
    local deb

    deb="$(docker::desktop::_deb_path)"

    curl -fsSL https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb -o "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_download_package

#--------------------------------------------------
# Function:
#   docker::desktop::_install_package
#
# Description:
#   Installs the downloaded Docker Desktop .deb with apt-get, which pulls its
#   dependencies from the repository added earlier, then removes the .deb. Needs
#   root through sudo. Discards apt-get's output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   apt-get's exit status when the install fails
#
# Example:
#   docker::desktop::_install_package
#--------------------------------------------------
docker::desktop::_install_package() {
    local deb

    deb="$(docker::desktop::_deb_path)"

    sudo apt-get install -y "$deb" || return $?
    rm -f "$deb"
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_install_package

#--------------------------------------------------
# Function:
#   docker::desktop::_remove_residual
#
# Description:
#   Removes the configuration and data files the official uninstall instructions
#   say to delete after the package is purged: the per-user ~/.docker/desktop
#   directory and the /usr/local/bin/com.docker.cli symlink. The CLI symlink
#   removal needs root through sudo. Removes files.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when a step fails
#
# Example:
#   docker::desktop::_remove_residual
#--------------------------------------------------
docker::desktop::_remove_residual() {
    rm -rf "$HOME/.docker/desktop" || return $?
    sudo rm -f /usr/local/bin/com.docker.cli
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_remove_residual

#--------------------------------------------------
# Function:
#   docker::desktop::_install_gnome_terminal
#
# Description:
#   Installs gnome-terminal, which Docker Desktop relies on for its integrated
#   terminal, and records that we installed it (keyed under the docker-desktop
#   unit) so the uninstall can warn that it was left behind. The caller runs this
#   only when gnome-terminal is not already present, so a copy the user already
#   had is never claimed as ours. Needs root through sudo. Discards apt-get's
#   output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   apt-get's exit status when the install fails
#
# Example:
#   docker::desktop::_install_gnome_terminal
#--------------------------------------------------
docker::desktop::_install_gnome_terminal() {
    sudo apt-get install -y gnome-terminal || return $?
    state::own docker-desktop/gnome-terminal
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_install_gnome_terminal

#--------------------------------------------------
# Function:
#   docker::desktop::_warn_orphaned_gnome_terminal
#
# Description:
#   When this unit installed gnome-terminal for Docker Desktop (recorded at
#   install time), warns that it has been left in place, because we cannot tell
#   whether the user now relies on it elsewhere, then clears the record so the
#   warning shows once. Does nothing when we did not install it. Writes a warning
#   to stderr.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always
#
# Example:
#   docker::desktop::_warn_orphaned_gnome_terminal
#--------------------------------------------------
docker::desktop::_warn_orphaned_gnome_terminal() {
    state::owned docker-desktop/gnome-terminal || return 0

    output::warn 'gnome-terminal was installed for Docker Desktop and has been left in place; remove it with "sudo apt-get purge gnome-terminal" if you do not use it elsewhere.'
    state::disown docker-desktop/gnome-terminal
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::_warn_orphaned_gnome_terminal

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether Docker Desktop can be installed on this host. Docker Desktop
#   is a GUI application, so it requires a graphical desktop and is unavailable on
#   a headless server. Writes nothing.
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
#   Reports whether Docker Desktop is present on the host by any means, by
#   resolving the docker-desktop command. This is the broad "is it usable" check,
#   distinct from unit::is_managed, which asks only whether it came from our
#   package. command -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when docker-desktop is present
#   1 when docker-desktop is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v docker-desktop &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether Docker Desktop is installed through the mechanism this unit
#   uses, the docker-desktop apt/dpkg package, by querying dpkg. The runner
#   compares this against unit::is_installed to refuse adopting a copy that
#   arrived another way. dpkg's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the docker-desktop package is installed
#   1 when it is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s docker-desktop &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   Docker Desktop has no inputs to collect. It only warms the sudo session,
#   because the repository, install, and uninstall steps need root.
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
#   Installs Docker Desktop the way the official Ubuntu instructions direct:
#   refreshes the package lists, installs the prerequisites (and gnome-terminal,
#   which Docker Desktop needs for its integrated terminal, when it is not already
#   present), adds Docker's apt repository, refreshes the lists again, then
#   downloads and installs the .deb. Each step is announced through output::run.
#   Needs root through sudo.
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

    if ! command -v gnome-terminal &>/dev/null
    then
        output::run 'Installing gnome-terminal' docker::desktop::_install_gnome_terminal || return $?
    fi

    output::run 'Adding the Docker apt repository' docker::desktop::_add_apt_repository || return $?
    output::run 'Updating the package lists' sudo apt-get update -qq || return $?
    output::run 'Downloading Docker Desktop' docker::desktop::_download_package || return $?
    output::run 'Installing the docker-desktop package' docker::desktop::_install_package
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Removes Docker Desktop the way the official uninstall instructions direct:
#   purges the docker-desktop package, then removes the residual configuration and
#   data files (~/.docker/desktop and the com.docker.cli symlink). Uninstall is
#   unconditional, so a user who asks to uninstall always gets a clean removal.
#   Each step is announced through output::run. Finally, if we installed
#   gnome-terminal for Docker Desktop, warns that it was left in place, since we
#   cannot tell whether the user now relies on it. Needs root through sudo.
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
    output::run 'Purging the docker-desktop package' sudo apt-get purge -y docker-desktop || return $?
    output::run 'Removing residual Docker Desktop files' docker::desktop::_remove_residual || return $?

    docker::desktop::_warn_orphaned_gnome_terminal
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   docker::desktop::main [<action>]
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
#   docker::desktop::main install
#--------------------------------------------------
docker::desktop::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f docker::desktop::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || docker::desktop::main "$@"
