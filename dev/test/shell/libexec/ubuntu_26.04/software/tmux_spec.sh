# Specs for the tmux unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. dpkg, sudo, and apt-get are stubbed so no
# package operation ever touches the real host.
Describe 'libexec/ubuntu_26.04/software/tmux.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/tmux.sh

    # Isolated host and a log to spy on apt-get. TMUX_ON_PATH drives is_installed
    # (does `command -v tmux` resolve) and TMUX_PRESENT drives is_managed (does
    # `dpkg -s tmux` report the package), so a test can pretend tmux is present by
    # any means, present via our package, or absent, without touching the host.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=tmux
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
        : "${TMUX_ON_PATH:=1}"
        : "${TMUX_PRESENT:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v tmux`; every other call falls through to the real builtin.
    command() {
        if [ "$1" = -v ] && [ "$2" = tmux ]
        then [ "${TMUX_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }
    dpkg()    { [ "${TMUX_PRESENT}" = 1 ]; }           # `dpkg -s tmux`
    sudo()    { "$@"; }                                # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }     # record the apt-get call

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when tmux resolves on the host'
            TMUX_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when tmux resolves nowhere'
            TMUX_ON_PATH=0
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

        It 'is true when dpkg reports the tmux package present'
            TMUX_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the tmux package absent'
            TMUX_PRESENT=0
            When call unit::is_managed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_configured
    # ==========================================================================
    Describe 'unit::is_configured'

        It 'is always satisfied because tmux needs no configuration'
            When call unit::is_configured
            The status should be success
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

        It 'updates the package lists then installs tmux and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the tmux package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y tmux'
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

        It 'reports available when tmux is not present'
            TMUX_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when tmux is present but not via our package'
            TMUX_ON_PATH=1
            TMUX_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as tmux is present via our package'
            TMUX_ON_PATH=1
            TMUX_PRESENT=1
            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::configure
    # ==========================================================================
    Describe 'unit::configure'

        It 'does nothing because tmux needs no configuration'
            When call unit::configure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::unconfigure
    # ==========================================================================
    Describe 'unit::unconfigure'

        It 'does nothing because tmux has no configuration to restore'
            When call unit::unconfigure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::uninstall
    # ==========================================================================
    Describe 'unit::uninstall'

        It 'purges tmux and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the tmux package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y tmux'
        End

        It 'purges tmux even when this tool never recorded installing it'
            # no ownership state seeded: uninstall must not depend on it
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the tmux package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y tmux'
        End

    End

    # ==========================================================================
    # tmux::main
    # ==========================================================================
    Describe 'tmux::main'

        It 'hands the action to the runner, which prints the status word'
            TMUX_ON_PATH=0
            When call tmux::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
