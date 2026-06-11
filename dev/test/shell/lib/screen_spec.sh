# Specs for the sticky-header screen. TEST_FLAG keeps the functions non-readonly so
# the spec can Include the file and exercise them. SCREEN_OUTPUT is pointed at a
# temp file under the shellspec temp base, standing in for the terminal, so the
# header and region draws are captured and asserted without a real tty. The
# open-screen state is reset before each example so one does not leak into another.
Describe 'lib/screen.sh'
    TEST_FLAG=true
    Include lib/screen.sh

    helper::screen_out() {
        SCREEN_OUTPUT="$SHELLSPEC_TMPBASE/screen-out"
        : >"$SCREEN_OUTPUT"
        SCREEN_ACTIVE=''
        SCREEN_HEADER=''
    }

    BeforeEach 'helper::screen_out'

    # ==========================================================================
    # screen::open
    # ==========================================================================
    Describe 'screen::open'

        It 'marks the screen active and draws the title and intro into the output'
            When call screen::open 'Workspace setup' 'Define your workspaces.'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The variable SCREEN_ACTIVE should equal 1
            The contents of file "$SCREEN_OUTPUT" should include 'Workspace setup'
            The contents of file "$SCREEN_OUTPUT" should include 'Define your workspaces.'
        End

        It 'is a no-op and stays inactive when the output cannot be opened'
            SCREEN_OUTPUT="$SHELLSPEC_TMPBASE/missing/screen-out"
            When call screen::open 'Workspace setup'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The variable SCREEN_ACTIVE should be blank
        End

    End

    # ==========================================================================
    # screen::close
    # ==========================================================================
    Describe 'screen::close'

        It 'resets the active state'
            screen::open 'Workspace setup'

            When call screen::close
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The variable SCREEN_ACTIVE should be blank
            The variable SCREEN_HEADER should be blank
        End

    End

End
