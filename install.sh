#!/bin/sh
#
# install.sh - POSIX sh bootstrap for machine-setup.
#
# Fetched on a bare host and run by sh. Pass the script as an argument rather
# than piping it in (`... | sh`): the orchestrator asks questions with `read`,
# and a pipe ties up stdin so those prompts can never reach the terminal.
#
#   sh -c "$(curl -fsSL https://github.com/juliendufresne/machine-setup/install.sh)"
#   sh -c "$(wget -qO-  https://github.com/juliendufresne/machine-setup/install.sh)"
#
# To pass options through to the orchestrator, append them after the command
# string (sh assigns them to the script's positional parameters):
#
#   sh -c "$(wget -qO- .../install.sh)" -- --some-machine-setup-option
#
# It must run before bash is guaranteed, so it stays POSIX sh (no bashisms) and
# targets whatever /bin/sh the pipe provides (dash on Ubuntu). It:
#
#   1. selects a package manager for the host (apt on Ubuntu) and refuses
#      unsupported ones,
#   2. ensures git is installed,
#   3. ensures bash is recent enough for the runner,
#   4. clones (or updates) the repository under an XDG data directory,
#   5. hands over to bin/machine-setup, forwarding any option it did not use.
#
# Every step is idempotent: re-running updates the checkout and dispatches again.

set -eu

# ─── Constants / globals ─────────────────────────────────────────────────────

# Repository to clone when --repository / $MACHINE_SETUP_REPOSITORY is not given.
DEFAULT_REPOSITORY='https://github.com/juliendufresne/machine-setup.git'

# Path of the orchestrator inside the checkout, run once the repo is in place.
# Change this one line if the orchestrator is renamed.
ENTRYPOINT='bin/machine-setup'

# Minimum bash the runner needs. Compared as MAJOR*100 + MINOR in one shot, so
# 4.2 is 402. Bump these if a newer feature raises the floor.
REQUIRED_BASH_MAJOR=4
REQUIRED_BASH_MINOR=2

# Set once `apt-get update` has run, so package lists refresh at most once and
# only when something actually needs installing.
APT_UPDATED=0

# The package manager selected by detect_package_manager(); the pkg_* wrappers
# dispatch on it.
PACKAGE_MANAGER=''

# The os-release file that identifies the distribution. Overridable so the test
# suite can point it at a fixture instead of the real one.
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

# ─── Output ──────────────────────────────────────────────────────────────────

# Reports a progress step on stderr (stdout is left clean for the orchestrator).
info() {
    printf '%s\n' "$*" >&2
}

# Prints an error on stderr with the program prefix. Control flow is the caller's
# job: follow every call with `return 1` (or let it propagate via set -e).
error() {
    printf 'install.sh: error: %s\n' "$*" >&2
}

# Prints bootstrap usage on stderr.
usage() {
    cat >&2 <<EOF
machine-setup bootstrap (install.sh)

Usage:
  curl -fsSL <url>/install.sh | sh
  wget -qO-  <url>/install.sh | sh -s -- [bootstrap options] [machine-setup options]

Bootstrap options (everything else is forwarded to ${ENTRYPOINT}):
  -r, --repository <url>   Git repository to clone
                           (default: ${DEFAULT_REPOSITORY})
  -d, --directory <path>   Where to clone it
                           (default: \$XDG_DATA_HOME/machine-setup)
  -h, --help               Show this help and exit

Environment overrides:
  MACHINE_SETUP_REPOSITORY   same as --repository
  MACHINE_SETUP_DIR          same as --directory
EOF
}

# ─── Privilege / packages ────────────────────────────────────────────────────

# Runs its arguments as root: directly when already root, through sudo when not.
as_root() {
    if [ "$(id -u)" -eq 0 ]
    then
        "$@"
    elif command -v sudo >/dev/null 2>&1
    then
        sudo "$@"
    else
        error "root privileges required to run: $*"

        return 1
    fi
}

# Refreshes the apt package lists, at most once per invocation.
apt_update_once() {
    [ "$APT_UPDATED" -eq 0 ] || return 0
    info 'Updating package lists'
    as_root apt-get update -qq
    APT_UPDATED=1
}

# Installs the named apt packages non-interactively.
apt_install() {
    apt_update_once
    info "Installing: $*"
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Installs the named packages with the detected manager's backend. Add a branch
# here when wiring in a new package manager.
pkg_install() {
    case "$PACKAGE_MANAGER" in
        apt) apt_install "$@" ;;
        *) error "no installer wired for package manager '${PACKAGE_MANAGER}'"; return 1 ;;
    esac
}

# ─── Steps ───────────────────────────────────────────────────────────────────

