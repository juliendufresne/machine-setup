# Specs for the system upgrade on Ubuntu 26.04. TEST_FLAG keeps the functions
# non-readonly so the spec can source the file, and the file's own Execute guard
# keeps it from running when Included. sudo and apt-get are stubbed so no package
# operation ever touches the real host.
Describe 'libexec/ubuntu_26.04/system-upgrade'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/system-upgrade

    # Isolated host and a log to spy on apt-get. The sudo session is assumed warm,
    # so warmup is a no-op and sudo just runs the wrapped command.
    setup() {
        helper::isolate
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
    }
    BeforeEach 'setup'

    sudo::warmup() { return 0; }
    sudo()    { "$@"; }                                # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }     # record the apt-get call

    # ==========================================================================
    # system_upgrade::run
    # ==========================================================================
    Describe 'system_upgrade::run'

        It 'updates the package lists then upgrades the packages and reports each step'
            When call system_upgrade::run
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Upgrading the installed packages'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
upgrade -y'
        End

        It 'warms the sudo session before touching apt-get'
            sudo::warmup() { printf 'warmed\n'; }

            When call system_upgrade::run
            The status should be success
            The line 1 of stdout should equal 'warmed'
            The stderr should be blank
        End

        It 'stops at the failing step and propagates its status'
            apt-get() { return 7; }

            When call system_upgrade::run
            The status should equal 7
            The stdout should be blank
            The stderr should equal '  ✗ Updating the package lists'
        End

    End

    # ==========================================================================
    # system_upgrade::main
    # ==========================================================================
    Describe 'system_upgrade::main'

        It 'refreshes the package manager through the run helper'
            When call system_upgrade::main
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Upgrading the installed packages'
            The stderr should be blank
        End

    End

End
