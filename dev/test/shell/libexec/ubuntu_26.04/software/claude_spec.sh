# Specs for the claude unit on Ubuntu 26.04. TEST_FLAG keeps the unit's functions
# non-readonly so the spec can source it, and the unit's own Execute guard keeps
# it from running when Included. The system-touching commands are stubbed so no
# apt operation or download reaches the real host: sudo runs the wrapped command,
# apt-get logs its args, and curl and bash are no-ops so the native installer
# never runs. is_managed and uninstall are file checks against an isolated HOME, so
# they create and remove the binary under the temp tree rather than stubbing dpkg.
Describe 'libexec/ubuntu_26.04/software/claude.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/claude.sh

    # Isolated host plus a log to spy on apt-get. CLAUDE_ON_PATH drives
    # is_installed (does `command -v claude` resolve); is_managed is a file-presence
    # check against the isolated HOME that the fs-touching tests steer by creating
    # or removing the binary the native installer would place.
    setup() {
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=claude
        export APT_LOG="$SHELLSPEC_TMPBASE/apt.log"
        : >"$APT_LOG"
        : "${CLAUDE_ON_PATH:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. command is shadowed only for
    # `command -v claude`; every other call falls through to the real builtin. sudo
    # runs the wrapped command so its stub is exercised; apt-get logs its call; curl
    # and bash are no-ops so the native installer pipeline never runs.
    command() {
        if [ "$1" = -v ] && [ "$2" = claude ]
        then [ "${CLAUDE_ON_PATH}" = 1 ]
        else builtin command "$@"
        fi
    }
    sudo()    { "$@"; }                                # run the wrapped command
    apt-get() { printf '%s\n' "$*" >>"$APT_LOG"; }     # record the apt-get call
    curl()    { :; }                                   # never fetch the installer
    bash()    { :; }                                   # never run the installer

    # Create the binary the native installer places, under the isolated HOME, so
    # is_managed and the uninstall and status checks observe a managed install.
    helper::seed_binary() {
        mkdir -p "$HOME/.local/bin"
        : >"$HOME/.local/bin/claude"
        chmod +x "$HOME/.local/bin/claude"
    }

    # ==========================================================================
    # claude::_binary_path
    # ==========================================================================
    Describe 'claude::_binary_path'

        It 'reports the binary path under the user home'
            When call claude::_binary_path
            The status should be success
            The stdout should equal "$HOME/.local/bin/claude"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # claude::_data_dir
    # ==========================================================================
    Describe 'claude::_data_dir'

        It 'reports the data directory under the user home'
            When call claude::_data_dir
            The status should be success
            The stdout should equal "$HOME/.local/share/claude"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # claude::_run_installer
    # ==========================================================================
    Describe 'claude::_run_installer'

        It 'pipes the native installer into bash'
            When call claude::_run_installer
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is always available because claude works headless and on WSL'
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when claude resolves on the host'
            CLAUDE_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when claude resolves nowhere'
            CLAUDE_ON_PATH=0
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

        It 'is true when our installed binary is present'
            helper::seed_binary

            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when our installed binary is absent'
            When call unit::is_managed
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_configured
    # ==========================================================================
    Describe 'unit::is_configured'

        It 'is always satisfied because claude needs no configuration'
            When call unit::is_configured
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::request_inputs
    # ==========================================================================
    Describe 'unit::request_inputs'

        It 'warms the sudo session because the prerequisite step needs root'
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

        It 'updates the lists, installs prerequisites, then runs the installer and reports each step'
            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Installing Claude Code'
            The stderr should be blank
            The contents of file "$APT_LOG" should equal 'update -qq
install -y ca-certificates curl'
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

        It 'reports available when claude is not present'
            CLAUDE_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when claude is present but not via our installer'
            CLAUDE_ON_PATH=1
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as our installed binary is present'
            CLAUDE_ON_PATH=1
            helper::seed_binary

            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::configure
    # ==========================================================================
    Describe 'unit::configure'

        It 'does nothing because claude needs no configuration'
            When call unit::configure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::unconfigure
    # ==========================================================================
    Describe 'unit::unconfigure'

        It 'does nothing because claude has no configuration to restore'
            When call unit::unconfigure
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::uninstall
    # ==========================================================================
    Describe 'unit::uninstall'

        It 'removes the binary and the data directory and reports each step'
            helper::seed_binary
            mkdir -p "$HOME/.local/share/claude"

            When call unit::uninstall
            The status should be success
            The line 1 of stdout should equal '  ✓ Removing the claude binary'
            The line 2 of stdout should equal '  ✓ Removing the Claude Code data directory'
            The stderr should be blank
            The path "$HOME/.local/bin/claude" should not be exist
            The path "$HOME/.local/share/claude" should not be exist
        End

    End

    # ==========================================================================
    # claude::main
    # ==========================================================================
    Describe 'claude::main'

        It 'hands the action to the runner, which prints the status word'
            CLAUDE_ON_PATH=0
            When call claude::main status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

    End

End
