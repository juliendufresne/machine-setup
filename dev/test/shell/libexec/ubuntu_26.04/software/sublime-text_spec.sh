# Specs for the sublime-text unit on Ubuntu 26.04. TEST_FLAG keeps the unit's
# functions non-readonly so the spec can source it, and the unit's own Execute
# guard keeps it from running when Included. Every system-touching command (sudo,
# apt-get, curl, install, chmod, tee, dpkg, command) is stubbed so no package
# operation or file write ever reaches the real host, and the host probe is
# stubbed so the result never depends on the test machine.
Describe 'libexec/ubuntu_26.04/software/sublime-text.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/sublime-text.sh

    # Isolated host plus a log to spy on the commands. ST_ON_PATH drives
    # is_installed (does `command -v subl` resolve), ST_PRESENT drives is_managed
    # (does `dpkg -s sublime-text` report the package), and ST_HAS_DESKTOP drives
    # is_available. CMD_LOG is set before helper::isolate so the rm stub it
    # triggers has a valid target, then truncated.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=sublime-text
        : >"$CMD_LOG"                                   # discard isolate's own rm log
        : "${ST_ON_PATH:=1}"
        : "${ST_PRESENT:=1}"
        : "${ST_HAS_DESKTOP:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v subl`;
    # everything else logs its call instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    install() { printf 'install %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    chmod()   { printf 'chmod %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    tee()     { cat >/dev/null; printf 'tee %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    rm()      { printf 'rm %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    dpkg()    { [ "${ST_PRESENT}" = 1 ]; }

    command() {
        if [ "$1" = -v ] && [ "$2" = subl ]
        then [ "${ST_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${ST_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # sublime::text::_add_apt_repository
    # ==========================================================================
    Describe 'sublime::text::_add_apt_repository'

        It 'creates the keyring, fetches the key, and writes the sources list'
            When call sublime::text::_add_apt_repository
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o /etc/apt/keyrings/sublimehq-pub.gpg
chmod a+r /etc/apt/keyrings/sublimehq-pub.gpg
tee /etc/apt/sources.list.d/sublime-text.list'
        End

        It 'stops and propagates the status when a step fails'
            install() { return 4; }

            When call sublime::text::_add_apt_repository
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
            ST_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            ST_HAS_DESKTOP=0
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

        It 'is true when subl resolves on the host'
            ST_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when subl resolves nowhere'
            ST_ON_PATH=0
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

        It 'is true when dpkg reports the sublime-text package present'
            ST_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the sublime-text package absent'
            ST_PRESENT=0
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

        It 'is always satisfied because sublime-text needs no configuration'
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

        It 'sets up the repository then installs sublime-text and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Adding the Sublime Text apt repository'
            The line 4 of stdout should equal '  ✓ Updating the package lists'
            The line 5 of stdout should equal '  ✓ Installing the sublime-text package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o /etc/apt/keyrings/sublimehq-pub.gpg'
            The contents of file "$CMD_LOG" should include 'apt-get install -y sublime-text'
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
            ST_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when sublime-text is not present'
            ST_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when sublime-text is present but not via our package'
            ST_ON_PATH=1
            ST_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as sublime-text is present via our package'
            ST_ON_PATH=1
            ST_PRESENT=1
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

        It 'does nothing because sublime-text needs no configuration'
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

        It 'does nothing because sublime-text has no configuration to restore'
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

        It 'purges sublime-text and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the sublime-text package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'apt-get purge -y sublime-text'
        End

    End

    # ==========================================================================
    # sublime::text::main
    # ==========================================================================
    Describe 'sublime::text::main'

        It 'hands the action to the runner, which prints the status word'
            ST_HAS_DESKTOP=0
            When call sublime::text::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
