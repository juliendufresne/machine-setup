# Specs for the discord unit on Ubuntu 26.04. TEST_FLAG keeps the unit's
# functions non-readonly so the spec can source it, and the unit's own Execute
# guard keeps it from running when Included. Every system-touching command (sudo,
# apt-get, curl, rm, dpkg, command) is stubbed so no package operation or file
# write ever reaches the real host, and the host probe is stubbed so the result
# never depends on the test machine.
Describe 'libexec/ubuntu_26.04/software/discord.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/discord.sh

    # Isolated host plus a log to spy on the commands. DC_ON_PATH drives
    # is_installed (does `command -v discord` resolve), DC_PRESENT drives
    # is_managed (does `dpkg -s discord` report the package), and DC_HAS_DESKTOP
    # drives is_available. TMPDIR is pinned under the temp base so the .deb path
    # is stable. CMD_LOG is set before helper::isolate so the rm stub it triggers
    # has a valid target, then truncated.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=discord
        export TMPDIR="$SHELLSPEC_TMPBASE"
        : >"$CMD_LOG"                                   # discard isolate's own rm log
        : "${DC_ON_PATH:=1}"
        : "${DC_PRESENT:=1}"
        : "${DC_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v discord`;
    # everything else logs its call instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    rm()      { printf 'rm %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    dpkg()    { [ "${DC_PRESENT}" = 1 ]; }

    command() {
        if [ "$1" = -v ] && [ "$2" = discord ]
        then [ "${DC_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${DC_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # discord::_deb_path
    # ==========================================================================
    Describe 'discord::_deb_path'

        It 'reports the .deb path under the temp directory'
            When call discord::_deb_path
            The status should be success
            The stdout should equal "$SHELLSPEC_TMPBASE/discord.deb"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # discord::_download_package
    # ==========================================================================
    Describe 'discord::_download_package'

        It 'downloads the .deb from the discord.com endpoint'
            When call discord::_download_package
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "curl -fsSL https://discord.com/api/download?platform=linux&format=deb -o $SHELLSPEC_TMPBASE/discord.deb"
        End

    End

    # ==========================================================================
    # discord::_install_package
    # ==========================================================================
    Describe 'discord::_install_package'

        It 'installs the downloaded .deb and removes it'
            When call discord::_install_package
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "apt-get install -y $SHELLSPEC_TMPBASE/discord.deb
rm -f $SHELLSPEC_TMPBASE/discord.deb"
        End

        It 'does not remove the .deb when the install fails'
            apt-get() { return 5; }

            When call discord::_install_package
            The status should equal 5
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should be blank
        End

    End

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is true when the host has a desktop'
            DC_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            DC_HAS_DESKTOP=0
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

        It 'is true when discord resolves on the host'
            DC_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when discord resolves nowhere'
            DC_ON_PATH=0
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

        It 'is true when dpkg reports the discord package present'
            DC_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the discord package absent'
            DC_PRESENT=0
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

        It 'is always satisfied because discord needs no configuration'
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

        It 'updates the lists, installs prerequisites, downloads, then installs discord and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Downloading Discord'
            The line 4 of stdout should equal '  ✓ Installing the discord package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get install -y ca-certificates curl'
            The contents of file "$CMD_LOG" should include "curl -fsSL https://discord.com/api/download?platform=linux&format=deb -o $SHELLSPEC_TMPBASE/discord.deb"
            The contents of file "$CMD_LOG" should include "apt-get install -y $SHELLSPEC_TMPBASE/discord.deb"
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
            DC_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when discord is not present'
            DC_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when discord is present but not via our package'
            DC_ON_PATH=1
            DC_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as discord is present via our package'
            DC_ON_PATH=1
            DC_PRESENT=1
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

        It 'does nothing because discord needs no configuration'
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

        It 'does nothing because discord has no configuration to restore'
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

        It 'purges discord and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the discord package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'apt-get purge -y discord'
        End

    End

    # ==========================================================================
    # discord::main
    # ==========================================================================
    Describe 'discord::main'

        It 'hands the action to the runner, which prints the status word'
            DC_HAS_DESKTOP=0
            When call discord::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
