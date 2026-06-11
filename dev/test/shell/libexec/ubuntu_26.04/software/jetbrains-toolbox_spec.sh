# Specs for the jetbrains-toolbox unit on Ubuntu 26.04. TEST_FLAG keeps the unit's
# functions non-readonly so the spec can source it, and the unit's own Execute
# guard keeps it from running when Included. The system-touching commands that
# fetch and unpack the tarball (sudo, apt-get, curl, tar, command) are stubbed so
# no download or apt operation reaches the real host; mkdir, ln, and rm run for
# real but only ever against the temp base, because the fs-touching tests redirect
# the install paths there. The host probe is stubbed so the result never depends
# on the test machine.
Describe 'libexec/ubuntu_26.04/software/jetbrains-toolbox.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/jetbrains-toolbox.sh

    # Isolated host plus a log to spy on the commands. JT_ON_PATH drives
    # is_installed (does `command -v jetbrains-toolbox` resolve) and JT_HAS_DESKTOP
    # drives is_available; is_managed is a file-presence check that the fs-touching
    # tests steer by redirecting the install directory under the temp base. TMPDIR
    # is pinned under the temp base so the tarball path is stable.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=jetbrains-toolbox
        export TMPDIR="$SHELLSPEC_TMPBASE"
        : >"$CMD_LOG"
        : "${JT_ON_PATH:=1}"
        : "${JT_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the commands that must not touch the host. sudo runs the wrapped
    # command so its stub is exercised; command is shadowed only for `command -v
    # jetbrains-toolbox`; tar, apt-get, and curl log their calls. mkdir, ln, and rm
    # are left real so the extract/link/cleanup logic is exercised against the temp
    # paths the fs-touching tests provide.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    tar()     { printf 'tar %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }

    command() {
        if [ "$1" = -v ] && [ "$2" = jetbrains-toolbox ]
        then [ "${JT_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${JT_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # jetbrains::toolbox::_install_dir
    # ==========================================================================
    Describe 'jetbrains::toolbox::_install_dir'

        It 'reports the directory the tarball is extracted into'
            When call jetbrains::toolbox::_install_dir
            The status should be success
            The stdout should equal '/opt/jetbrains-toolbox'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # jetbrains::toolbox::_symlink_path
    # ==========================================================================
    Describe 'jetbrains::toolbox::_symlink_path'

        It 'reports the launcher symlink path on PATH'
            When call jetbrains::toolbox::_symlink_path
            The status should be success
            The stdout should equal '/usr/local/bin/jetbrains-toolbox'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # jetbrains::toolbox::_tarball_path
    # ==========================================================================
    Describe 'jetbrains::toolbox::_tarball_path'

        It 'reports the tarball path under the temp directory'
            When call jetbrains::toolbox::_tarball_path
            The status should be success
            The stdout should equal "$SHELLSPEC_TMPBASE/jetbrains-toolbox.tar.gz"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # jetbrains::toolbox::_download_archive
    # ==========================================================================
    Describe 'jetbrains::toolbox::_download_archive'

        It 'downloads the tarball from the JetBrains download redirect'
            When call jetbrains::toolbox::_download_archive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "curl -fsSL https://data.services.jetbrains.com/products/download?platform=linux&code=TBA -o $SHELLSPEC_TMPBASE/jetbrains-toolbox.tar.gz"
        End

    End

    # ==========================================================================
    # jetbrains::toolbox::_install_archive
    # ==========================================================================
    Describe 'jetbrains::toolbox::_install_archive'

        It 'extracts the tarball into the install directory and links the launcher'
            jetbrains::toolbox::_install_dir()  { printf '%s' "$SHELLSPEC_TMPBASE/jtb"; }
            jetbrains::toolbox::_symlink_path() { printf '%s' "$SHELLSPEC_TMPBASE/jtb-link"; }

            When call jetbrains::toolbox::_install_archive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal "tar -xzf $SHELLSPEC_TMPBASE/jetbrains-toolbox.tar.gz -C $SHELLSPEC_TMPBASE/jtb --strip-components=1"
            The path "$SHELLSPEC_TMPBASE/jtb" should be directory
            The path "$SHELLSPEC_TMPBASE/jtb-link" should be symlink
        End

    End

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is true when the host has a desktop'
            JT_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            JT_HAS_DESKTOP=0
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

        It 'is true when jetbrains-toolbox resolves on the host'
            JT_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when jetbrains-toolbox resolves nowhere'
            JT_ON_PATH=0
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

        It 'is true when our extracted launcher is present'
            jetbrains::toolbox::_install_dir() { printf '%s' "$SHELLSPEC_TMPBASE/jtb"; }
            mkdir -p "$SHELLSPEC_TMPBASE/jtb/bin"
            : >"$SHELLSPEC_TMPBASE/jtb/bin/jetbrains-toolbox"

            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when our extracted launcher is absent'
            jetbrains::toolbox::_install_dir() { printf '%s' "$SHELLSPEC_TMPBASE/absent"; }

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

        It 'is always satisfied because jetbrains-toolbox needs no configuration'
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

        It 'warms the sudo session because the install steps need root'
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

        It 'updates the lists, downloads, then extracts jetbrains-toolbox and reports each step'
            jetbrains::toolbox::_install_dir()  { printf '%s' "$SHELLSPEC_TMPBASE/jtb"; }
            jetbrains::toolbox::_symlink_path() { printf '%s' "$SHELLSPEC_TMPBASE/jtb-link"; }

            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Downloading JetBrains Toolbox'
            The line 4 of stdout should equal '  ✓ Installing the JetBrains Toolbox archive'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include "curl -fsSL https://data.services.jetbrains.com/products/download?platform=linux&code=TBA -o $SHELLSPEC_TMPBASE/jetbrains-toolbox.tar.gz"
            The contents of file "$CMD_LOG" should include "tar -xzf $SHELLSPEC_TMPBASE/jetbrains-toolbox.tar.gz -C $SHELLSPEC_TMPBASE/jtb --strip-components=1"
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
            JT_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when jetbrains-toolbox is not present'
            JT_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when jetbrains-toolbox is present but not via our mechanism'
            JT_ON_PATH=1
            jetbrains::toolbox::_install_dir() { printf '%s' "$SHELLSPEC_TMPBASE/absent"; }

            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as our extracted launcher is present'
            JT_ON_PATH=1
            jetbrains::toolbox::_install_dir() { printf '%s' "$SHELLSPEC_TMPBASE/jtb"; }
            mkdir -p "$SHELLSPEC_TMPBASE/jtb/bin"
            : >"$SHELLSPEC_TMPBASE/jtb/bin/jetbrains-toolbox"

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

        It 'does nothing because jetbrains-toolbox needs no configuration'
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

        It 'does nothing because jetbrains-toolbox has no configuration to restore'
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

        It 'removes the launcher and the install directory and reports each step'
            jetbrains::toolbox::_install_dir()  { printf '%s' "$SHELLSPEC_TMPBASE/jtb"; }
            jetbrains::toolbox::_symlink_path() { printf '%s' "$SHELLSPEC_TMPBASE/jtb-link"; }
            mkdir -p "$SHELLSPEC_TMPBASE/jtb"
            : >"$SHELLSPEC_TMPBASE/jtb-link"

            When call unit::uninstall
            The status should be success
            The line 1 of stdout should equal '  ✓ Removing the jetbrains-toolbox launcher'
            The line 2 of stdout should equal '  ✓ Removing the JetBrains Toolbox install directory'
            The stderr should be blank
            The path "$SHELLSPEC_TMPBASE/jtb-link" should not be exist
            The path "$SHELLSPEC_TMPBASE/jtb" should not be exist
        End

    End

    # ==========================================================================
    # jetbrains::toolbox::main
    # ==========================================================================
    Describe 'jetbrains::toolbox::main'

        It 'hands the action to the runner, which prints the status word'
            JT_HAS_DESKTOP=0
            When call jetbrains::toolbox::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
