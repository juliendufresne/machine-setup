# Specs for the fish unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. dpkg, sudo, and apt-get are stubbed so no package
# operation ever touches the real host; getent and id are stubbed so the login
# shell is whatever DEFAULT_SHELL says. The unit sources its
# lib/software/fish/configure fragment, so unit::is_configured is available here
# and drives runner::status; the configuration contract itself is covered by that
# fragment's configure_spec.sh, so only the status path edits rc files under the
# isolated HOME here.
Describe 'libexec/ubuntu_26.04/software/fish.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/fish.sh

    # Isolated host and a log to spy on apt-get. FISH_ON_PATH drives is_installed
    # (does `command -v fish` resolve) and FISH_PRESENT drives is_managed (does
    # `dpkg -s fish` report the package). DEFAULT_SHELL is the basename of the
    # login shell that getent reports, so a test can pretend bash, zsh, or fish is
    # the default without touching the host.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=fish
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
        : "${FISH_ON_PATH:=1}"
        : "${FISH_PRESENT:=1}"
        : "${DEFAULT_SHELL:=bash}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v fish`; every other call falls through to the real builtin. getent
    # and id together report DEFAULT_SHELL as the login shell.
    command() {
        if [ "$1" = -v ] && [ "$2" = fish ]
        then [ "${FISH_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }
    dpkg()    { [ "${FISH_PRESENT}" = 1 ]; }                                     # `dpkg -s fish`
    sudo()    { "$@"; }                                                          # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }                              # record the apt-get call
    id()      { printf 'tester\n'; }                                            # `id -un`
    getent()  { printf 'tester:x:1000:1000::/home/tester:/usr/bin/%s\n' "$DEFAULT_SHELL"; }

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when fish resolves on the host'
            FISH_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when fish resolves nowhere'
            FISH_ON_PATH=0
            When call unit::is_installed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_managed
    # ==========================================================================
    Describe 'unit::is_managed'

        It 'is true when dpkg reports the fish package present'
            FISH_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the fish package absent'
            FISH_PRESENT=0
            When call unit::is_managed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::request_inputs
    # ==========================================================================
    Describe 'unit::request_inputs'

        It 'warms the sudo session because the package steps need root'
            sudo::warmup() { return 0; }

            When call unit::request_inputs
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::install
    # ==========================================================================
    Describe 'unit::install'

        It 'updates the package lists then installs fish and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the fish package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y fish'
        End

        It 'stops at the failing step and propagates its status'
            apt-get() { return 7; }

            When call unit::install
            The status should equal 7
            The stdout should be blank
            The stderr should equal '  ✗ Updating the package lists'
        End

    End

    # ==========================================================================
    # runner::status
    # ==========================================================================
    Describe 'runner::status'

        It 'reports available when fish is not present'
            FISH_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when fish is present but not via our package'
            FISH_ON_PATH=1
            FISH_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports installed when ours but the login shell rc lacks the block'
            FISH_ON_PATH=1
            FISH_PRESENT=1
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"

            When call runner::status
            The status should be success
            The stdout should equal 'installed'
            The stderr should be blank
        End

        It 'reports configured when ours and the hand-off is in place'
            FISH_ON_PATH=1
            FISH_PRESENT=1
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::uninstall
    # ==========================================================================
    Describe 'unit::uninstall'

        It 'purges fish and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the fish package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y fish'
        End

        It 'purges fish even when this tool never recorded installing it'
            # no ownership state seeded: uninstall must not depend on it
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the fish package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y fish'
        End

    End

    # ==========================================================================
    # fish::main
    # ==========================================================================
    Describe 'fish::main'

        It 'hands the action to the runner, which prints the status word'
            FISH_ON_PATH=0
            When call fish::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
