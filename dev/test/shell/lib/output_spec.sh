# Specs for the output helpers. TEST_FLAG keeps the functions non-readonly so the
# spec can source the library without freezing it. The shellspec capture is not a
# terminal, so output::color_enabled is false and every line is asserted in its
# plain, uncoloured form.
Describe 'lib/output.sh'
    TEST_FLAG=true
    Include lib/output.sh

    # ==========================================================================
    # output::color_enabled
    # ==========================================================================
    Describe 'output::color_enabled'

        It 'reports failure when the descriptor is not a terminal'
            When call output::color_enabled 1
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::stage
    # ==========================================================================
    Describe 'output::stage'

        It 'opens the stage as a triangle header after a blank line'
            When call output::stage 'Installing git'
            The status should be success
            The line 1 of stdout should equal ''
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
        End

        It 'colours the header magenta on a terminal'
            output::color_enabled() { return 0; }

            When call output::stage 'Installing git'
            The status should be success
            The stdout should include '1;35m'
            The stdout should include '▶ Installing git'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::log
    # ==========================================================================
    Describe 'output::log'

        It 'writes a double-angle phase heading to stderr'
            When call output::log 'Installing the selected units...'
            The status should be success
            The stdout should be blank
            The stderr should equal '» Installing the selected units...'
        End

        It 'bolds the heading on a terminal'
            output::color_enabled() { return 0; }

            When call output::log 'Installing the selected units...'
            The status should be success
            The stdout should be blank
            The stderr should include '[1m'
            The stderr should include '» Installing the selected units...'
        End

    End

End
