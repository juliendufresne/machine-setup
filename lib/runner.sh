#!/usr/bin/env bash
set -euo pipefail
# The step runner: every unit script sources this, implements the unit::*
# contract, then calls `runner::run "$@"`. The runner drives the same step
# sequence for every unit and computes its status. It sequences and calls the
# unit::* functions (unit::is_available, unit::is_installed, unit::is_managed,
# unit::is_configured, unit::request_inputs, unit::install, unit::configure,
# unit::unconfigure, unit::uninstall, unit::instance).
# The hooks it defines itself are no-op defaults for the three
# configuration functions (unit::is_configured, unit::configure, unit::unconfigure)
# and an empty unit::instance (so a unit is non-instanceable unless it says
# otherwise); so a unit that configures nothing and is not instanceable can omit all
# of them. A unit that does configure
# something defines its own config hooks in a sibling `configure` file sourced
# before this library, which wins; an instanceable unit defines unit::instance in
# its own script before sourcing this library. The post-install provisioners (the
# workspace, the dotfiles) are not software units and do not use this runner; they
# run on lib/provisioner.sh. Sourced by
# unit scripts; re-sources the sibling libraries it depends on.

! declare -F runner::run &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   runner::unit_name
#
# Description:
#   Prints the unit's name. A per-OS software file is named by its filename
#   without the .sh extension (libexec/<os>_<version>/software/<name>.sh ->
#   <name>); a flat helper that is its own executable directly in libexec/ (a
#   workspace at libexec/<name>) is named by the script's own basename. The two are
#   told apart by whether the script's parent directory is named "software".
#   Honours MACHINE_SETUP_UNIT_NAME when set (used by tests to avoid depending on
#   $0), otherwise derives it from the script path. Writes the name to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   runner::unit_name
#--------------------------------------------------
runner::unit_name() {
    local dir
    local file
    local path

    if [[ -n "${MACHINE_SETUP_UNIT_NAME:-}" ]]
    then
        printf '%s' "$MACHINE_SETUP_UNIT_NAME"

        return
    fi

    path="$(realpath -- "$0")"
    dir="$(dirname "$path")"

    # A per-OS software file lives under a software/ directory and is named by its
    # filename without .sh; a flat helper sits directly in libexec/ and is named by
    # its own basename.
    if [[ "$(basename "$dir")" == software ]]
    then
        file="$(basename "$path")"
        printf '%s' "${file%.sh}"
    else
        basename "$path"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f runner::unit_name

#--------------------------------------------------
# Function:
#   runner::id
#
# Description:
#   Prints the unit's state id - the key under which ownership, configuration, and
#   manifests are recorded. For a plain unit that is just its name; for an
#   instanceable unit (one whose unit::instance prints a non-empty value) it is
#   name@instance, so each instance is tracked separately (workspace@personal,
#   workspace@acme). Writes the id to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   runner::id
#--------------------------------------------------
runner::id() {
    local instance
    local name

    name="$(runner::unit_name)"
    instance="$(unit::instance)"

    if [[ -n "$instance" ]]
    then
        printf '%s@%s' "$name" "$instance"
    else
        printf '%s' "$name"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f runner::id

#--------------------------------------------------
# Function:
#   runner::status
#
# Description:
#   Prints the unit's status word - one of unavailable, available, unmanaged,
#   installed, or configured - by consulting the unit::is_* contract in order.
#   unmanaged means present on the host but not via our mechanism, so installed
#   and configured both describe software we manage. Writes the word to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   runner::status
#--------------------------------------------------
runner::status() {
    if ! unit::is_available
    then
        printf 'unavailable\n'

        return
    fi

    if ! unit::is_installed
    then
        printf 'available\n'

        return
    fi

    if ! unit::is_managed
    then
        printf 'unmanaged\n'                            # present, but by other means

        return
    fi

    if ! unit::is_configured
    then
        printf 'installed\n'                            # ours, not yet configured

        return
    fi

    printf 'configured\n'
}
[[ -v TEST_FLAG ]] || readonly -f runner::status

# ─── Default contract ─────────────────────────────────────────────────────────
# The configuration part of the unit::* contract, defaulted to no-ops. Most units
# install software that needs no configuration of ours, so they ship no config
# code at all and inherit these. A unit that does configure something defines
# unit::is_configured, unit::configure, and unit::unconfigure in a sibling
# `configure` file next to its per-OS script, sourced by that script before this
# library; each default below is defined only when the unit has not already
# provided its own, so the unit's version wins and is never overwritten here.

#--------------------------------------------------
# Function:
#   unit::is_configured
#
# Description:
#   Default predicate for a unit with nothing to configure: it is configured as
#   soon as it is installed. A unit that configures something overrides this in
#   its `configure` file. Writes nothing. Defined only when the unit has not
#   already supplied its own.
#
# Arguments:
#   N/A
#
# Returns:
#   0 always (nothing to configure)
#
# Example:
#   unit::is_configured
#--------------------------------------------------
if ! declare -F unit::is_configured &>/dev/null
then
    unit::is_configured() {
        true
    }
    [[ -v TEST_FLAG ]] || readonly -f unit::is_configured
fi

#--------------------------------------------------
# Function:
#   unit::instance
#
# Description:
#   Default for a non-instanceable unit: it has no instance key, so runner::id is
#   just the unit name. An instanceable unit (a workspace) overrides this in its
#   own script, printing the value that scopes the instance (its name), so the
#   state id becomes name@instance. Writes nothing. Defined only when the unit has
#   not already supplied its own.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   unit::instance
#--------------------------------------------------
if ! declare -F unit::instance &>/dev/null
then
    unit::instance() {
        :
    }
    [[ -v TEST_FLAG ]] || readonly -f unit::instance
fi

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling libraries are sourced regardless
# of the unit's location or the caller's working directory. Defined only when not
# already set (a unit or another library may have resolved it first), and made
# readonly outside tests so specs can still reassign it.
if [[ -z "${LIB_DIR:-}" ]]
then
    LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    [[ -v TEST_FLAG ]] || readonly LIB_DIR
fi

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=lib/os.sh
source "$LIB_DIR/os.sh"
# shellcheck source=lib/host.sh
source "$LIB_DIR/host.sh"
# shellcheck source=lib/sudo.sh
source "$LIB_DIR/sudo.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/session.sh
source "$LIB_DIR/session.sh"
