# Specs for the provisioner executable. TEST_FLAG keeps the functions non-readonly so
# the spec can source the script and mock its parts (and the Execute guard keeps
# provisioner::main from running on Include). helper::isolate redirects the state store
# and HOME. wget, curl, and sh are stubbed where a test drives a fetch, so no network
# or real installer is touched.
Describe 'libexec/provisioner.sh'
    TEST_FLAG=true
    Include libexec/provisioner.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # provisioner::confirm
    # ==========================================================================
    Describe 'provisioner::confirm'

        It 'confirms and shows the question when the user answers yes'
            PROMPT_INPUT="$HOME/in"
            PROMPT_OUTPUT="$HOME/out"
            printf 'y\n' >"$PROMPT_INPUT"

            When call provisioner::confirm workspace
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/out" should include 'Do you want to create workspace(s)?'
        End

        It 'defaults to yes on an empty answer'
            PROMPT_INPUT="$HOME/in"
            PROMPT_OUTPUT="$HOME/out"
            printf '\n' >"$PROMPT_INPUT"

            When call provisioner::confirm workspace
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'declines when the user answers no'
            PROMPT_INPUT="$HOME/in"
            PROMPT_OUTPUT="$HOME/out"
            printf 'n\n' >"$PROMPT_INPUT"

            When call provisioner::confirm workspace
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
        End

        It 'confirms with no terminal so a piped run still provisions'
            PROMPT_INPUT=/nonexistent/in
            PROMPT_OUTPUT=/nonexistent/out
            When call provisioner::confirm workspace
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # provisioner::run
    # ==========================================================================
    Describe 'provisioner::run'

        # The named provisioner's fixed installer is fetched and run; the fetcher
        # writes a marker (carrying the URL) into the destination file rather than
        # piping, and sh echoes that file back, so the test sees what was fetched and
        # run, and confirms the installer keeps the terminal on stdin.
        PROVISIONER_INSTALLERS=([workspace]='https://example.com/i.sh')
        sh() { cat "$1"; }

        It 'fetches the installer with wget when it is available'
            command() { [[ "$2" == wget || "$2" == curl ]]; }
            wget() { printf 'from wget %s\n' "$3" >"$2"; }
            curl() { printf 'from curl %s\n' "$2" >"$4"; }

            When call provisioner::run workspace
            The status should be success
            The stdout should equal 'from wget https://example.com/i.sh'
            The stderr should be blank
        End

        It 'falls back to curl when wget is absent'
            command() { [[ "$2" == curl ]]; }
            curl() { printf 'from curl %s\n' "$2" >"$4"; }

            When call provisioner::run workspace
            The status should be success
            The stdout should equal 'from curl https://example.com/i.sh'
            The stderr should be blank
        End

        It 'errors when neither wget nor curl is available'
            command() { return 1; }

            When run provisioner::run workspace
            The status should equal 1
            The stdout should be blank
            The stderr should include 'neither wget nor curl'
        End

    End

    # ==========================================================================
    # provisioner::main
    # ==========================================================================
    Describe 'provisioner::main'

        output::log() { :; }
        provisioner::confirm() { :; }
        provisioner::run() { printf 'run %s\n' "$1"; }

        It 'runs each confirmed provisioner in PROVISIONERS order'
            When call provisioner::main
            The status should be success
            The line 1 of stdout should equal 'run workspace'
            The line 2 of stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'interleaves the confirm and the run of each provisioner'
            provisioner::confirm() { printf 'confirm %s\n' "$1"; }

            When call provisioner::main
            The status should be success
            The line 1 of stdout should equal 'confirm workspace'
            The line 2 of stdout should equal 'run workspace'
            The line 3 of stdout should equal 'confirm dotfiles'
            The line 4 of stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'skips a provisioner the user declines'
            provisioner::confirm() { [[ "$1" != workspace ]]; }

            When call provisioner::main
            The status should be success
            The stdout should equal 'run dotfiles'
            The stderr should be blank
        End

        It 'provisions nothing when every provisioner is declined'
            provisioner::confirm() { return 1; }

            When call provisioner::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'continues past a failing provisioner and returns the worst status'
            provisioner::run() {
                [[ "$1" == workspace ]] && return 4

                printf 'run %s\n' "$1"
            }

            When call provisioner::main
            The status should equal 4
            The stdout should equal 'run dotfiles'
            The stderr should be blank
        End

    End

End
