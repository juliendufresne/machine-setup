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
#   Reports whether vim can be installed on this host. vim is a command-line
#   tool with no special requirements, so it is always available where this
#   per-OS file exists. Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always (vim is available)
#
# Example:
#   unit::is_available
#--------------------------------------------------
unit::is_available() {
    true
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_available

#--------------------------------------------------
# Function:
#   unit::is_installed
#
# Description:
#   Reports whether vim is present on the host by any means: a packaged install,
#   a hand-built binary on PATH, anything that resolves the command. This is the
#   broad "is it usable" check, distinct from unit::is_managed, which asks only
#   whether it came from our mechanism. command -v's own output is discarded, so
#   nothing is written to stdout or stderr.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when vim is present on the host
#   1 when vim is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v vim &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether vim is installed through the mechanism this unit uses, the
#   apt/dpkg package, by querying dpkg. The runner compares this against
#   unit::is_installed: present but unmanaged means vim arrived by some other route
#   (a source build, a different package), which the runner refuses to take over.
#   dpkg's own output is discarded, so nothing is written to stdout or stderr.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when the vim package is installed
#   1 when the vim package is not installed
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    dpkg -s vim &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   vim has no inputs to collect. It only warms the sudo session, because the
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
#   Installs vim, or updates it when already present, with apt-get. Each step is
#   announced through output::run, which shows a spinner and the result and
#   reveals apt-get's output only when a step fails. Needs root through sudo.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing step's exit status when apt-get fails
#
# Example:
#   unit::install
#--------------------------------------------------
unit::install() {
    output::run 'Updating the package lists' sudo apt-get update -qq || return $?
    output::run 'Installing the vim package' sudo apt-get install -y vim
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Purges vim with apt-get, announced through output::run so the user sees the
#   step and only sees apt-get's output if it fails. Uninstall is unconditional: it
#   removes vim regardless of whether this tool installed it, so a user who asks
#   to uninstall always gets a clean removal. Needs root through sudo.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing step's exit status when apt-get fails
#
# Example:
#   unit::uninstall
#--------------------------------------------------
unit::uninstall() {
    output::run 'Purging the vim package' sudo apt-get purge -y vim
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   vim::main [<action>]
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
#   vim::main install
#--------------------------------------------------
vim::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f vim::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || vim::main "$@"
