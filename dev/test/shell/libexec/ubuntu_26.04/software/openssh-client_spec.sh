# Specs for the openssh-client unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. dpkg, sudo, and apt-get are stubbed so no
# package operation ever touches the real host.
Describe 'libexec/ubuntu_26.04/software/openssh-client.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/openssh-client.sh

    # Isolated host and a log to spy on apt-get. OPENSSH_CLIENT_ON_PATH drives is_installed
    # (does `command -v ssh` resolve) and OPENSSH_CLIENT_PRESENT drives is_managed (does
    # `dpkg -s openssh-client` report the package), so a test can pretend openssh-client is present by
    # any means, present via our package, or absent, without touching the host.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=openssh-client
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
        : "${OPENSSH_CLIENT_ON_PATH:=1}"
        : "${OPENSSH_CLIENT_PRESENT:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v ssh`; every other call falls through to the real builtin.
    command() {
        if [ "$1" = -v ] && [ "$2" = ssh ]
        then [ "${OPENSSH_CLIENT_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }
    dpkg()    { [ "${OPENSSH_CLIENT_PRESENT}" = 1 ]; }  # `dpkg -s openssh-client`
    sudo()    { "$@"; }                                  # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }      # record the apt-get call

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when ssh resolves on the host'
            OPENSSH_CLIENT_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when ssh resolves nowhere'
            OPENSSH_CLIENT_ON_PATH=0
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

        It 'is true when dpkg reports the openssh-client package present'
            OPENSSH_CLIENT_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the openssh-client package absent'
            OPENSSH_CLIENT_PRESENT=0
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

        It 'is always satisfied because openssh-client needs no configuration'
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

        It 'updates the package lists then installs openssh-client and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the openssh-client package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y openssh-client'
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

        It 'reports available when openssh-client is not present'
            OPENSSH_CLIENT_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when openssh-client is present but not via our package'
            OPENSSH_CLIENT_ON_PATH=1
            OPENSSH_CLIENT_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as openssh-client is present via our package'
            OPENSSH_CLIENT_ON_PATH=1
            OPENSSH_CLIENT_PRESENT=1
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

        It 'does nothing because openssh-client needs no configuration'
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

        It 'does nothing because openssh-client has no configuration to restore'
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

        It 'purges openssh-client and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the openssh-client package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y openssh-client'
        End

        It 'purges openssh-client even when this tool never recorded installing it'
            # no ownership state seeded: uninstall must not depend on it
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the openssh-client package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y openssh-client'
        End

    End

    # ==========================================================================
    # openssh::client::main
    # ==========================================================================
    Describe 'openssh::client::main'

        It 'hands the action to the runner, which prints the status word'
            OPENSSH_CLIENT_ON_PATH=0
            When call openssh::client::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
