# Specs for the execution session. helper::isolate redirects XDG_STATE_HOME at a
# fresh temp directory and clears the session markers, so the working area is
# created and removed entirely inside the shellspec temp base.
Describe 'lib/session.sh'
    TEST_FLAG=true
    Include lib/session.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # session::dir
    # ==========================================================================
    Describe 'session::dir'

        It 'returns the execution-in-progress directory under the store root'
            When call session::dir
            The status should be success
            The stdout should equal "$XDG_STATE_HOME/machine-setup/execution-in-progress"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # session::active
    # ==========================================================================
    Describe 'session::active'

        It 'is true when the session marker is set'
            MACHINE_SETUP_SESSION=1
            When call session::active
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when no session is in progress'
            When call session::active
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # session::begin
    # ==========================================================================
    Describe 'session::begin'

        It 'begins a fresh session, writing the lock and marking ownership'
            When call session::begin
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The file "$XDG_STATE_HOME/machine-setup/execution-in-progress/machine-setup.lock" should be exist
            The variable MACHINE_SETUP_SESSION should equal 1
            The variable SESSION_OWNED should equal 1
        End

        It 'is a no-op when a session is already inherited'
            MACHINE_SETUP_SESSION=1
            When call session::begin
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The variable SESSION_OWNED should be undefined
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress" should not be exist
        End

        It 'warns and continues over a leftover session when there is no terminal'
            output::warn() { printf 'warn: %s\n' "$*" >&2; }
            mkdir -p "$XDG_STATE_HOME/machine-setup/execution-in-progress"
            : >"$XDG_STATE_HOME/machine-setup/execution-in-progress/stale"

            PROMPT_INPUT=/nonexistent/in
            PROMPT_OUTPUT=/nonexistent/out
            When call session::begin
            The status should be success
            The stdout should be blank
            The stderr should equal 'warn: discarding an unfinished previous run'
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress/stale" should not be exist
            The file "$XDG_STATE_HOME/machine-setup/execution-in-progress/machine-setup.lock" should be exist
        End

        It 'discards the leftover session and continues when the user confirms'
            mkdir -p "$XDG_STATE_HOME/machine-setup/execution-in-progress"
            : >"$XDG_STATE_HOME/machine-setup/execution-in-progress/stale"
            PROMPT_INPUT="$XDG_STATE_HOME/in"
            PROMPT_OUTPUT="$XDG_STATE_HOME/out"
            printf 'y\n' >"$PROMPT_INPUT"

            When call session::begin
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress/stale" should not be exist
            The variable MACHINE_SETUP_SESSION should equal 1
        End

        It 'aborts the run when the user declines to discard a leftover session'
            mkdir -p "$XDG_STATE_HOME/machine-setup/execution-in-progress"
            : >"$XDG_STATE_HOME/machine-setup/execution-in-progress/stale"
            PROMPT_INPUT="$XDG_STATE_HOME/in"
            PROMPT_OUTPUT="$XDG_STATE_HOME/out"
            printf 'n\n' >"$PROMPT_INPUT"

            When call session::begin
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress/stale" should be exist
            The variable SESSION_OWNED should be undefined
        End

    End

    # ==========================================================================
    # session::end
    # ==========================================================================
    Describe 'session::end'

        It 'removes the working area when this process owns the session'
            mkdir -p "$XDG_STATE_HOME/machine-setup/execution-in-progress/machine-setup"
            MACHINE_SETUP_SESSION=1
            SESSION_OWNED=1

            When call session::end
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress" should not be exist
            The variable MACHINE_SETUP_SESSION should be undefined
            The variable SESSION_OWNED should be undefined
        End

        It 'leaves the working area in place for an inherited child that does not own it'
            mkdir -p "$XDG_STATE_HOME/machine-setup/execution-in-progress/machine-setup"
            MACHINE_SETUP_SESSION=1

            When call session::end
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress" should be exist
        End

    End

End
