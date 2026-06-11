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

    # ==========================================================================
    # provisioner::run
    # ==========================================================================
    Describe 'provisioner::run'

        # Every step is stubbed to log so the ordering is asserted without a real fetch.
        output::stage() { printf 'stage: %s\n' "$1" >>"$HOME/log"; }
        provisioner::_stage_inputs() { printf 'staged\n' >>"$HOME/log"; }
        provisioner::request_inputs() { printf 'inputs\n' >>"$HOME/log"; }
        state::commit_prefix() { printf 'commit:%s\n' "$1" >>"$HOME/log"; }
        provisioner::run_installer() { printf 'installer\n' >>"$HOME/log"; }

        It 'stages the inputs, collects the input, commits it, then runs the installer'
            When call provisioner::run
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'stage: Provisioning the workspace\nstaged\ninputs\ncommit:workspace.\ninstaller')"
        End

        It 'stops and propagates when the installer fails'
            provisioner::run_installer() {
                printf 'installer\n' >>"$HOME/log"

                return 7
            }

            When call provisioner::run
            The status should equal 7
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'stage: Provisioning the workspace\nstaged\ninputs\ncommit:workspace.\ninstaller')"
        End

    End

    # ==========================================================================
    # provisioner::contains
    # ==========================================================================
    Describe 'provisioner::contains'

        It 'is true when the needle is among the items'
            When call provisioner::contains beta alpha beta gamma
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the needle is absent'
            When call provisioner::contains delta alpha beta gamma
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when there are no items'
            When call provisioner::contains delta
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::choose
    # ==========================================================================
    Describe 'provisioner::choose'

        menu::select() {
            local entry

            for entry in "$@"
            do
                printf '%s\n' "$entry"
            done
        }

        It 'offers exactly the fixed provisioners, both pre-ticked, in order'
            PROVISIONER_DESCRIPTIONS=([workspace]='ws desc' [dotfiles]='df desc')

            When call provisioner::choose
            The status should be success
            The line 1 of stdout should equal "$(printf '1\tworkspace\tws desc')"
            The line 2 of stdout should equal "$(printf '1\tdotfiles\tdf desc')"
            The stderr should be blank
        End

        It 'labels the menu as a provisioner menu'
            menu::select() { printf '%s\n' "$MENU_PROMPT"; }

            When call provisioner::choose
            The status should be success
            The stdout should include 'provisioners'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::provision
    # ==========================================================================
    Describe 'provisioner::provision'

        # The framework is the whole implementation; the seam loads the named
        # provisioner's record into the PROVISIONER_* globals and drives
        # provisioner::run. Stub it to echo the globals it reads.
        provisioner::run() {
            printf 'name=%s title=%s installer=%s\n' \
                "$PROVISIONER_NAME" "$PROVISIONER_TITLE" "$PROVISIONER_DEFAULT_INSTALLER"
        }

        It 'loads the provisioner record into the globals and drives the framework'
            PROVISIONER_TITLES=([workspace]='Workspace setup')
            PROVISIONER_INSTALLERS=([workspace]='https://example.invalid/install.sh')

            When call provisioner::provision workspace
            The status should be success
            The stdout should equal 'name=workspace title=Workspace setup installer=https://example.invalid/install.sh'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::provision_all
    # ==========================================================================
    Describe 'provisioner::provision_all'

        output::log() { :; }
        provisioner::provision() { printf 'run %s\n' "$1"; }

        It 'runs the chosen provisioners in PROVISIONERS order'
            # Given reversed, the provisioners still run workspace before dotfiles.
            When call provisioner::provision_all dotfiles workspace
            The status should be success
            The line 1 of stdout should equal 'run workspace'
            The line 2 of stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'runs only the chosen provisioners'
            When call provisioner::provision_all dotfiles
            The status should be success
            The stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'continues past a failing provisioner and returns the worst status'
            provisioner::provision() {
                [[ "$1" == workspace ]] && return 4

                printf 'run %s\n' "$1"
            }

            When call provisioner::provision_all workspace dotfiles
            The status should equal 4
            The stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'does nothing when no provisioners are given'
            When call provisioner::provision_all
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

End
