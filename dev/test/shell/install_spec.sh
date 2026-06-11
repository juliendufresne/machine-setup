# Specs for the POSIX sh bootstrap. TEST_FLAG keeps main from running on Include
# so the spec can exercise each helper in isolation. The package manager and
# privilege escalation are always mocked, and OS_RELEASE_FILE is pointed at a
# fixture, so no example ever reads the real host or mutates it.
Describe 'install.sh'
    TEST_FLAG=true
    Include install.sh

    setup() {
        helper::isolate
    }
    BeforeEach 'setup'

    # ==========================================================================
    # info
    # ==========================================================================
    Describe 'info'

        It 'writes the message to stderr'
            When call info 'cloning'
            The status should be success
            The stdout should be blank
            The stderr should equal 'cloning'
        End

    End

    # ==========================================================================
    # error
    # ==========================================================================
    Describe 'error'

        It 'writes the message to stderr with the program prefix'
            When call error 'boom'
            The status should be success
            The stdout should be blank
            The stderr should equal 'install.sh: error: boom'
        End

    End

    # ==========================================================================
    # usage
    # ==========================================================================
    Describe 'usage'

        It 'prints the bootstrap usage to stderr'
            When call usage
            The status should be success
            The stdout should be blank
            The stderr should include 'machine-setup bootstrap'
        End

    End

    # ==========================================================================
    # as_root
    # ==========================================================================
    Describe 'as_root'

        It 'runs the command directly when already root'
            id() { printf '0'; }

            When call as_root printf 'ran %s\n' here
            The status should be success
            The stdout should equal 'ran here'
            The stderr should be blank
        End

        It 'runs the command through sudo when not root'
            id() { printf '1000'; }
            sudo() { printf 'sudo %s\n' "$*"; }

            When call as_root apt-get install git
            The status should be success
            The stdout should equal 'sudo apt-get install git'
            The stderr should be blank
        End

        It 'dies when not root and sudo is unavailable'
            id() { printf '1000'; }
            command() { return 1; }

            When run as_root apt-get install git
            The status should equal 1
            The stdout should be blank
            The stderr should include 'root privileges required'
        End

    End

    # ==========================================================================
    # apt_update_once
    # ==========================================================================
    Describe 'apt_update_once'

        as_root() { printf 'root: %s\n' "$*"; }

        It 'refreshes the package lists on the first call'
            APT_UPDATED=0

            When call apt_update_once
            The status should be success
            The stdout should equal 'root: apt-get update -qq'
            The stderr should include 'Updating package lists'
        End

        It 'does nothing when the lists were already refreshed'
            APT_UPDATED=1

            When call apt_update_once
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # apt_install
    # ==========================================================================
    Describe 'apt_install'

        apt_update_once() { :; }
        as_root() { printf 'root: %s\n' "$*"; }

        It 'installs the packages non-interactively as root'
            When call apt_install git curl
            The status should be success
            The stdout should equal 'root: env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl'
            The stderr should include 'Installing: git curl'
        End

    End

    # ==========================================================================
    # pkg_install
    # ==========================================================================
    Describe 'pkg_install'

        apt_install() { printf 'apt %s\n' "$*"; }

        It 'dispatches to the apt backend when apt is selected'
            PACKAGE_MANAGER=apt

            When call pkg_install git curl
            The status should be success
            The stdout should equal 'apt git curl'
            The stderr should be blank
        End

        It 'dies when no installer is wired for the package manager'
            PACKAGE_MANAGER=dnf

            When run pkg_install git
            The status should equal 1
            The stdout should be blank
            The stderr should include 'no installer wired'
        End

    End

    # ==========================================================================
    # unsupported_distribution
    # ==========================================================================
    Describe 'unsupported_distribution'

        It 'names the detected id and the steps to add support'
            When run unsupported_distribution fedora
            The status should equal 1
            The stdout should be blank
            The stderr should include "unsupported distribution 'fedora'"
            The stderr should include 'add support'
        End

        It 'points at extending detection when no id could be read'
            When run unsupported_distribution
            The status should equal 1
            The stdout should be blank
            The stderr should include 'could not determine the distribution'
            The stderr should include 'fallback source'
        End

    End

    # ==========================================================================
    # detect_package_manager
    # ==========================================================================
    Describe 'detect_package_manager'

        setup_release() {
            OS_RELEASE_FILE="$SHELLSPEC_TMPBASE/os-release"
        }
        BeforeEach 'setup_release'

        It 'selects apt on a host whose os-release reports Ubuntu'
            printf 'ID=ubuntu\n' >"$OS_RELEASE_FILE"

            When call detect_package_manager
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The variable PACKAGE_MANAGER should equal 'apt'
        End

        It 'defers to unsupported_distribution when the os-release is unreadable'
            OS_RELEASE_FILE="$SHELLSPEC_TMPBASE/missing"

            When run detect_package_manager
            The status should equal 1
            The stdout should be blank
            The stderr should include 'could not determine the distribution'
        End

        It 'defers to unsupported_distribution when the os-release carries no ID'
            printf 'NAME=Whatever\n' >"$OS_RELEASE_FILE"

            When run detect_package_manager
            The status should equal 1
            The stdout should be blank
            The stderr should include 'could not determine the distribution'
        End

        It 'reports the detected id on an unsupported distribution'
            printf 'ID=debian\n' >"$OS_RELEASE_FILE"

            When run detect_package_manager
            The status should equal 1
            The stdout should be blank
            The stderr should include "unsupported distribution 'debian'"
        End

    End

    # ==========================================================================
    # ensure_git
    # ==========================================================================
    Describe 'ensure_git'

        pkg_install() { printf 'install %s\n' "$*"; }

        It 'does nothing when git is already on PATH'
            git() { :; }

            When call ensure_git
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'installs git when it is missing'
            command() { return 1; }

            When call ensure_git
            The status should be success
            The stdout should equal 'install git'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # bash_recent
    # ==========================================================================
    Describe 'bash_recent'

        It 'fails when no bash is on PATH'
            command() { return 1; }

            When call bash_recent
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'succeeds when the available bash meets the floor'
            bash() { return 0; }

            When call bash_recent
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails when the available bash is older than the floor'
            bash() { return 1; }

            When call bash_recent
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ensure_bash
    # ==========================================================================
    Describe 'ensure_bash'

        pkg_install() { :; }

        It 'does nothing when bash is already recent enough'
            bash_recent() { return 0; }

            When call ensure_bash
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'installs a newer bash and returns once the floor is met'
            attempts="$SHELLSPEC_TMPBASE/bash-attempts"
            : >"$attempts"
            bash_recent() {
                printf 'x' >>"$attempts"
                [ "$(wc -c <"$attempts")" -ge 2 ]
            }

            When call ensure_bash
            The status should be success
            The stdout should be blank
            The stderr should include 'installing a newer one'
        End

        It 'dies when bash is still too old after the install'
            bash_recent() { return 1; }

            When run ensure_bash
            The status should equal 1
            The stdout should be blank
            The stderr should include 'still older'
        End

    End

    # ==========================================================================
    # sync_repository
    # ==========================================================================
    Describe 'sync_repository'

        git() { printf 'git %s\n' "$*"; }

        setup_paths() {
            install_dir="$SHELLSPEC_TMPBASE/checkout"
            repository='https://example.invalid/repo.git'
            rm -rf "$install_dir"
        }
        BeforeEach 'setup_paths'

        It 'fast-forwards an existing checkout'
            mkdir -p "$install_dir/.git"

            When call sync_repository
            The status should be success
            The stdout should equal "git -C $install_dir pull --ff-only"
            The stderr should include 'Updating checkout'
        End

        It 'dies when the directory exists but is not a checkout'
            mkdir -p "$install_dir"

            When run sync_repository
            The status should equal 1
            The stdout should be blank
            The stderr should include 'not a machine-setup checkout'
        End

        It 'clones the repository when nothing is there yet'
            When call sync_repository
            The status should be success
            The stdout should equal "git clone $repository $install_dir"
            The stderr should include 'Cloning'
        End

    End

    # ==========================================================================
    # run_machine_setup
    # ==========================================================================
    Describe 'run_machine_setup'

        setup_entrypoint() {
            install_dir="$SHELLSPEC_TMPBASE/checkout"
            rm -rf "$install_dir"
        }
        BeforeEach 'setup_entrypoint'

        It 'dies when the orchestrator is missing'
            mkdir -p "$install_dir"

            When run run_machine_setup
            The status should equal 1
            The stdout should be blank
            The stderr should include 'missing or not executable'
        End

        It 'execs the orchestrator, forwarding the remaining options'
            mkdir -p "$install_dir/bin"
            printf '#!/bin/sh\nprintf "orchestrator %%s\\n" "$*"\n' >"$install_dir/bin/machine-setup"
            chmod +x "$install_dir/bin/machine-setup"

            When run run_machine_setup --some-option
            The status should be success
            The stdout should equal 'orchestrator --some-option'
            The stderr should include 'Running bin/machine-setup'
        End

    End

    # ==========================================================================
    # main
    # ==========================================================================
    Describe 'main'

        detect_package_manager() { :; }
        ensure_git() { :; }
        ensure_bash() { :; }
        sync_repository() { :; }
        run_machine_setup() { printf 'forward:%s\n' "$*"; }

        It 'prints usage and exits zero for --help'
            usage() { printf 'USAGE\n' >&2; }

            When run main --help
            The status should be success
            The stdout should be blank
            The stderr should equal 'USAGE'
        End

        It 'runs every step in order then hands over to the orchestrator'
            detect_package_manager() { printf 'detect\n'; }
            ensure_git() { printf 'git\n'; }
            ensure_bash() { printf 'bash\n'; }
            sync_repository() { printf 'sync\n'; }

            When call main
            The status should be success
            The line 1 of stdout should equal 'detect'
            The line 2 of stdout should equal 'git'
            The line 3 of stdout should equal 'bash'
            The line 4 of stdout should equal 'sync'
            The line 5 of stdout should equal 'forward:'
            The stderr should be blank
        End

        It 'consumes the repository option and forwards the rest'
            When call main --repository https://example.invalid/r.git extra
            The status should be success
            The stdout should equal 'forward:extra'
            The stderr should be blank
        End

        It 'accepts the joined repository option form'
            When call main --repository=https://example.invalid/r.git
            The status should be success
            The stdout should equal 'forward:'
            The stderr should be blank
        End

        It 'dies when the repository option has no value'
            When run main --repository
            The status should equal 1
            The stdout should be blank
            The stderr should include '--repository needs a value'
        End

        It 'consumes the directory option and forwards the rest'
            When call main --directory /tmp/elsewhere extra
            The status should be success
            The stdout should equal 'forward:extra'
            The stderr should be blank
        End

        It 'accepts the joined directory option form'
            When call main --directory=/tmp/elsewhere
            The status should be success
            The stdout should equal 'forward:'
            The stderr should be blank
        End

        It 'dies when the directory option has no value'
            When run main --directory
            The status should equal 1
            The stdout should be blank
            The stderr should include '--directory needs a value'
        End

        It 'forwards every option it does not recognise to the orchestrator'
            When call main --foo --bar
            The status should be success
            The stdout should equal 'forward:--foo --bar'
            The stderr should be blank
        End

    End

End
