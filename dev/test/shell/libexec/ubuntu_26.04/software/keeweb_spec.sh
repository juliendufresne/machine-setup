# Specs for the keeweb unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. Every system-touching command (sudo, apt-get,
# curl, rm, dpkg, command) is stubbed so no package operation or file write ever
# reaches the real host, and the host probe is stubbed so the result never depends
# on the test machine.
Describe 'libexec/ubuntu_26.04/software/keeweb.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/keeweb.sh

    # Isolated host plus a log to spy on the commands. KW_ON_PATH drives
    # is_installed (does `command -v keeweb` resolve), KW_PRESENT drives is_managed
    # (does `dpkg -s keeweb-desktop` report the package), and KW_HAS_DESKTOP drives
    # is_available. TMPDIR is pinned under the temp base so the .deb path is stable.
    # CMD_LOG is set before helper::isolate so the rm stub it triggers has a valid
    # target, then truncated.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=keeweb
        export TMPDIR="$SHELLSPEC_TMPBASE"
        : >"$CMD_LOG"                                   # discard isolate's own rm log
        : "${KW_ON_PATH:=1}"
        : "${KW_PRESENT:=1}"
        : "${KW_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v keeweb`;
    # everything else logs its call instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    rm()      { printf 'rm %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    dpkg()    { [ "${KW_PRESENT}" = 1 ]; }

    command() {
        if [ "$1" = -v ] && [ "$2" = keeweb ]
        then [ "${KW_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${KW_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # keeweb::_deb_path
    # ==========================================================================
    Describe 'keeweb::_deb_path'

        It 'reports the .deb path under the temp directory'
            When call keeweb::_deb_path
            The status should be success
            The stdout should equal "$SHELLSPEC_TMPBASE/keeweb.deb"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # keeweb::_latest_deb_url
    # ==========================================================================
    Describe 'keeweb::_latest_deb_url'

        # Override curl to emit a GitHub releases API payload so the extraction is
        # exercised without reaching the network.
        It 'extracts the linux.x64.deb asset URL from the releases API'
            curl() {
                printf '%s\n' '  "tag_name": "v9.9.9",'
                printf '%s\n' '  "browser_download_url": "https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb",'
            }

            When call keeweb::_latest_deb_url
            The status should be success
            The stdout should equal 'https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # keeweb::_download_package
    # ==========================================================================
    Describe 'keeweb::_download_package'

        It 'downloads the resolved latest .deb to the temp path'
            keeweb::_latest_deb_url() { printf '%s' 'https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb'; }

            When call keeweb::_download_package
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "curl -fsSL https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb -o $SHELLSPEC_TMPBASE/keeweb.deb"
        End

        It 'fails without downloading when no release URL can be resolved'
            keeweb::_latest_deb_url() { printf ''; }

            When call keeweb::_download_package
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should be blank
        End

    End

    # ==========================================================================
    # keeweb::_install_package
    # ==========================================================================
    Describe 'keeweb::_install_package'

        It 'installs the downloaded .deb and removes it'
            When call keeweb::_install_package
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "apt-get install -y $SHELLSPEC_TMPBASE/keeweb.deb
rm -f $SHELLSPEC_TMPBASE/keeweb.deb"
        End

        It 'does not remove the .deb when the install fails'
            apt-get() { return 5; }

            When call keeweb::_install_package
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
            KW_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            KW_HAS_DESKTOP=0
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

        It 'is true when keeweb resolves on the host'
            KW_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when keeweb resolves nowhere'
            KW_ON_PATH=0
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

        It 'is true when dpkg reports the keeweb-desktop package present'
            KW_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the keeweb-desktop package absent'
            KW_PRESENT=0
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

        It 'is always satisfied because keeweb needs no configuration'
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

        It 'updates the lists, installs prerequisites, downloads, then installs keeweb and reports each step'
            keeweb::_latest_deb_url() { printf '%s' 'https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb'; }

            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Downloading KeeWeb'
            The line 4 of stdout should equal '  ✓ Installing the keeweb package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get install -y ca-certificates curl'
            The contents of file "$CMD_LOG" should include "curl -fsSL https://github.test/keeweb/KeeWeb-9.9.9.linux.x64.deb -o $SHELLSPEC_TMPBASE/keeweb.deb"
            The contents of file "$CMD_LOG" should include "apt-get install -y $SHELLSPEC_TMPBASE/keeweb.deb"
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
            KW_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when keeweb is not present'
            KW_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when keeweb is present but not via our package'
            KW_ON_PATH=1
            KW_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as keeweb is present via our package'
            KW_ON_PATH=1
            KW_PRESENT=1
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

        It 'does nothing because keeweb needs no configuration'
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

        It 'does nothing because keeweb has no configuration to restore'
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

        It 'purges keeweb and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the keeweb package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'apt-get purge -y keeweb-desktop'
        End

    End

    # ==========================================================================
    # keeweb::main
    # ==========================================================================
    Describe 'keeweb::main'

        It 'hands the action to the runner, which prints the status word'
            KW_HAS_DESKTOP=0
            When call keeweb::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
