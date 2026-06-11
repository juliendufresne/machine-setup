#!/usr/bin/env bash
set -euo pipefail
# Detect the OS id and version so the orchestrator and the runner can resolve the
# right per-OS files (libexec/<os-id>_<version>/software/<name>.sh and the sibling
# system-upgrade). Reads /etc/os-release, which every supported target ships.
# Tests point OS_RELEASE_FILE at a fixture. Sourced by bin/machine-setup and
# lib/runner.sh.

! declare -F os::_release_file &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   os::_release_file
#
# Description:
#   Resolves the os-release path to read: OS_RELEASE_FILE when set (used by
#   tests to point at a fixture), otherwise /etc/os-release. Writes the path to
#   stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   os::_release_file
#--------------------------------------------------
os::_release_file() {
    printf '%s' "${OS_RELEASE_FILE:-/etc/os-release}"
}
[[ -v TEST_FLAG ]] || readonly -f os::_release_file

#--------------------------------------------------
# Function:
#   os::_field <key>
#
# Description:
#   Reads a single field (for example ID or VERSION_ID) from os-release,
#   stripping the surrounding quotes that os-release uses for values with
#   spaces. Sources the os-release file in a subshell to evaluate the field.
#   Writes the value to stdout.
#
# Arguments:
#   <key>  The os-release variable to read (for example ID)
#
# Returns:
#   0 on success
#   1 when the os-release file is not readable
#
# Example:
#   os::_field ID
#--------------------------------------------------
os::_field() {
    local file
    local key
    local value

    key="$1"
    file="$(os::_release_file)"
    [[ -r "$file" ]] || return 1

    value="$(
        # shellcheck source=/dev/null
        source "$file" >/dev/null 2>&1 || true
        printf '%s' "${!key:-}"
    )"

    printf '%s' "$value"
}
[[ -v TEST_FLAG ]] || readonly -f os::_field

#--------------------------------------------------
# Function:
#   os::id
#
# Description:
#   Reports the OS id (the ID field of os-release, for example "ubuntu"). Writes
#   the id to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   1 when the os-release file is not readable
#
# Example:
#   os::id
#--------------------------------------------------
os::id() {
    os::_field ID
}
[[ -v TEST_FLAG ]] || readonly -f os::id

#--------------------------------------------------
# Function:
#   os::version
#
# Description:
#   Reports the OS version (the VERSION_ID field of os-release, for example
#   "26.04"). Writes the version to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   1 when the os-release file is not readable
#
# Example:
#   os::version
#--------------------------------------------------
os::version() {
    os::_field VERSION_ID
}
[[ -v TEST_FLAG ]] || readonly -f os::version

#--------------------------------------------------
# Function:
#   os::file_token
#
# Description:
#   Reports the filename token a software unit uses, joining the OS id and
#   version as "<id>_<version>" (for example "ubuntu_26.04"). Writes the token
#   to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#   1 when the os-release file is not readable
#
# Example:
#   os::file_token
#--------------------------------------------------
os::file_token() {
    printf '%s_%s' "$(os::id)" "$(os::version)"
}
[[ -v TEST_FLAG ]] || readonly -f os::file_token
