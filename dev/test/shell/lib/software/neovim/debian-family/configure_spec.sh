# Specs for the neovim unit's configuration contract and the helpers it shares.
# TEST_FLAG keeps the functions non-readonly so the spec can source them. The
# fragment is sourced and relies on output::run, so lib/output.sh is included first.
# The host's alternatives database is modelled per group by two temp files (the
# registered choices and the selected value) under ALT_DIR, and update-alternatives
# is stubbed to read and edit them, so the contract is exercised without touching
# the real vi/vim/editor links; command is stubbed so nvim resolves to a fixed path.
Describe 'lib/software/neovim/debian-family/configure'
    TEST_FLAG=true
    Include lib/output.sh
    Include lib/software/neovim/debian-family/configure

    # Isolated host plus a fake alternatives database. For each managed group ALT_DIR
    # holds a .list of registered choices and a .value of the selected one, seeded to
    # the distro default (vim.basic) so a fresh group looks untouched.
    setup() {
        helper::isolate
        export ALT_DIR="$SHELLSPEC_TMPBASE/alt"
        : "${NVIM_ON_PATH:=1}"
        rm -rf "$ALT_DIR"
        mkdir -p "$ALT_DIR"
        for group in vi vim editor
        do
            printf '/usr/bin/vim.basic\n' >"$ALT_DIR/$group.list"
            printf '/usr/bin/vim.basic\n' >"$ALT_DIR/$group.value"
        done
    }
    BeforeEach 'setup'

    # Stubs for the only host-touching commands. command is shadowed only for
    # `command -v nvim`, which resolves to /usr/bin/nvim when NVIM_ON_PATH is 1;
    # every other call falls through to the real builtin. update-alternatives reads
    # and edits the per-group files above instead of the system database.
    command() {
        if [ "$1" = -v ] && [ "$2" = nvim ]
        then [ "${NVIM_ON_PATH}" = 1 ] && printf '/usr/bin/nvim\n'
        else builtin command "$@"
        fi
    }

    update-alternatives() {
        case "$1" in
            --list)
                cat "$ALT_DIR/$2.list" 2>/dev/null ;;
            --query)                                    # $2 group
                printf 'Name: %s\nValue: %s\n' "$2" "$(cat "$ALT_DIR/$2.value" 2>/dev/null)" ;;
            --install)                                  # $3 group, $4 path
                grep -qxF -- "$4" "$ALT_DIR/$3.list" 2>/dev/null || printf '%s\n' "$4" >>"$ALT_DIR/$3.list" ;;
            --set)                                      # $2 group, $3 path
                printf '%s\n' "$3" >"$ALT_DIR/$2.value" ;;
            --remove)                                   # $2 group, $3 path
                grep -vxF -- "$3" "$ALT_DIR/$2.list" >"$ALT_DIR/$2.list.new" 2>/dev/null ||:
                mv "$ALT_DIR/$2.list.new" "$ALT_DIR/$2.list"
                [ "$(cat "$ALT_DIR/$2.value" 2>/dev/null)" = "$3" ] && head -n 1 "$ALT_DIR/$2.list" >"$ALT_DIR/$2.value" ||: ;;
        esac
    }

    # ==========================================================================
    # neovim::nvim_path
    # ==========================================================================
    Describe 'neovim::nvim_path'

        It 'prints the nvim path when nvim resolves on PATH'
            NVIM_ON_PATH=1
            When call neovim::nvim_path
            The status should be success
            The stdout should equal '/usr/bin/nvim'
            The stderr should be blank
        End

        It 'fails when nvim resolves nowhere'
            NVIM_ON_PATH=0
            When call neovim::nvim_path
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # neovim::alt_value
    # ==========================================================================
    Describe 'neovim::alt_value'

        It 'prints the binary the group alternative currently resolves to'
            When call neovim::alt_value vi
            The status should be success
            The stdout should equal '/usr/bin/vim.basic'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # neovim::alt_registered
    # ==========================================================================
    Describe 'neovim::alt_registered'

        It 'is false when nvim is not a registered choice for the group'
            When call neovim::alt_registered vim
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is true once nvim is registered for the group'
            neovim::register_alt vim

            When call neovim::alt_registered vim
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # neovim::register_alt
    # ==========================================================================
    Describe 'neovim::register_alt'

        It 'registers nvim for the group and selects it as the value'
            When call neovim::register_alt editor
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$ALT_DIR/editor.value" should equal '/usr/bin/nvim'
            The contents of file "$ALT_DIR/editor.list" should include '/usr/bin/nvim'
        End

    End

    # ==========================================================================
    # neovim::deregister_alt
    # ==========================================================================
    Describe 'neovim::deregister_alt'

        It 'drops our entry for the group and reselects the distro default'
            neovim::register_alt vi

            When call neovim::deregister_alt vi
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$ALT_DIR/vi.value" should equal '/usr/bin/vim.basic'
            The contents of file "$ALT_DIR/vi.list" should not include '/usr/bin/nvim'
        End

    End

    # ==========================================================================
    # unit::is_configured
    # ==========================================================================
    Describe 'unit::is_configured'

        It 'is satisfied when every managed command resolves to neovim'
            neovim::register_alt vi
            neovim::register_alt vim
            neovim::register_alt editor

            When call unit::is_configured
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is unsatisfied when no command resolves to neovim'
            When call unit::is_configured
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is unsatisfied when only some commands resolve to neovim'
            neovim::register_alt vi

            When call unit::is_configured
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is unsatisfied when nvim is absent'
            NVIM_ON_PATH=0
            When call unit::is_configured
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::configure
    # ==========================================================================
    Describe 'unit::configure'

        It 'points every command at neovim and reports each one'
            When call unit::configure
            The status should be success
            The line 1 of stdout should equal '  ✓ Pointing the vi command at neovim'
            The line 2 of stdout should equal '  ✓ Pointing the vim command at neovim'
            The line 3 of stdout should equal '  ✓ Pointing the editor command at neovim'
            The stderr should be blank
            The contents of file "$ALT_DIR/editor.value" should equal '/usr/bin/nvim'
        End

        It 'skips a command that already resolves to neovim'
            neovim::register_alt vi

            When call unit::configure
            The status should be success
            The line 1 of stdout should equal '  ✓ Pointing the vim command at neovim'
            The line 2 of stdout should equal '  ✓ Pointing the editor command at neovim'
            The stderr should be blank
        End

        It 'does nothing when every command already resolves to neovim'
            neovim::register_alt vi
            neovim::register_alt vim
            neovim::register_alt editor

            When call unit::configure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'stops at the failing edit and propagates its status'
            neovim::register_alt() { return 5; }

            When call unit::configure
            The status should equal 5
            The stdout should be blank
            The stderr should equal '  ✗ Pointing the vi command at neovim'
        End

    End

    # ==========================================================================
    # unit::unconfigure
    # ==========================================================================
    Describe 'unit::unconfigure'

        It 'removes our entry from every command and reports each one'
            neovim::register_alt vi
            neovim::register_alt vim
            neovim::register_alt editor

            When call unit::unconfigure
            The status should be success
            The line 1 of stdout should equal '  ✓ Restoring the vi command to its default'
            The line 2 of stdout should equal '  ✓ Restoring the vim command to its default'
            The line 3 of stdout should equal '  ✓ Restoring the editor command to its default'
            The stderr should be blank
            The contents of file "$ALT_DIR/vi.value" should equal '/usr/bin/vim.basic'
        End

        It 'does nothing when our entry is registered nowhere'
            When call unit::unconfigure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'stops at the failing edit and propagates its status'
            neovim::register_alt vi
            neovim::register_alt vim
            neovim::register_alt editor
            neovim::deregister_alt() { return 5; }

            When call unit::unconfigure
            The status should equal 5
            The stdout should be blank
            The stderr should equal '  ✗ Restoring the vi command to its default'
        End

    End

End
