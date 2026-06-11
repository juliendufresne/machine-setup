# Specs for the spotify unit on Ubuntu 26.04. TEST_FLAG keeps the unit's
# functions non-readonly so the spec can source it, and the unit's own Execute
# guard keeps it from running when Included. Every system-touching command (sudo,
# apt-get, curl, gpg, install, chmod, tee, dpkg, command) is stubbed so no package
# operation or file write ever reaches the real host, and the host probe is
# stubbed so the result never depends on the test machine.
Describe 'libexec/ubuntu_26.04/software/spotify.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/spotify.sh

    # Isolated host plus a log to spy on the commands. SP_ON_PATH drives
    # is_installed (does `command -v spotify` resolve), SP_PRESENT drives
    # is_managed (does `dpkg -s spotify-client` report the package), and
    # SP_HAS_DESKTOP drives is_available.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=spotify
        : >"$CMD_LOG"
        : "${SP_ON_PATH:=1}"
        : "${SP_PRESENT:=1}"
        : "${SP_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v spotify`;
    # gpg and tee consume their piped input and everything else logs its call
    # instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    gpg()     { cat >/dev/null; printf 'gpg %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    install() { printf 'install %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    chmod()   { printf 'chmod %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    tee()     { cat >/dev/null; printf 'tee %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    dpkg()    { [ "${SP_PRESENT}" = 1 ]; }

    command() {
        if [ "$1" = -v ] && [ "$2" = spotify ]
        then [ "${SP_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${SP_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # spotify::_add_apt_repository
    # ==========================================================================
    Describe 'spotify::_add_apt_repository'

        It 'creates the keyring, dearmors the key, and writes the sources list'
            When call spotify::_add_apt_repository
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'install -m 0755 -d /etc/apt/keyrings'
            The contents of file "$CMD_LOG" should include 'curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc'
            The contents of file "$CMD_LOG" should include 'gpg --dearmor -o /etc/apt/keyrings/spotify.gpg'
            The contents of file "$CMD_LOG" should include 'chmod a+r /etc/apt/keyrings/spotify.gpg'
            The contents of file "$CMD_LOG" should include 'tee /etc/apt/sources.list.d/spotify.list'
        End

        It 'stops and propagates the status when a step fails'
            install() { return 4; }

            When call spotify::_add_apt_repository
            The status should equal 4
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is true when the host has a desktop'
            SP_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            SP_HAS_DESKTOP=0
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

        It 'is true when spotify resolves on the host'
            SP_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when spotify resolves nowhere'
            SP_ON_PATH=0
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

        It 'is true when dpkg reports the spotify-client package present'
            SP_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the spotify-client package absent'
            SP_PRESENT=0
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

        It 'is always satisfied because spotify needs no configuration'
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

        It 'sets up the repository then installs spotify-client and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Adding the Spotify apt repository'
            The line 4 of stdout should equal '  ✓ Updating the package lists'
            The line 5 of stdout should equal '  ✓ Installing the spotify-client package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc'
            The contents of file "$CMD_LOG" should include 'apt-get install -y spotify-client'
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
            SP_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when spotify is not present'
            SP_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when spotify is present but not via our package'
            SP_ON_PATH=1
            SP_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as spotify is present via our package'
            SP_ON_PATH=1
            SP_PRESENT=1
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

        It 'does nothing because spotify needs no configuration'
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

        It 'does nothing because spotify has no configuration to restore'
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

        It 'purges spotify-client and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the spotify-client package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'apt-get purge -y spotify-client'
        End

    End

    # ==========================================================================
    # spotify::main
    # ==========================================================================
    Describe 'spotify::main'

        It 'hands the action to the runner, which prints the status word'
            SP_HAS_DESKTOP=0
            When call spotify::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
