# Specs for the step runner. Including the runner sources its sibling libraries,
# so output::fatal is real while the unit::* contract and the state writes are mocked.
# A run log records the order in which the contract steps fire.
Describe 'lib/runner.sh'
    TEST_FLAG=true
    Include lib/runner.sh

    setup() {
        helper::isolate
        RUN_LOG="$SHELLSPEC_TMPBASE/run.log"
        : >"$RUN_LOG"
    }
    BeforeEach 'setup'

    # ==========================================================================
    # runner::unit_name
    # ==========================================================================
    Describe 'runner::unit_name'

        It 'uses MACHINE_SETUP_UNIT_NAME when it is set'
            MACHINE_SETUP_UNIT_NAME=git
            When call runner::unit_name
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'derives the name from the script filename for a per-OS software file'
            MACHINE_SETUP_UNIT_NAME=''
            realpath() { printf '%s' /repo/libexec/ubuntu_26.04/software/git.sh; }

            When call runner::unit_name
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'derives the name from the script basename for a flat unit directly in libexec'
            MACHINE_SETUP_UNIT_NAME=''
            realpath() { printf '%s' /repo/libexec/workspace; }

            When call runner::unit_name
            The status should be success
            The stdout should equal 'workspace'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # runner::id
    # ==========================================================================
    Describe 'runner::id'

        It 'is the unit name when the unit is not instanceable'
            MACHINE_SETUP_UNIT_NAME=git
            When call runner::id
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'is name@instance when the unit declares an instance'
            MACHINE_SETUP_UNIT_NAME=workspace
            unit::instance() { printf 'personal'; }

            When call runner::id
            The status should be success
            The stdout should equal 'workspace@personal'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # runner::status
    # ==========================================================================
    Describe 'runner::status'

        It 'reports unavailable when the unit is not available'
            unit::is_available() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when the unit is available but not installed'
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when the unit is present but not by our mechanism'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports installed when the unit is managed but not configured'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 0; }
            unit::is_configured() { return 1; }

            When call runner::status
            The status should be success
            The stdout should equal 'installed'
            The stderr should be blank
        End

        It 'reports configured when every check passes'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 0; }
            unit::is_configured() { return 0; }

            When call runner::status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # runner::run
    # ==========================================================================
    Describe 'runner::run'

        It 'fails with an error when requirements are not met on install'
            unit::is_available() { return 1; }

            When call runner::run install
            The status should equal 1
            The stdout should be blank
            The stderr should equal 'error: requirements not met'
        End

        It 'runs the install steps in order and records ownership once they succeed'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }       # not present: a fresh install
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own:%s\n' "$1" >>"$RUN_LOG"; }

            When call runner::run install
            The status should be success
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal "$(printf 'request\ninstall\nconfigure\nown:git')"
        End

        It 'records ownership even when the software is already installed by our mechanism'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }       # present...
            unit::is_managed() { return 0; }         # ...and ours, so we adopt it
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own:%s\n' "$1" >>"$RUN_LOG"; }

            When call runner::run install
            The status should be success
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal "$(printf 'request\ninstall\nconfigure\nown:git')"
        End

        It 'refuses to install when the software is present by other means'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }       # present...
            unit::is_managed() { return 1; }         # ...but not ours
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own:%s\n' "$1" >>"$RUN_LOG"; }

            When call runner::run install
            The status should equal 1
            The stdout should be blank
            The stderr should equal 'error: git is already installed by other means'
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'treats a missing action as install'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }
            unit::request_inputs() { :; }
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { :; }
            state::own() { :; }

            When call runner::run
            The status should be success
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'install'
        End

        It 'opens the inputs overlay for the unit and drops the session once the install succeeds'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }
            unit::request_inputs() { :; }
            unit::install() { printf '%s\n' "${MACHINE_SETUP_INPUTS_WORKING##*/machine-setup/}" >>"$RUN_LOG"; }
            unit::configure() { :; }
            state::own() { :; }

            When call runner::run install
            The status should be success
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'execution-in-progress/git/inputs'
            The path "$XDG_STATE_HOME/machine-setup/execution-in-progress" should not be exist
        End

        It 'runs the uninstall steps in order and clears ownership'
            MACHINE_SETUP_UNIT_NAME=git
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }
            unit::unconfigure() { printf 'unconfigure\n' >>"$RUN_LOG"; }
            unit::uninstall() { printf 'uninstall\n' >>"$RUN_LOG"; }
            state::disown() { printf 'disown:%s\n' "$1" >>"$RUN_LOG"; }
            unit::is_installed() { return 1; }       # gone after uninstall: no warning

            When call runner::run uninstall
            The status should be success
            The line 2 of stdout should equal '▶ Uninstalling git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal "$(printf 'request\nunconfigure\nuninstall\ndisown:git')"
        End

        It 'warns without failing when the software is still present after uninstall'
            MACHINE_SETUP_UNIT_NAME=git
            unit::request_inputs() { :; }
            unit::unconfigure() { :; }
            unit::uninstall() { :; }
            state::disown() { :; }
            unit::is_installed() { return 0; }       # still resolves: another install exists

            When call runner::run uninstall
            The status should be success
            The line 2 of stdout should equal '▶ Uninstalling git'
            The stderr should equal '  ! git is still present; it may be installed by other means'
        End

        It 'stops before the next step and propagates the status when a step fails'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }
            unit::request_inputs() { :; }
            unit::install() { return 5; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own\n' >>"$RUN_LOG"; }

            When call runner::run install
            The status should equal 5
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'collects inputs for the step-install-inputs action when the unit may be installed'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 1; }       # not present: a fresh install
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }

            When call runner::run step-install-inputs
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'request'
        End

        It 'fails the step-install-inputs action without collecting inputs when requirements are not met'
            unit::is_available() { return 1; }
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }

            When call runner::run step-install-inputs
            The status should equal 1
            The stdout should be blank
            The stderr should equal 'error: requirements not met'
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'fails the step-install-inputs action when the software is present by other means'
            MACHINE_SETUP_UNIT_NAME=git
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }       # present...
            unit::is_managed() { return 1; }         # ...but not ours
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }

            When call runner::run step-install-inputs
            The status should equal 1
            The stdout should be blank
            The stderr should equal 'error: git is already installed by other means'
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'installs, configures, then records ownership for the step-install action'
            MACHINE_SETUP_UNIT_NAME=git
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own:%s\n' "$1" >>"$RUN_LOG"; }

            When call runner::run step-install
            The status should be success
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal "$(printf 'install\nconfigure\nown:git')"
        End

        It 'stops before configure and ownership when the step-install install fails'
            MACHINE_SETUP_UNIT_NAME=git
            unit::install() { return 5; }
            unit::configure() { printf 'configure\n' >>"$RUN_LOG"; }
            state::own() { printf 'own\n' >>"$RUN_LOG"; }

            When call runner::run step-install
            The status should equal 5
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'does not record ownership when the step-install configure fails'
            MACHINE_SETUP_UNIT_NAME=git
            unit::install() { printf 'install\n' >>"$RUN_LOG"; }
            unit::configure() { return 5; }
            state::own() { printf 'own\n' >>"$RUN_LOG"; }

            When call runner::run step-install
            The status should equal 5
            The line 2 of stdout should equal '▶ Installing git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'install'
        End

        It 'collects inputs for the step-uninstall-inputs action without applying guards'
            MACHINE_SETUP_UNIT_NAME=git
            unit::request_inputs() { printf 'request\n' >>"$RUN_LOG"; }

            When call runner::run step-uninstall-inputs
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'request'
        End

        It 'unconfigures, uninstalls, then clears ownership for the step-uninstall action'
            MACHINE_SETUP_UNIT_NAME=git
            unit::unconfigure() { printf 'unconfigure\n' >>"$RUN_LOG"; }
            unit::uninstall() { printf 'uninstall\n' >>"$RUN_LOG"; }
            state::disown() { printf 'disown:%s\n' "$1" >>"$RUN_LOG"; }
            unit::is_installed() { return 1; }       # gone after uninstall: no warning

            When call runner::run step-uninstall
            The status should be success
            The line 2 of stdout should equal '▶ Uninstalling git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal "$(printf 'unconfigure\nuninstall\ndisown:git')"
        End

        It 'stops before uninstall and ownership when the step-uninstall unconfigure fails'
            MACHINE_SETUP_UNIT_NAME=git
            unit::unconfigure() { return 5; }
            unit::uninstall() { printf 'uninstall\n' >>"$RUN_LOG"; }
            state::disown() { printf 'disown\n' >>"$RUN_LOG"; }

            When call runner::run step-uninstall
            The status should equal 5
            The line 2 of stdout should equal '▶ Uninstalling git'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal ''
        End

        It 'warns without failing when the software is still present after the step-uninstall action'
            MACHINE_SETUP_UNIT_NAME=git
            unit::unconfigure() { :; }
            unit::uninstall() { :; }
            state::disown() { :; }
            unit::is_installed() { return 0; }       # still resolves: another install exists

            When call runner::run step-uninstall
            The status should be success
            The line 2 of stdout should equal '▶ Uninstalling git'
            The stderr should equal '  ! git is still present; it may be installed by other means'
        End

        It 'prints the status word for the status action'
            unit::is_available() { return 0; }
            unit::is_installed() { return 0; }
            unit::is_managed() { return 0; }
            unit::is_configured() { return 0; }

            When call runner::run status
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

        It 'records ownership under the instance id for an instanceable unit'
            MACHINE_SETUP_UNIT_NAME=workspace
            unit::instance() { printf 'personal'; }
            unit::install() { :; }
            unit::configure() { :; }
            state::own() { printf 'own:%s\n' "$1" >>"$RUN_LOG"; }

            When call runner::run step-install
            The status should be success
            The line 2 of stdout should equal '▶ Installing workspace'
            The stderr should be blank
            The contents of file "$RUN_LOG" should equal 'own:workspace@personal'
        End

        It 'fails with an error on an unknown action'
            When call runner::run frobnicate
            The status should equal 2
            The stdout should be blank
            The stderr should equal 'error: unknown action: frobnicate'
        End

    End

End
