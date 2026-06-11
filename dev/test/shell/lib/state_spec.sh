# Specs for the persistent state store. helper::isolate redirects XDG_STATE_HOME
# and HOME at fresh temp directories, so every write stays inside the shellspec
# temp base and the real store is never touched.
Describe 'lib/state.sh'
    TEST_FLAG=true
    Include lib/state.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # state::_root
    # ==========================================================================
    Describe 'state::_root'

        It 'returns the machine-setup directory under XDG_STATE_HOME'
            XDG_STATE_HOME=/xdg
            When call state::_root
            The status should be success
            The stdout should equal '/xdg/machine-setup'
            The stderr should be blank
        End

        It 'falls back to ~/.local/state when XDG_STATE_HOME is unset'
            XDG_STATE_HOME=''
            HOME=/home/ada
            When call state::_root
            The status should be success
            The stdout should equal '/home/ada/.local/state/machine-setup'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_dir
    # ==========================================================================
    Describe 'state::_dir'

        It 'creates the sub-directory and prints its path'
            When call state::_dir inputs
            The status should be success
            The stdout should equal "$XDG_STATE_HOME/machine-setup/inputs"
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/inputs" should be directory
        End

    End

    # ==========================================================================
    # state::_key
    # ==========================================================================
    Describe 'state::_key'

        It 'replaces characters outside the safe set with underscores'
            When call state::_key 'workspaces/api@/srv/api'
            The status should be success
            The stdout should equal 'workspaces_api@_srv_api'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_envname
    # ==========================================================================
    Describe 'state::_envname'

        It 'upper-cases the name and replaces non-alphanumerics with underscores'
            When call state::_envname git.name
            The status should be success
            The stdout should equal 'GIT_NAME'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_put
    # ==========================================================================
    Describe 'state::_put'

        It 'writes the value without a trailing newline and creates the parent directory'
            file="$XDG_STATE_HOME/sub/dir/value"
            When call state::_put "$file" 'Ada'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$file" should equal 'Ada'
        End

    End

    # ==========================================================================
    # state::ask
    # ==========================================================================
    Describe 'state::ask'

        It 'reuses a saved value without prompting'
            helper::seed_input git.name 'Ada'

            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/git.name" should equal 'Ada'
        End

        It 'takes the value from the environment when nothing is saved'
            GIT_NAME=Ada
            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/git.name" should equal 'Ada'
        End

        It 'prompts for the value when there is no saved or environment value'
            GIT_NAME=''
            Data 'Ada'
            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/git.name" should equal 'Ada'
        End

        It 'draws the sticky header and help line into the screen output'
            SCREEN_OUTPUT="$SHELLSPEC_TMPBASE/state-screen"
            : >"$SCREEN_OUTPUT"
            screen::open 'Dotfiles setup'

            GIT_NAME=''
            Data 'Ada'
            SCREEN_HELP='The git author name.'
            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/git.name" should equal 'Ada'
            The contents of file "$SCREEN_OUTPUT" should include 'Dotfiles setup'
            The contents of file "$SCREEN_OUTPUT" should include 'The git author name.'
        End

        It 'writes a freshly resolved value to the working overlay during a session'
            helper::overlay git

            GIT_NAME=Ada
            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$MACHINE_SETUP_INPUTS_WORKING/git.name" should equal 'Ada'
            The path "$XDG_STATE_HOME/machine-setup/inputs/git.name" should not be exist
        End

        It 'reuses a committed value without prompting during a session'
            helper::overlay git
            helper::seed_input git.name 'Ada'

            GIT_NAME=Grace
            When call state::ask git.name 'Your git name'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$MACHINE_SETUP_INPUTS_WORKING/git.name" should not be exist
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/git.name" should equal 'Ada'
        End

    End

    # ==========================================================================
    # state::set
    # ==========================================================================
    Describe 'state::set'

        It 'writes the input value and round-trips through state::input with no trailing newline'
            state::set workspace.personal.path /srv/personal

            When call state::input workspace.personal.path
            The status should be success
            The stdout should equal '/srv/personal'
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should equal '/srv/personal'
        End

        It 'overwrites an existing value unconditionally'
            state::set workspace.personal.path /old

            When call state::set workspace.personal.path /new
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should equal '/new'
        End

        It 'writes to the working overlay during a session, leaving the committed value untouched'
            helper::overlay workspace
            helper::seed_input workspace.personal.path /old

            When call state::set workspace.personal.path /new
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$MACHINE_SETUP_INPUTS_WORKING/workspace.personal.path" should equal '/new'
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should equal '/old'
        End

    End

    # ==========================================================================
    # state::input
    # ==========================================================================
    Describe 'state::input'

        output::fatal() { printf 'error: %s\n' "$*" >&2; }

        It 'prints a saved input value'
            helper::seed_input git.name 'Ada'

            When call state::input git.name
            The status should be success
            The stdout should equal 'Ada'
            The stderr should be blank
        End

        It 'fails and reports an error when no value is saved'
            When call state::input git.name
            The status should equal 1
            The stdout should be blank
            The stderr should equal 'error: no saved input: git.name'
        End

        It 'prefers the working overlay over the committed value during a session'
            helper::overlay workspace
            helper::seed_input workspace.personal.path /committed
            helper::seed_working workspace.personal.path /working

            When call state::input workspace.personal.path
            The status should be success
            The stdout should equal '/working'
            The stderr should be blank
        End

        It 'falls back to the committed value when the overlay has none'
            helper::overlay workspace
            helper::seed_input workspace.personal.path /committed

            When call state::input workspace.personal.path
            The status should be success
            The stdout should equal '/committed'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::unset
    # ==========================================================================
    Describe 'state::unset'

        It 'removes a saved input'
            helper::seed_input workspace.list Personal

            When call state::unset workspace.list
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should not be exist
        End

        It 'is a no-op when the input was never saved'
            When call state::unset workspace.list
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'removes the input from both the overlay and the committed store during a session'
            helper::overlay workspace
            helper::seed_input workspace.list Personal
            helper::seed_working workspace.list Personal

            When call state::unset workspace.list
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$MACHINE_SETUP_INPUTS_WORKING/workspace.list" should not be exist
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should not be exist
        End

    End

    # ==========================================================================
    # state::unset_prefix
    # ==========================================================================
    Describe 'state::unset_prefix'

        It 'removes every input whose name begins with the prefix'
            helper::seed_input workspace.personal.path /srv/personal
            helper::seed_input workspace.personal.user.email ada@example.com
            helper::seed_input workspace.acme.path /srv/acme

            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should not be exist
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.user.email" should not be exist
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.acme.path" should be exist
        End

        It 'is a no-op when no input matches the prefix'
            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'also clears matching inputs from the working overlay'
            helper::overlay workspace
            helper::seed_working workspace.personal.path /srv/personal
            helper::seed_working workspace.acme.path /srv/acme

            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$MACHINE_SETUP_INPUTS_WORKING/workspace.personal.path" should not be exist
            The path "$MACHINE_SETUP_INPUTS_WORKING/workspace.acme.path" should be exist
        End

    End

    # ==========================================================================
    # state::commit
    # ==========================================================================
    Describe 'state::commit'

        It 'moves a working input down to the committed store'
            helper::overlay workspace
            helper::seed_working workspace.personal.path /srv/personal

            When call state::commit workspace.personal.path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$MACHINE_SETUP_INPUTS_WORKING/workspace.personal.path" should not be exist
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should equal '/srv/personal'
        End

        It 'skips an input with no working copy'
            helper::overlay workspace

            When call state::commit workspace.personal.path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should not be exist
        End

        It 'is a no-op when no overlay is active'
            When call state::commit workspace.personal.path
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::commit_prefix
    # ==========================================================================
    Describe 'state::commit_prefix'

        It 'moves every working input matching the prefix down to the committed store'
            helper::overlay workspace
            helper::seed_working workspace.personal.path /srv/personal
            helper::seed_working workspace.personal.user.email ada@example.com
            helper::seed_working workspace.acme.path /srv/acme

            When call state::commit_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.path" should equal '/srv/personal'
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.personal.user.email" should equal 'ada@example.com'
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.acme.path" should not be exist
            The path "$MACHINE_SETUP_INPUTS_WORKING/workspace.acme.path" should be exist
        End

    End

    # ==========================================================================
    # state::commit_line_append
    # ==========================================================================
    Describe 'state::commit_line_append'

        It 'creates the committed list with the entry'
            When call state::commit_line_append workspace.list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should equal 'Personal'
        End

        It 'appends a second entry on a newline without a trailing newline'
            state::commit_line_append workspace.list Personal

            When call state::commit_line_append workspace.list Acme
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should equal "$(printf 'Personal\nAcme')"
        End

        It 'does not duplicate an entry already present'
            state::commit_line_append workspace.list Personal

            When call state::commit_line_append workspace.list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should equal 'Personal'
        End

    End

    # ==========================================================================
    # state::commit_line_remove
    # ==========================================================================
    Describe 'state::commit_line_remove'

        It 'removes the entry and keeps the rest in order'
            state::commit_line_append workspace.list Personal
            state::commit_line_append workspace.list Acme
            state::commit_line_append workspace.list Work

            When call state::commit_line_remove workspace.list Acme
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should equal "$(printf 'Personal\nWork')"
        End

        It 'removes the list file when the last entry is removed'
            state::commit_line_append workspace.list Personal

            When call state::commit_line_remove workspace.list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/inputs/workspace.list" should not be exist
        End

        It 'is a no-op when the list file is missing'
            When call state::commit_line_remove workspace.list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

End
