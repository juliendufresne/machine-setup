# shellspec spec helper, loaded via `--require spec_helper` (see .shellspec).
# Provides an isolated environment so specs never touch the real host: a private
# state store and HOME under the shellspec temp base, and the test flag that
# makes a unit script sourceable without executing its runner::run.

# Safety net: unit tests must never run a package manager against the real host.
# Every software unit installs and removes packages with apt-get under sudo, so a
# spec that forgets to stub them would uninstall packages from the developer's
# machine (this has happened). Each software spec stubs these per Describe to
# assert on the arguments; the definitions below are a backstop that any stub
# overrides, so an un-stubbed call lands here, fails loudly, and aborts the
# example instead of mutating the host. Only end-to-end or integration tests may
# touch real packages, and they must run outside this helper. dpkg is left alone
# because units only ever query it (`dpkg -s`), which is read-only.
helper::blocked() {
    printf 'spec_helper: blocked a host-mutating command in a unit test: %s\n' "$*" >&2
    return 99
}

apt-get()  { helper::blocked apt-get "$@"; }
apt()      { helper::blocked apt "$@"; }
aptitude() { helper::blocked aptitude "$@"; }

# Drop privileges in tests: run the wrapped command directly and unprivileged so
# a `sudo apt-get ...` still routes through the apt-get backstop above. A spec may
# override this to assert on how sudo itself is invoked.
sudo() { "$@"; }

# Point the state store and HOME at fresh per-example temp directories. TEST_FLAG
# keeps the unit's functions non-readonly so specs can mock them.
helper::isolate() {
    export TEST_FLAG=true
    export XDG_STATE_HOME="$SHELLSPEC_TMPBASE/state"
    export HOME="$SHELLSPEC_TMPBASE/home"
    rm -rf "$XDG_STATE_HOME" "$HOME"
    mkdir -p "$XDG_STATE_HOME" "$HOME"

    # No session by default, so the inputs overlay is inactive and the store
    # behaves as the plain inputs/ directory unless a spec opts into one.
    unset MACHINE_SETUP_SESSION MACHINE_SETUP_INPUTS_WORKING SESSION_OWNED
}

# Seed a saved input value, as if it had been collected on an earlier run.
helper::seed_input() {
    local name="$1" value="$2" dir="$XDG_STATE_HOME/machine-setup/inputs"
    mkdir -p "$dir"
    printf '%s' "$value" >"$dir/$name"
}

# Point the inputs overlay at a fresh per-unit working area, as the runner does
# inside a session, so a spec can exercise the working-then-committed layering.
helper::overlay() {
    local unit="${1:-workspace}"
    MACHINE_SETUP_INPUTS_WORKING="$XDG_STATE_HOME/machine-setup/execution-in-progress/$unit/inputs"
    mkdir -p "$MACHINE_SETUP_INPUTS_WORKING"
}

# Seed a value into the working overlay, as if it had been entered this run but
# not yet committed.
helper::seed_working() {
    local name="$1" value="$2"
    mkdir -p "$MACHINE_SETUP_INPUTS_WORKING"
    printf '%s' "$value" >"$MACHINE_SETUP_INPUTS_WORKING/$name"
}
