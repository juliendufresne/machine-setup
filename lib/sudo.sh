#!/usr/bin/env bash
set -euo pipefail
# Sudo session handling. A unit that needs root calls sudo::warmup during input
# collection (step 1), so the rest of the run is unattended. Sourced by runner.

! declare -F sudo::is_needed &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   sudo::is_needed
#
# Description:
#   Reports whether a sudo password prompt would be needed, that is when a
#   non-interactive sudo does not already succeed from a cached credential.
#   sudo's own output is discarded, so nothing is written.
#
# Arguments:
#   N/A
#
# Returns:
#   0 when a password prompt would be needed
#   1 when sudo already succeeds non-interactively
#
# Example:
#   sudo::is_needed
#--------------------------------------------------
sudo::is_needed() {
    ! sudo -n true 2>/dev/null
}
[[ -v TEST_FLAG ]] || readonly -f sudo::is_needed

#--------------------------------------------------
# Function:
#   sudo::warmup
#
# Description:
#   Primes the sudo session, but only when a prompt is actually needed, so a
#   host that already has a valid sudo timestamp is never prompted. May prompt
#   the user for a password on the controlling terminal.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   non-zero when the sudo authentication fails
#
# Example:
#   sudo::warmup
#--------------------------------------------------
sudo::warmup() {
    if sudo::is_needed
    then
        sudo -v
    fi
}
[[ -v TEST_FLAG ]] || readonly -f sudo::warmup
