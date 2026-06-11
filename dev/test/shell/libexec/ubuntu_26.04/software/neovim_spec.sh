# Specs for the neovim unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. dpkg, sudo, and apt-get are stubbed so no package
# operation ever touches the real host. The unit sources its
# lib/software/neovim/debian-family/configure fragment, so unit::is_configured is
# available here and drives runner::status; the configuration contract itself is
# covered by that fragment's configure_spec.sh, so only the status path models the
# editor alternatives here.
Describe 'libexec/ubuntu_26.04/software/neovim.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/neovim.sh

    # Isolated host and a log to spy on apt-get. NEOVIM_ON_PATH drives is_installed
    # (does `command -v nvim` resolve) and NEOVIM_PRESENT drives is_managed (does
    # `dpkg -s neovim` report the package), so a test can pretend neovim is present by
    # any means, present via our package, or absent, without touching the host. The
    # fake alternative selection (ALT_VALUE, the binary every managed group resolves
    # to) drives is_configured.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=neovim
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        export ALT_VALUE="$SHELLSPEC_TMPBASE/alt_value"
        : >"$APT_LOG"
        : "${NEOVIM_ON_PATH:=1}"
        : "${NEOVIM_PRESENT:=1}"
        printf '/usr/bin/vim.basic\n' >"$ALT_VALUE"     # the distro default, not yet pointed at neovim
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v nvim`, which resolves to /usr/bin/nvim when on PATH; every other
    # call falls through to the real builtin. update-alternatives reports the fake
    # selection (the same value for every group) so is_configured can be exercised
    # without the system database.
    command() {
        if [ "$1" = -v ] && [ "$2" = nvim ]
        then [ "${NEOVIM_ON_PATH}" = 1 ] && printf '/usr/bin/nvim\n'
        else builtin command "$@"
        fi
    }
    dpkg()    { [ "${NEOVIM_PRESENT}" = 1 ]; }           # `dpkg -s neovim`
    sudo()    { "$@"; }                                  # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }      # record the apt-get call

    update-alternatives() {                             # report the fake selection for any group
        printf 'Name: %s\nValue: %s\n' "$2" "$(cat "$ALT_VALUE" 2>/dev/null)"
    }

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when nvim resolves on the host'
            NEOVIM_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when nvim resolves nowhere'
            NEOVIM_ON_PATH=0
            When call unit::is_installed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_managed
    # ==========================================================================
    Describe 'unit::is_managed'

        It 'is true when dpkg reports the neovim package present'
            NEOVIM_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the neovim package absent'
            NEOVIM_PRESENT=0
            When call unit::is_managed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::request_inputs
    # ==========================================================================
    Describe 'unit::request_inputs'

        It 'warms the sudo session because the package steps need root'
            sudo::warmup() { return 0; }

            When call unit::request_inputs
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::install
    # ==========================================================================
    Describe 'unit::install'

        It 'updates the package lists then installs neovim and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing the neovim package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y neovim'
        End

        It 'stops at the failing step and propagates its status'
            apt-get() { return 7; }

            When call unit::install
            The status should equal 7
            The stdout should be blank
            The stderr should equal '  ✗ Updating the package lists'
        End

    End

    # ==========================================================================
    # runner::status
    # ==========================================================================
    Describe 'runner::status'

        It 'reports available when neovim is not present'
            NEOVIM_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when neovim is present but not via our package'
            NEOVIM_ON_PATH=1
            NEOVIM_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports installed when ours but the editor commands do not point at neovim'
            NEOVIM_ON_PATH=1
            NEOVIM_PRESENT=1
            printf '/usr/bin/vim.basic\n' >"$ALT_VALUE"

            When call runner::status
            The status should be success
            The stdout should equal 'installed'
            The stderr should be blank
        End

        It 'reports configured when ours and the editor commands point at neovim'
            NEOVIM_ON_PATH=1
            NEOVIM_PRESENT=1
            printf '/usr/bin/nvim\n' >"$ALT_VALUE"

            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::uninstall
    # ==========================================================================
    Describe 'unit::uninstall'

        It 'purges neovim and reports the step'
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the neovim package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y neovim'
        End

        It 'purges neovim even when this tool never recorded installing it'
            # no ownership state seeded: uninstall must not depend on it
            When call unit::uninstall
            The status should be success
            The stdout should equal '  ✓ Purging the neovim package'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'purge -y neovim'
        End

    End

    # ==========================================================================
    # neovim::main
    # ==========================================================================
    Describe 'neovim::main'

        It 'hands the action to the runner, which prints the status word'
            NEOVIM_ON_PATH=0
            When call neovim::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
