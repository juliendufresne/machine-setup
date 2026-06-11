# Specs for the vlc unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. Every system-touching command (sudo, apt-get,
# dpkg, command) is stubbed so no package operation ever reaches the real host,
# and the host probe is stubbed so the result never depends on the test machine.
Describe 'libexec/ubuntu_26.04/software/vlc.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/vlc.sh

    # Isolated host plus a log to spy on the commands. VLC_ON_PATH drives
    # is_installed (does `command -v vlc` resolve), VLC_PRESENT drives is_managed
    # (does `dpkg -s vlc` report the package), and VLC_HAS_DESKTOP drives
    # is_available.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=vlc
        : >"$CMD_LOG"
        : "${VLC_ON_PATH:=1}"
        : "${VLC_PRESENT:=1}"
        : "${VLC_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v vlc`;
    # apt-get logs its call instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    dpkg()    { [ "${VLC_PRESENT}" = 1 ]; }

    command() {
        if [ "$1" = -v ] && [ "$2" = vlc ]
        then [ "${VLC_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${VLC_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is true when the host has a desktop'
            VLC_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            VLC_HAS_DESKTOP=0
            When call unit::is_available
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when vlc resolves on the host'
            VLC_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when vlc resolves nowhere'
            VLC_ON_PATH=0
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

        It 'is true when dpkg reports the vlc package present'
            VLC_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the vlc package absent'
            VLC_PRESENT=0
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

        It 'is always satisfied because vlc needs no configuration'
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

        It 'updates the lists then installs vlc and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the vlc package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get install -y vlc'
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

        It 'reports unavailable when the host has no desktop'
            VLC_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when vlc is not present'
            VLC_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when vlc is present but not via our package'
            VLC_ON_PATH=1
            VLC_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as vlc is present via our package'
            VLC_ON_PATH=1
            VLC_PRESENT=1
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

        It 'does nothing because vlc needs no configuration'
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

        It 'does nothing because vlc has no configuration to restore'
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

        It 'purges vlc and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the vlc package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'apt-get purge -y vlc'
        End

    End

    # ==========================================================================
    # vlc::main
    # ==========================================================================
    Describe 'vlc::main'

        It 'hands the action to the runner, which prints the status word'
            VLC_HAS_DESKTOP=0
            When call vlc::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
