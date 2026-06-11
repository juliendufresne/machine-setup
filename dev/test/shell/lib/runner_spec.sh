# Specs for the step runner. Including the runner sources its sibling libraries,
# so output::fatal is real while the unit::* contract and the state writes are mocked.
# A run log records the order in which the contract steps fire.
Describe 'lib/runner.sh'
    TEST_FLAG=true
    Include lib/runner.sh

    setup() {
        helper::isolate
        RUN_LOG="$SHELLSPEC_TMPBASE/run.log"
        : >"$RUN_LOG"
    }
    BeforeEach 'setup'

    # ==========================================================================
    # runner::unit_name
    # ==========================================================================
    Describe 'runner::unit_name'

        It 'uses MACHINE_SETUP_UNIT_NAME when it is set'
            MACHINE_SETUP_UNIT_NAME=git
            When call runner::unit_name
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'derives the name from the script filename for a per-OS software file'
            MACHINE_SETUP_UNIT_NAME=''
            realpath() { printf '%s' /repo/libexec/ubuntu_26.04/software/git.sh; }

            When call runner::unit_name
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'derives the name from the script basename for a flat unit directly in libexec'
            MACHINE_SETUP_UNIT_NAME=''
            realpath() { printf '%s' /repo/libexec/workspace; }

            When call runner::unit_name
            The status should be success
            The stdout should equal 'workspace'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # runner::id
    # ==========================================================================
    Describe 'runner::id'

        It 'is the unit name when the unit is not instanceable'
            MACHINE_SETUP_UNIT_NAME=git
            When call runner::id
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'is name@instance when the unit declares an instance'
            MACHINE_SETUP_UNIT_NAME=workspace
            unit::instance() { printf 'personal'; }

            When call runner::id
            The status should be success
            The stdout should equal 'workspace@personal'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # runner::status
    # ==========================================================================
    Describe 'runner::status'

        It 'reports unavailable when the unit is not available'
            unit::is_available() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when the unit is available but not installed'
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when the unit is present but not by our mechanism'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports installed when the unit is managed but not configured'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 0; }
            unit::is_configured() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'installed'
            The stderr should be blank
        End

        It 'reports configured when every check passes'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 0; }
            unit::is_configured() { return 0; }

            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

End
