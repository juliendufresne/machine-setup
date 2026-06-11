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

    # ==========================================================================
    # output::success
    # ==========================================================================
    Describe 'output::success'

        It 'writes an indented check line'
            When call output::success 'Installing the git package'
            The status should be success
            The stdout should equal '  ✓ Installing the git package'
            The stderr should be blank
        End

        It 'colours the check line green on a terminal'
            output::color_enabled() { return 0; }

            When call output::success 'Installing the git package'
            The status should be success
            The stdout should include '0;32m'
            The stdout should include '✓ Installing the git package'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::info
    # ==========================================================================
    Describe 'output::info'

        It 'writes an indented bullet line'
            When call output::info 'already installed'
            The status should be success
            The stdout should equal '  • already installed'
            The stderr should be blank
        End

        It 'dims the bullet line on a terminal'
            output::color_enabled() { return 0; }

            When call output::info 'already installed'
            The status should be success
            The stdout should include '[2m'
            The stdout should include '• already installed'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::warn
    # ==========================================================================
    Describe 'output::warn'

        It 'writes an indented warning line to stderr'
            When call output::warn 'git is still present; it may be installed by other means'
            The status should be success
            The stdout should be blank
            The stderr should equal '  ! git is still present; it may be installed by other means'
        End

        It 'colours the warning line yellow on a terminal'
            output::color_enabled() { return 0; }

            When call output::warn 'git is still present'
            The status should be success
            The stdout should be blank
            The stderr should include '0;33m'
            The stderr should include '! git is still present'
        End

    End

    # ==========================================================================
    # output::error
    # ==========================================================================
    Describe 'output::error'

        It 'writes an indented cross line to stderr'
            When call output::error 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should equal '  ✗ Installing the git package'
        End

        It 'colours the cross line red on a terminal'
            output::color_enabled() { return 0; }

            When call output::error 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should include '0;31m'
            The stderr should include '✗ Installing the git package'
        End

    End

    # ==========================================================================
    # output::fatal
    # ==========================================================================
    Describe 'output::fatal'

        It 'writes a flush-left error line to stderr'
            When call output::fatal 'requirements not met'
            The status should be success
            The stdout should be blank
            The stderr should equal 'error: requirements not met'
        End

        It 'colours the error line red on a terminal'
            output::color_enabled() { return 0; }

            When call output::fatal 'requirements not met'
            The status should be success
            The stdout should be blank
            The stderr should include '0;31m'
            The stderr should include 'error: requirements not met'
        End

    End

    # ==========================================================================
    # output::_spinner
    # ==========================================================================
    Describe 'output::_spinner'

        It 'draws a cyan frame next to the message each tick'
            sleep() { exit 0; }

            When run output::_spinner 'Installing the git package'
            The status should be success
            The stdout should include '0;36m'
            The stdout should include 'Installing the git package'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::_start
    # ==========================================================================
    Describe 'output::_start'

        It 'does nothing off a terminal'
            output::color_enabled() { return 1; }

            When call output::_start 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'prints the first frame and launches the spinner on a terminal'
            output::color_enabled() { return 0; }
            output::_spinner() { :; }

            When call output::_start 'Installing the git package'
            The status should be success
            The stdout should include 'Installing the git package'
            The stderr should be blank
            The variable _OUTPUT_SPINNER_PID should not equal 0
        End

    End

    # ==========================================================================
    # output::_stop
    # ==========================================================================
    Describe 'output::_stop'

        It 'does nothing off a terminal'
            output::color_enabled() { return 1; }

            When call output::_stop 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'kills the spinner and erases the pending line on a terminal'
            output::color_enabled() { return 0; }
            kill() { :; }
            wait() { :; }

            _OUTPUT_SPINNER_PID=12345
            When call output::_stop 'Installing the git package'
            The status should be success
            The stdout should not be blank
            The stderr should be blank
            The variable _OUTPUT_SPINNER_PID should equal 0
        End

    End

    # ==========================================================================
    # output::run
    # ==========================================================================
    Describe 'output::run'

        It 'shows a check with the message and hides the command output on success'
            noisy() { printf 'chatty stdout\n'; printf 'chatty stderr\n' >&2; }

            When call output::run 'Installing the git package' noisy
            The status should be success
            The stdout should equal '  ✓ Installing the git package'
            The stderr should be blank
        End

        It 'shows a cross with the message and the captured output and propagates the status on failure'
            noisy() { printf 'boom on stdout\n'; printf 'boom on stderr\n' >&2; return 3; }

            When call output::run 'Installing the git package' noisy
            The status should equal 3
            The stdout should be blank
            The line 1 of stderr should equal '  ✗ Installing the git package'
            The stderr should include 'boom on stdout'
            The stderr should include 'boom on stderr'
        End

        It 'shows no trace when a failing command produces no output'
            silent() { return 4; }

            When call output::run 'Configuring git' silent
            The status should equal 4
            The stdout should be blank
            The stderr should equal '  ✗ Configuring git'
        End

    End

End
