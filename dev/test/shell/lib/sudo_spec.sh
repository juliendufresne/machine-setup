# Specs for sudo session handling. sudo itself is mocked, so no real privilege
# escalation or password prompt is ever attempted.
Describe 'lib/sudo.sh'
    TEST_FLAG=true
    Include lib/sudo.sh

    # A log to record what the mocked sudo was asked to do, started empty so a
    # test can assert sudo was never invoked.
    setup() {
        SUDO_LOG="$SHELLSPEC_TMPBASE/sudo.log"
        : >"$SUDO_LOG"
    }
    BeforeEach 'setup'

    # ==========================================================================
    # sudo::is_needed
    # ==========================================================================
    Describe 'sudo::is_needed'

        It 'is true when a non-interactive sudo fails'
            sudo() { return 1; }

            When call sudo::is_needed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when a non-interactive sudo already succeeds'
            sudo() { return 0; }

            When call sudo::is_needed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # sudo::warmup
    # ==========================================================================
    Describe 'sudo::warmup'

        sudo() { printf '%s\n' "$*" >>"$SUDO_LOG"; }

        It 'primes the session when a prompt is needed'
            sudo::is_needed() { return 0; }

            When call sudo::warmup
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$SUDO_LOG" should equal '-v'
        End

        It 'does nothing when sudo is already warmed up'
            sudo::is_needed() { return 1; }

            When call sudo::warmup
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$SUDO_LOG" should be blank
        End

    End

End
