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
# are the separate libexec/provisioner.sh executable. Sourced by
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
#   runner::_open_session <action>
#
# Description:
#   Opens the execution session for an action that collects or consumes inputs
#   (every action but the read-only status). It begins the session, or
#   joins the one the orchestrator already owns (session::begin), and points this
#   unit's inputs overlay at its working area under the session
#   (execution-in-progress/<unit>/inputs), so state::set/ask write there until the
#   action commits them. A standalone unit run thus owns its own session; an
#   orchestrated step inherits the run's. Exports MACHINE_SETUP_INPUTS_WORKING and
#   creates the working directory.
#
# Arguments:
#   <action>  The action about to run
#
# Returns:
#   0 when the session is open (or the action needs none)
#   the status session::begin returns when the user declined a leftover session
#
# Example:
#   runner::_open_session install
#--------------------------------------------------
runner::_open_session() {
    case "$1" in
        install | uninstall | step-install-inputs | step-install | step-uninstall-inputs | step-uninstall)
            session::begin || return $?

            if session::active
            then
                MACHINE_SETUP_INPUTS_WORKING="$(session::dir)/$(state::_key "$(runner::unit_name)")/inputs"
                export MACHINE_SETUP_INPUTS_WORKING
                mkdir -p "$MACHINE_SETUP_INPUTS_WORKING"
            fi
            ;;
    esac
}
[[ -v TEST_FLAG ]] || readonly -f runner::_open_session

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

