# Specs for the checkbox menu. TEST_FLAG keeps menu::read_key and menu::select
# non-readonly so the spec can Include the file and exercise them. The draw loop
# is driven through MENU_INPUT/MENU_OUTPUT pointed at temp files, so no terminal
# is needed and stdout carries only the resulting selection.
Describe 'lib/menu.sh'
    TEST_FLAG=true
    Include lib/menu.sh

    # ==========================================================================
    # menu::read_key
    # ==========================================================================
    Describe 'menu::read_key'

        wrapper::menu::read_key() {
            local -i exit_status
            local fd
            local tmp

            tmp="$(mktemp -t shellspec-menu-XXXXXXXXXX)"
            printf '%b' "$1" >"$tmp"

            exec {fd}<"$tmp"
            menu::read_key "$fd"
            exit_status=$?
            exec {fd}<&-

            rm -f "$tmp"

            return "$exit_status"
        }

        It 'maps the up-arrow escape sequence to up'
            When call wrapper::menu::read_key '\033[A'
            The status should be success
            The stdout should equal 'up'
            The stderr should be blank
        End

        It 'maps the down-arrow escape sequence to down'
            When call wrapper::menu::read_key '\033[B'
            The status should be success
            The stdout should equal 'down'
            The stderr should be blank
        End

        It 'maps k to up'
            When call wrapper::menu::read_key 'k'
            The status should be success
            The stdout should equal 'up'
            The stderr should be blank
        End

        It 'maps j to down'
            When call wrapper::menu::read_key 'j'
            The status should be success
            The stdout should equal 'down'
            The stderr should be blank
        End

        It 'maps the space bar to toggle'
            When call wrapper::menu::read_key ' '
            The status should be success
            The stdout should equal 'toggle'
            The stderr should be blank
        End

        It 'maps Enter to confirm'
            When call wrapper::menu::read_key '\n'
            The status should be success
            The stdout should equal 'confirm'
            The stderr should be blank
        End

        It 'maps q to cancel'
            When call wrapper::menu::read_key 'q'
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
        End

        It 'maps a bare Escape to cancel'
            When call wrapper::menu::read_key '\033'
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
        End

        It 'ignores an unrecognised key'
            When call wrapper::menu::read_key 'x'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails at end of input so the caller can treat it as a confirm'
            When call wrapper::menu::read_key ''
            The status should equal 1
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # menu::select
    # ==========================================================================
    Describe 'menu::select'

        wrapper::menu::select() {
            local -i exit_status
            local keys
            local tmp_in
            local tmp_out

            keys="$1"
            shift

            tmp_in="$(mktemp -t shellspec-menu-in-XXXXXXXXXX)"
            tmp_out="$(mktemp -t shellspec-menu-out-XXXXXXXXXX)"
            printf '%b' "$keys" >"$tmp_in"

            MENU_INPUT="$tmp_in" MENU_OUTPUT="$tmp_out" menu::select "$@"
            exit_status=$?

            rm -f "$tmp_in" "$tmp_out"

            return "$exit_status"
        }

        It 'emits the pre-selected entries when no terminal is available'
            MENU_INPUT='/nonexistent'
            MENU_OUTPUT='/dev/null'
            When call menu::select "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')" "$(printf '1\tfish\tShell')"
            The status should be success
            The stdout should equal "$(printf 'git\nfish')"
            The stderr should be blank
        End

        It 'emits nothing for an empty entry list'
            MENU_INPUT='/nonexistent'
            MENU_OUTPUT='/dev/null'
            When call menu::select
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'confirms the defaults when Enter is pressed straight away'
            When call wrapper::menu::select '\n' "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'toggles the highlighted entry off with the space bar'
            When call wrapper::menu::select ' \n' "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')"
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'navigates down and toggles a deselected entry on'
            When call wrapper::menu::select '\033[B \n' "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')"
            The status should be success
            The stdout should equal "$(printf 'git\ndiscord')"
            The stderr should be blank
        End

        It 'confirms the current selection at end of input'
            When call wrapper::menu::select ' ' "$(printf '0\tgit\tVCS')" "$(printf '1\tdiscord\tChat')"
            The status should be success
            The stdout should equal "$(printf 'git\ndiscord')"
            The stderr should be blank
        End

        It 'redraws unchanged on an unrecognised key'
            When call wrapper::menu::select 'x\n' "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'draws the sticky header and help line into the screen output'
            SCREEN_OUTPUT="$SHELLSPEC_TMPBASE/menu-screen"
            : >"$SCREEN_OUTPUT"
            screen::open 'Set up this machine'

            SCREEN_HELP='Tick the units to set up.'
            When call wrapper::menu::select '\n' "$(printf '1\tgit\tVCS')" "$(printf '0\tdiscord\tChat')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
            The contents of file "$SCREEN_OUTPUT" should include 'Set up this machine'
            The contents of file "$SCREEN_OUTPUT" should include 'Tick the units to set up.'
        End

    End

End
