# Specs for the provisioner framework. The PROVISIONER_* globals stand in for the
# record the orchestrator loads before driving a provisioner; TEST_FLAG keeps the
# functions non-readonly so the spec can source the library and mock its parts.
# helper::isolate redirects the state store and HOME. wget, curl, and sh are stubbed
# where a test drives a fetch, so no network or real installer is touched.
Describe 'lib/provisioner.sh'
    TEST_FLAG=true
    Include lib/provisioner.sh

    PROVISIONER_NAME='workspace'
    PROVISIONER_TITLE='Workspace setup'
    PROVISIONER_DEFAULT_INSTALLER='https://example.invalid/install.sh'

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # provisioner::installer
    # ==========================================================================
    Describe 'provisioner::installer'

        It 'is the saved installer when one was given'
            helper::seed_input workspace.installer 'https://example.com/custom.sh'
            When call provisioner::installer
            The status should be success
            The stdout should equal 'https://example.com/custom.sh'
            The stderr should be blank
        End

        It 'falls back to the default installer when none was given'
            When call provisioner::installer
            The status should be success
            The stdout should equal "$PROVISIONER_DEFAULT_INSTALLER"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::is_url
    # ==========================================================================
    Describe 'provisioner::is_url'

        It 'is true for an https URL'
            When call provisioner::is_url 'https://example.com/install.sh'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is true for a file URL'
            When call provisioner::is_url 'file:///tmp/install.sh'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false for an absolute path'
            When call provisioner::is_url '/home/me/install.sh'
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false for a relative path'
            When call provisioner::is_url 'bin/install'
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::request_inputs
    # ==========================================================================
    Describe 'provisioner::request_inputs'

        state::ask() { printf '%s\n%s\n' "$1" "$2" >>"$HOME/log"; }

        It 'asks for the installer'
            When call provisioner::request_inputs
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'workspace.installer'
        End

        It 'shows the default installer in the prompt'
            When call provisioner::request_inputs
            The status should be success
            The contents of file "$HOME/log" should include "$PROVISIONER_DEFAULT_INSTALLER"
        End

    End

    # ==========================================================================
    # provisioner::run_remote
    # ==========================================================================
    Describe 'provisioner::run_remote'

        # The fetcher writes a marker (carrying the URL) into the destination file
        # rather than piping; sh echoes that file back, so the test sees what was
        # fetched and run, and confirms the installer keeps the terminal on stdin.
        sh() { cat "$1"; }

        It 'fetches with wget when it is available'
            command() { [[ "$2" == wget || "$2" == curl ]]; }
            wget() { printf 'from wget %s\n' "$3" >"$2"; }
            curl() { printf 'from curl %s\n' "$2" >"$4"; }

            When call provisioner::run_remote 'https://example.com/i.sh'
            The status should be success
            The stdout should equal 'from wget https://example.com/i.sh'
            The stderr should be blank
        End

        It 'falls back to curl when wget is absent'
            command() { [[ "$2" == curl ]]; }
            curl() { printf 'from curl %s\n' "$2" >"$4"; }

            When call provisioner::run_remote 'https://example.com/i.sh'
            The status should be success
            The stdout should equal 'from curl https://example.com/i.sh'
            The stderr should be blank
        End

        It 'errors when neither wget nor curl is available'
            command() { return 1; }

            When run provisioner::run_remote 'https://example.com/i.sh'
            The status should equal 1
            The stdout should be blank
            The stderr should include 'neither wget nor curl'
        End

    End

    # ==========================================================================
    # provisioner::run_installer
    # ==========================================================================
    Describe 'provisioner::run_installer'

        It 'fetches and runs a remote installer through run_remote'
            helper::seed_input workspace.installer 'https://example.com/i.sh'
            provisioner::run_remote() { printf 'remote %s\n' "$1"; }

            When call provisioner::run_installer
            The status should be success
            The stdout should equal 'remote https://example.com/i.sh'
            The stderr should be blank
        End

        It 'runs a local executable installer directly, forwarding its output'
            printf '#!/bin/sh\nprintf "local install ran\\n"\n' >"$HOME/installer"
            chmod +x "$HOME/installer"
            helper::seed_input workspace.installer "$HOME/installer"

            When run provisioner::run_installer
            The status should be success
            The stdout should equal 'local install ran'
            The stderr should be blank
        End

        It 'errors when a local installer path is missing or not executable'
            helper::seed_input workspace.installer "$HOME/missing"

            When run provisioner::run_installer
            The status should equal 1
            The stdout should be blank
            The stderr should include 'not an URL and is not an executable file'
        End

    End

    # ==========================================================================
    # provisioner::_stage_inputs
    # ==========================================================================
    Describe 'provisioner::_stage_inputs'

        It 'does nothing outside an active session'
            session::active() { return 1; }

            When call provisioner::_stage_inputs
            The status should be success
            The variable MACHINE_SETUP_INPUTS_WORKING should be undefined
        End

        It 'points the inputs overlay at the session working area and creates it'
            session::active() { return 0; }
            session::dir() { printf '%s' "$XDG_STATE_HOME/session"; }

            When call provisioner::_stage_inputs
            The status should be success
            The variable MACHINE_SETUP_INPUTS_WORKING should equal "$XDG_STATE_HOME/session/$(state::_key workspace)/inputs"
            The path "$MACHINE_SETUP_INPUTS_WORKING" should be directory
        End

    End

End