#--------------------------------------------------
# Function:
#   runner::run [<action>]
#
# Description:
#   Public entry point a unit's main calls. Routes an action to the unit::*
#   contract. install checks requirements and refuses software already present by
#   other means (present, not ours, not previously owned), then runs
#   request_inputs, install, and configure, and records ownership only once they
#   succeed; uninstall runs request_inputs, unconfigure, uninstall, clears
#   ownership, then warns (without failing) if the software is still present
#   because another install of it exists; status prints the status word. install
#   and uninstall open one stage naming the action (output::stage), then run their
#   hooks; each hook describes its own commands through output::run, so the user
#   sees what is happening, not the commands' chatter. A hook that fails has
#   already shown its command's trace, and the `|| return $?` chain stops the run
#   at that point and propagates the status. The unit's Execute guard already
#   ensures this runs only on direct execution, never when the unit is sourced
#   (for example Included by a spec), so no test guard is needed here. Writes the
#   stage header to stdout and the failing action's status to its caller.
#
# The composite install/uninstall run their steps atomically per unit. So the
# orchestrator can stage them across many units - collecting every unit's inputs up
# front, then doing the real work unattended - each composite is also exposed as a
# pair of staged steps. Install: step-install-inputs applies the same guards as the
# composite install (requirements met, not a foreign install) and collects inputs,
# failing when the unit cannot or must not be installed so the orchestrator drops
# it; step-install then opens the stage and runs unit::install then unit::configure
# as one step, recording ownership once both succeed, exactly as the composite
# install does. step-install assumes step-install-inputs already filtered out
# unavailable or foreign units, so it does not re-check. Uninstall mirrors this:
# step-uninstall-inputs collects inputs (warm sudo, resolve the instance) with no
# guards, since uninstall is unconditional; step-uninstall then opens the stage and
# runs unit::unconfigure then unit::uninstall, clearing ownership, exactly as the
# composite uninstall does.
#
# Ownership, configuration, and manifests are recorded under runner::id, so an
# instanceable unit tracks each instance separately. The id is resolved after
# inputs are collected (install and the staged steps), since an instance key may
# itself come from an input.
#
# Arguments:
#   <action>  install (default), uninstall, status, or one of the
#             staged steps step-install-inputs, step-install, step-uninstall-inputs,
#             step-uninstall
#
# Returns:
#   0 on success
#   1 when requirements are not met, or the software is present by other means
#   2 on an unknown action
#   the exit status a contract step propagates
#
# Example:
#   runner::run install
#--------------------------------------------------
runner::run() {
    local action
    local name

    action="${1:-install}"

    runner::_open_session "$action" || return $?

    case "$action" in
        install)
            if ! unit::is_available
            then
                output::fatal 'requirements not met'

                return 1
            fi

            name="$(runner::unit_name)"

            # Refuse to adopt software that is present but arrived some other way
            # than our mechanism (a source build, a different package). We only
            # manage what we installed; taking it over would let a later uninstall
            # remove something we did not put there. Already ours, or already owned
            # from a prior run, is fine - install is an idempotent update.
            if ! state::owned "$name" && unit::is_installed && ! unit::is_managed
            then
                output::fatal "$name is already installed by other means"

                return 1
            fi

            output::stage "Installing $name"           # stage header for the action
            unit::request_inputs                       # step 1: collect inputs
            unit::install || return $?                 # step 2: install-or-update
            unit::configure || return $?               # step 3: idempotent config
            state::own "$(runner::id)"                 # we manage this instance now
            session::end                               # run finished; drop the lock
            ;;
        uninstall)
            name="$(runner::unit_name)"
            output::stage "Uninstalling $name"         # stage header for the action
            unit::request_inputs                       # step 1: sudo warmup, resolve instance
            unit::unconfigure || return $?             # step 2: restore config
            unit::uninstall || return $?               # step 3: remove
            state::disown "$(runner::id)"

            # Our copy is gone; if git still resolves, another install of it
            # exists that we did not place and must not touch. Flag it, do not fail.
            ! unit::is_installed || output::warn "$name is still present; it may be installed by other means"
            session::end                               # run finished; drop the lock
            ;;
        step-install-inputs)
            # Staged install, step 1: the same guards the composite install applies
            # (requirements met, and not a foreign install we must not adopt), then
            # collect inputs. A non-zero return drops the unit from the install
            # stage, so it runs unattended over the survivors.
            if ! unit::is_available
            then
                output::fatal 'requirements not met'

                return 1
            fi

            name="$(runner::unit_name)"

            if ! state::owned "$name" && unit::is_installed && ! unit::is_managed
            then
                output::fatal "$name is already installed by other means"

                return 1
            fi

            unit::request_inputs                       # collect inputs / warm sudo
            ;;
        step-install)
            # Staged install, step 2: install then configure as one per-unit step,
            # under the action's stage header, recording ownership once both succeed
            # - exactly what the composite install does, minus the guards
            # step-install-inputs already applied. The orchestrator only reaches here
            # for a unit step-install-inputs let through, so the guards are not repeated.
            name="$(runner::unit_name)"
            output::stage "Installing $name"           # stage header for the action
            unit::install || return $?                 # step 1: install-or-update
            unit::configure || return $?               # step 2: idempotent config
            state::own "$(runner::id)"                 # we manage this instance now
            ;;
        step-uninstall-inputs)
            # Staged uninstall, step 1: collect inputs (warm sudo, resolve the
            # instance) up front, so the removal stage that follows runs unattended.
            # Uninstall is unconditional, so unlike step-install-inputs there are no
            # availability or foreign-install guards to apply.
            unit::request_inputs                       # collect inputs / warm sudo
            ;;
        step-uninstall)
            # Staged uninstall, step 2: unconfigure then uninstall as one per-unit
            # step, under the action's stage header, clearing ownership - exactly
            # what the composite uninstall does, minus the inputs
            # step-uninstall-inputs already collected.
            name="$(runner::unit_name)"
            output::stage "Uninstalling $name"         # stage header for the action
            unit::unconfigure || return $?             # step 1: restore config
            unit::uninstall || return $?               # step 2: remove
            state::disown "$(runner::id)"

            # Our copy is gone; if it still resolves, another install of it exists
            # that we did not place and must not touch. Flag it, do not fail.
            ! unit::is_installed || output::warn "$name is still present; it may be installed by other means"
            ;;
        status)
            runner::status                             # the status word
            ;;
        *)
            output::fatal "unknown action: $action"

            return 2
            ;;
    esac
}
[[ -v TEST_FLAG ]] || readonly -f runner::run

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
#   unit::configure
#
# Description:
#   Default no-op for a unit with nothing to configure. A unit that configures
#   something overrides this in its `configure` file. Writes nothing. Defined only
#   when the unit has not already supplied its own.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   unit::configure
#--------------------------------------------------
if ! declare -F unit::configure &>/dev/null
then
    unit::configure() {
        :
    }
    [[ -v TEST_FLAG ]] || readonly -f unit::configure
fi

#--------------------------------------------------
# Function:
#   unit::unconfigure
#
# Description:
#   Default no-op for a unit with no configuration to restore. A unit that
#   configures something overrides this in its `configure` file. Writes nothing.
#   Defined only when the unit has not already supplied its own.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   unit::unconfigure
#--------------------------------------------------
if ! declare -F unit::unconfigure &>/dev/null
then
    unit::unconfigure() {
        :
    }
    [[ -v TEST_FLAG ]] || readonly -f unit::unconfigure
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
