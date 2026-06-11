# Specs for the curl unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. dpkg, sudo, and apt-get are stubbed so no
# package operation ever touches the real host.
Describe 'libexec/ubuntu_26.04/software/curl.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/curl.sh

    # Isolated host and a log to spy on apt-get. CURL_ON_PATH drives is_installed
    # (does `command -v curl` resolve) and CURL_PRESENT drives is_managed (does
    # `dpkg -s curl` report the package), so a test can pretend curl is present by
    # any means, present via our package, or absent, without touching the host.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=curl
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
        : "${CURL_ON_PATH:=1}"
        : "${CURL_PRESENT:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v curl`; every other call falls through to the real builtin.
    command() {
        if [ "$1" = -v ] && [ "$2" = curl ]
        then [ "${CURL_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }
    dpkg()    { [ "${CURL_PRESENT}" = 1 ]; }            # `dpkg -s curl`
    sudo()    { "$@"; }                                # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }     # record the apt-get call

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when curl resolves on the host'
            CURL_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when curl resolves nowhere'
            CURL_ON_PATH=0
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

        It 'is true when dpkg reports the curl package present'
            CURL_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the curl package absent'
            CURL_PRESENT=0
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

        It 'is always satisfied because curl needs no configuration'
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

        It 'updates the package lists then installs curl and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the curl package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y curl'
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

        It 'reports available when curl is not present'
            CURL_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when curl is present but not via our package'
            CURL_ON_PATH=1
            CURL_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as curl is present via our package'
            CURL_ON_PATH=1
            CURL_PRESENT=1
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

        It 'does nothing because curl needs no configuration'
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

        It 'does nothing because curl has no configuration to restore'
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

        It 'purges curl and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the curl package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y curl'
        End

        It 'purges curl even when this tool never recorded installing it'
            # no ownership state seeded: uninstall must not depend on it
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the curl package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y curl'
        End

    End

    # ==========================================================================
    # curl::main
    # ==========================================================================
    Describe 'curl::main'

        It 'hands the action to the runner, which prints the status word'
            CURL_ON_PATH=0
            When call curl::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
