# Specs for the fish unit's configuration contract and the helpers it shares.
# TEST_FLAG keeps the functions non-readonly so the spec can source them. The
# configure file is a sourced fragment that relies on output::run, so lib/output.sh
# is included first; getent and id are stubbed so the login shell is whatever
# DEFAULT_SHELL says, and the hooks edit shell rc files under the isolated HOME, so
# they touch only the per-example temp tree.
Describe 'lib/software/fish/configure'
    TEST_FLAG=true
    Include lib/output.sh
    Include lib/software/fish/configure

    # Isolated HOME so the rc-file edits stay in the per-example temp tree.
    # DEFAULT_SHELL is the basename of the login shell that getent reports, so a
    # test can pretend bash, zsh, or fish is the default without touching the host.
    setup() {
        helper::isolate
        : "${DEFAULT_SHELL:=bash}"
    }
    BeforeEach 'setup'

    # getent and id together report DEFAULT_SHELL as the login shell.
    id()     { printf 'tester\n'; }                                             # `id -un`
    getent() { printf 'tester:x:1000:1000::/home/tester:/usr/bin/%s\n' "$DEFAULT_SHELL"; }

    # ==========================================================================
    # fish::rc_files
    # ==========================================================================
    Describe 'fish::rc_files'

        It 'lists the bash and zsh rc files under HOME'
            When call fish::rc_files
            The status should be success
            The line 1 of stdout should equal "$HOME/.bashrc"
            The line 2 of stdout should equal "$HOME/.zshrc"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # fish::default_shell
    # ==========================================================================
    Describe 'fish::default_shell'

        It 'prints the basename of the login shell from the passwd entry'
            DEFAULT_SHELL=zsh
            When call fish::default_shell
            The status should be success
            The stdout should equal 'zsh'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # fish::default_rc
    # ==========================================================================
    Describe 'fish::default_rc'

        It 'is the bashrc when the login shell is bash'
            DEFAULT_SHELL=bash
            When call fish::default_rc
            The status should be success
            The stdout should equal "$HOME/.bashrc"
            The stderr should be blank
        End

        It 'is the zshrc when the login shell is zsh'
            DEFAULT_SHELL=zsh
            When call fish::default_rc
            The status should be success
            The stdout should equal "$HOME/.zshrc"
            The stderr should be blank
        End

        It 'is empty when the login shell is neither bash nor zsh'
            DEFAULT_SHELL=fish
            When call fish::default_rc
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # fish::block
    # ==========================================================================
    Describe 'fish::block'

        It 'prints the snippet delimited by the begin and end markers'
            When call fish::block
            The status should be success
            The line 1 of stdout should equal '# >>> machine-setup fish >>>'
            The stdout should include 'exec fish'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # fish::has_block
    # ==========================================================================
    Describe 'fish::has_block'

        It 'is true when the file carries the begin marker'
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call fish::has_block "$HOME/.bashrc"
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the file lacks the begin marker'
            printf 'existing\n' >"$HOME/.bashrc"

            When call fish::has_block "$HOME/.bashrc"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # fish::add_block
    # ==========================================================================
    Describe 'fish::add_block'

        It 'prepends the block at the top of the file'
            printf 'first line\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call head -n 1 "$HOME/.bashrc"
            The status should be success
            The stdout should equal '# >>> machine-setup fish >>>'
            The stderr should be blank
        End

        It 'keeps the existing content below the block'
            printf 'first line\n' >"$HOME/.bashrc"

            When call fish::add_block "$HOME/.bashrc"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should include 'first line'
        End

    End

    # ==========================================================================
    # fish::remove_block
    # ==========================================================================
    Describe 'fish::remove_block'

        It 'deletes the block and restores the rest of the file'
            printf 'keep me\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call fish::remove_block "$HOME/.bashrc"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should equal 'keep me'
        End

    End

    # ==========================================================================
    # unit::is_configured
    # ==========================================================================
    Describe 'unit::is_configured'

        It 'is satisfied when no shell rc file exists'
            When call unit::is_configured
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is satisfied when the login shell rc carries the block and the other is clean'
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"
            printf 'existing\n' >"$HOME/.zshrc"

            When call unit::is_configured
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is unsatisfied when the login shell rc lacks the block'
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"

            When call unit::is_configured
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is unsatisfied when a non-login shell rc still carries the block'
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"
            printf 'existing\n' >"$HOME/.zshrc"
            fish::add_block "$HOME/.zshrc"

            When call unit::is_configured
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is satisfied when the login shell is fish and every rc file is clean'
            DEFAULT_SHELL=fish
            printf 'existing\n' >"$HOME/.bashrc"

            When call unit::is_configured
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::configure
    # ==========================================================================
    Describe 'unit::configure'

        It 'adds the block to the login shell rc and reports it'
            DEFAULT_SHELL=bash
            printf 'existing bashrc\n' >"$HOME/.bashrc"

            When call unit::configure
            The status should be success
            The stdout should equal '  ✓ Adding the fish hand-off block to .bashrc'
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should include 'exec fish'
        End

        It 'adds to the login shell rc and strips a stale block from another shell rc'
            DEFAULT_SHELL=bash
            printf 'existing bashrc\n' >"$HOME/.bashrc"
            printf 'existing zshrc\n' >"$HOME/.zshrc"
            fish::add_block "$HOME/.zshrc"

            When call unit::configure
            The status should be success
            The line 1 of stdout should equal '  ✓ Adding the fish hand-off block to .bashrc'
            The line 2 of stdout should equal '  ✓ Removing the fish hand-off block from .zshrc'
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should include 'exec fish'
            The contents of file "$HOME/.zshrc" should not include 'exec fish'
        End

        It 'skips a shell whose rc file does not exist'
            DEFAULT_SHELL=bash
            printf 'existing bashrc\n' >"$HOME/.bashrc"

            When call unit::configure
            The status should be success
            The stdout should equal '  ✓ Adding the fish hand-off block to .bashrc'
            The stderr should be blank
            The path "$HOME/.zshrc" should not be exist
        End

        It 'does nothing when the login shell rc already has the block'
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call unit::configure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'only strips the block when the login shell is already fish'
            DEFAULT_SHELL=fish
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"

            When call unit::configure
            The status should be success
            The stdout should equal '  ✓ Removing the fish hand-off block from .bashrc'
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should not include 'exec fish'
        End

        It 'stops at the failing edit and propagates its status'
            DEFAULT_SHELL=bash
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block() { return 5; }

            When call unit::configure
            The status should equal 5
            The stdout should be blank
            The stderr should equal '  ✗ Adding the fish hand-off block to .bashrc'
        End

    End

    # ==========================================================================
    # unit::unconfigure
    # ==========================================================================
    Describe 'unit::unconfigure'

        It 'removes the block from every rc file that carries it and reports each one'
            printf 'existing bashrc\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"
            printf 'existing zshrc\n' >"$HOME/.zshrc"
            fish::add_block "$HOME/.zshrc"

            When call unit::unconfigure
            The status should be success
            The line 1 of stdout should equal '  ✓ Removing the fish hand-off block from .bashrc'
            The line 2 of stdout should equal '  ✓ Removing the fish hand-off block from .zshrc'
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should not include 'exec fish'
            The contents of file "$HOME/.bashrc" should include 'existing bashrc'
        End

        It 'leaves an rc file without the block untouched'
            printf 'existing\n' >"$HOME/.bashrc"

            When call unit::unconfigure
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.bashrc" should equal 'existing'
        End

        It 'stops at the failing edit and propagates its status'
            printf 'existing\n' >"$HOME/.bashrc"
            fish::add_block "$HOME/.bashrc"
            fish::remove_block() { return 5; }

            When call unit::unconfigure
            The status should equal 5
            The stdout should be blank
            The stderr should equal '  ✗ Removing the fish hand-off block from .bashrc'
        End

    End

End
