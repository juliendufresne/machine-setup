#!/usr/bin/env bash
set -euo pipefail

# ─── Functions ────────────────────────────────────────────────────────────────
# Local helpers for the claude unit. The unit::* contract below drives these
# through output::run so each appears as one announced step. Claude Code ships as
# a standalone binary installed by Anthropic's native installer (no Node.js, with
# ripgrep bundled), which places it per-user under ~/.local rather than using
# apt/dpkg, so this unit checks for that binary instead of querying a package.

#--------------------------------------------------
# Function:
#   claude::_binary_path
#
# Description:
#   Prints the path of the claude binary the native installer places under the
#   user's home. The is_managed and uninstall steps both call this so they agree
#   on one location without a shared variable. Resolved from HOME at call time, so
#   tests that redirect HOME observe the redirected path. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   claude::_binary_path
#--------------------------------------------------
claude::_binary_path() {
    printf '%s' "$HOME/.local/bin/claude"
}
[[ -v TEST_FLAG ]] || readonly -f claude::_binary_path

#--------------------------------------------------
# Function:
#   claude::_data_dir
#
# Description:
#   Prints the directory the native installer keeps Claude Code's state in under
#   the user's home. The uninstall step calls this to remove it. Resolved from HOME
#   at call time, so tests that redirect HOME observe the redirected path. Writes
#   the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   claude::_data_dir
#--------------------------------------------------
claude::_data_dir() {
    printf '%s' "$HOME/.local/share/claude"
}
[[ -v TEST_FLAG ]] || readonly -f claude::_data_dir

#--------------------------------------------------
# Function:
#   claude::_run_installer
#
# Description:
#   Runs Anthropic's native installer, which downloads the standalone Claude Code
#   binary and installs it per-user under ~/.local (no sudo). This is a helper
#   because the installer is a curl-into-bash pipeline and output::run takes a
#   single command, not a pipeline. Re-running updates the binary in place. Writes
#   the installer's output.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   the failing command's exit status when the install fails
#
# Example:
#   claude::_run_installer
#--------------------------------------------------
claude::_run_installer() {
    curl -fsSL https://claude.ai/install.sh | bash
}
[[ -v TEST_FLAG ]] || readonly -f claude::_run_installer

# ─── Runner contracts ─────────────────────────────────────────────────────────
# The unit::* interface the runner calls. This unit configures nothing, so the
# configuration part of the contract (unit::is_configured, unit::configure,
# unit::unconfigure) is left to the runner's no-op defaults; everything else is here.

#--------------------------------------------------
# Function:
#   unit::is_available
#
# Description:
#   Reports whether Claude Code can be installed on this host. Claude Code is a
#   command-line tool that works headless and on WSL with no graphical desktop, so
#   it is always available where this per-OS file exists. Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always (Claude Code is available)
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
#   Reports whether Claude Code is present on the host by any means, by resolving
#   the claude command. This is the broad "is it usable" check, distinct from
#   unit::is_managed, which asks only whether it came from our mechanism.
#   command -v's own output is discarded.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when claude is present
#   1 when claude is not present
#
# Example:
#   unit::is_installed
#--------------------------------------------------
unit::is_installed() {
    command -v claude &>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_installed

#--------------------------------------------------
# Function:
#   unit::is_managed
#
# Description:
#   Reports whether Claude Code is installed through the mechanism this unit uses,
#   by checking for the binary the native installer places under the user's home.
#   Claude Code is not a dpkg package, so this is a file-presence check rather than
#   a dpkg query. The runner compares this against unit::is_installed to refuse
#   adopting a copy that arrived another way.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when our installed binary is present
#   1 when it is not present
#
# Example:
#   unit::is_managed
#--------------------------------------------------
unit::is_managed() {
    [[ -x "$(claude::_binary_path)" ]]
}
[[ -v TEST_FLAG ]] || readonly -f unit::is_managed

#--------------------------------------------------
# Function:
#   unit::request_inputs
#
# Description:
#   Claude Code has no inputs to collect. It only warms the sudo session, because
#   the prerequisite step installs curl, which needs root. The native installer
#   itself runs unprivileged.
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
#   Installs Claude Code: refreshes the package lists, installs the prerequisites
#   needed to fetch the installer, then runs Anthropic's native installer, which
#   places the standalone binary per-user under ~/.local. Re-running re-runs the
#   installer, which updates the binary in place, so install is idempotent. Each
#   step is announced through output::run. Only the prerequisite step needs root.
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
    output::run 'Installing Claude Code' claude::_run_installer
}
[[ -v TEST_FLAG ]] || readonly -f unit::install

#--------------------------------------------------
# Function:
#   unit::uninstall
#
# Description:
#   Removes Claude Code: deletes the binary the native installer placed, then
#   removes its data directory. Both live under the user's home, so no sudo is
#   needed. Uninstall is unconditional, so a user who asks to uninstall always gets
#   a clean removal. Each step is announced through output::run.
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
    output::run 'Removing the claude binary' rm -f "$(claude::_binary_path)" || return $?
    output::run 'Removing the Claude Code data directory' rm -rf "$(claude::_data_dir)"
}
[[ -v TEST_FLAG ]] || readonly -f unit::uninstall

# ─── Main ─────────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   claude::main [<action>]
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
#   claude::main install
#--------------------------------------------------
claude::main() {
    runner::run "$@"
}
[[ -v TEST_FLAG ]] || readonly -f claude::main

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/runner.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/runner.sh"

# ─── Execute ──────────────────────────────────────────────────────────────────
[[ "${BASH_SOURCE[0]}" != "$0" ]] || claude::main "$@"