# Aborts because no package manager could be selected, printing the steps a
# contributor takes in install.sh to add support. Pass the detected distribution
# id when known; omit it (or pass an empty string) when none could be read, so
# step 1 points at extending detection rather than the case/backend wiring.
unsupported_distribution() {
    unsupported_id="${1:-}"
    if [ -n "$unsupported_id" ]
    then
        subject="unsupported distribution '${unsupported_id}'"
        retrieve_step="detect_package_manager() already read this id from the ID field of ${OS_RELEASE_FILE}, so detection needs no change"
    else
        subject='could not determine the distribution'
        retrieve_step="teach detect_package_manager() to read the os id from this host: ${OS_RELEASE_FILE} was unreadable or carried no ID, so add a fallback source (e.g. /etc/lsb-release, the lsb_release command, or uname)"
    fi

    error "${subject}; to add support, edit install.sh:"
    cat >&2 <<EOF
  1. ${retrieve_step};
  2. add a case branch in detect_package_manager() mapping the id to a
     PACKAGE_MANAGER tag (e.g. dnf);
  3. if that tag is new, add a backend pair beside apt_update_once/apt_install
     (e.g. dnf_install) and wire it into pkg_install();
  4. confirm the package names in ensure_git/ensure_bash (git, bash) match the
     new manager.
EOF

    return 1
}

# Selects the host's package manager from /etc/os-release into PACKAGE_MANAGER.
# Maps ID=ubuntu to apt; anything else (including a host with no readable
# os-release) defers to unsupported_distribution. Add new detection sources to
# the os_id lookup below, and new mappings to the case.
detect_package_manager() {
    os_id=''
    if [ -r "$OS_RELEASE_FILE" ]
    then
        # shellcheck source=/dev/null
        os_id="$(. "$OS_RELEASE_FILE" && printf '%s' "${ID:-}")"
    fi
    case "$os_id" in
        ubuntu) PACKAGE_MANAGER='apt' ;;
        *) unsupported_distribution "$os_id" ;;
    esac
}

# Installs git when it is not already on PATH.
ensure_git() {
    command -v git >/dev/null 2>&1 && return 0
    pkg_install git
}

# True when a bash recent enough for the runner is available. BASH_VERSINFO is a
# bash array, so the test runs inside bash itself; the required floor is spliced
# in as a literal integer.
bash_recent() {
    command -v bash >/dev/null 2>&1 || return 1
    bash -c 'exit $(( (BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1]) < ('"$REQUIRED_BASH_MAJOR"' * 100 + '"$REQUIRED_BASH_MINOR"') ))'
}

# Installs or upgrades bash when the present one is older than the floor.
ensure_bash() {
    bash_recent && return 0
    info "bash older than ${REQUIRED_BASH_MAJOR}.${REQUIRED_BASH_MINOR}; installing a newer one"
    pkg_install bash
    bash_recent || { error "bash is still older than ${REQUIRED_BASH_MAJOR}.${REQUIRED_BASH_MINOR} after install"; return 1; }
}

# Clones the repository, or fast-forwards it when the checkout already exists.
sync_repository() {
    if [ -d "$install_dir/.git" ]
    then
        info "Updating checkout in $install_dir"
        git -C "$install_dir" pull --ff-only
        return 0
    fi

    if [ -e "$install_dir" ]
    then
        error "$install_dir exists but is not a machine-setup checkout; move it aside and retry"; return 1
    fi

    info "Cloning $repository into $install_dir"
    mkdir -p "$(dirname "$install_dir")"
    git clone "$repository" "$install_dir"
}

# Hands over to the orchestrator, forwarding the options this script did not use.
run_machine_setup() {
    [ -x "$install_dir/$ENTRYPOINT" ] || { error "$install_dir/$ENTRYPOINT is missing or not executable"; return 1; }
    info "Running $ENTRYPOINT"
    exec "$install_dir/$ENTRYPOINT" "$@"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    repository="${MACHINE_SETUP_REPOSITORY:-$DEFAULT_REPOSITORY}"
    install_dir="${MACHINE_SETUP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/machine-setup}"

    # Consume the options this bootstrap understands and rotate every other
    # argument to the back, so what remains (in original order) is exactly what
    # gets forwarded to the orchestrator. `argc` counts the original arguments
    # still to inspect; kept ones are pushed past that window.
    argc=$#
    while [ "$argc" -gt 0 ]
    do
        argc=$(( argc - 1 ))
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--repository)
                [ "$#" -ge 2 ] || { error '--repository needs a value'; return 1; }
                repository="$2"
                shift 2
                argc=$(( argc - 1 ))
                continue
                ;;
            --repository=*)
                repository="${1#*=}"
                shift
                continue
                ;;
            -d|--directory)
                [ "$#" -ge 2 ] || { error '--directory needs a value'; return 1; }
                install_dir="$2"
                shift 2
                argc=$(( argc - 1 ))
                continue
                ;;
            --directory=*)
                install_dir="${1#*=}"
                shift
                continue
                ;;
            *)
                set -- "$@" "$1"
                shift
                ;;
        esac
    done

    detect_package_manager
    ensure_git
    ensure_bash
    sync_repository
    run_machine_setup "$@"
}

# Run unless sourced by a test (the suite sets TEST_FLAG to inspect functions).
[ -n "${TEST_FLAG:-}" ] || main "$@"
