# Specs for the orchestrator flow. The software mechanics and menus live in
# lib/software.sh and the provisioner menu and run in lib/provisioner.sh, each with
# their own spec; this file checks the flow that drives them (usage, setup, teardown,
# main). TEST_FLAG keeps the machine_setup::* functions non-readonly so the spec can Include
# the file and stub the software:: and provisioner:: calls; the script's own Execute
# guard keeps machine_setup::main from running on Include.
Describe 'bin/machine-setup'
    TEST_FLAG=true
    Include bin/machine-setup

    setup() {
        helper::isolate
    }
    BeforeEach 'setup'

    # ==========================================================================
    # machine_setup::usage
    # ==========================================================================
    Describe 'machine_setup::usage'

        It 'prints the usage synopsis to stdout'
            When call machine_setup::usage
            The status should be success
            The stdout should include 'Usage: machine-setup'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # machine_setup::install
    # ==========================================================================
    Describe 'machine_setup::install'

        software::install::pick() { printf 'alpha\nbeta\n'; }
        software::install() { printf 'install[%s]\n' "$*"; }
        provisioner::choose() { printf 'workspace\ndotfiles\n'; }
        provisioner::provision_all() { printf 'provision[%s]\n' "$*"; }

        It 'selects software interactively, installs it, then provisions the chosen ones'
            When call machine_setup::install
            The status should be success
            The line 1 of stdout should equal 'install[alpha beta]'
            The line 2 of stdout should equal 'provision[workspace dotfiles]'
            The stderr should be blank
        End

        It 'installs exactly the named software and never provisions on an unattended run'
            When call machine_setup::install tree
            The status should be success
            The stdout should equal 'install[tree]'
            The stderr should be blank
        End

        It 'passes a provisioner name straight through on a named run, no longer special-cased'
            When call machine_setup::install git workspace
            The status should be success
            The stdout should equal 'install[git workspace]'
            The stderr should be blank
        End

        It 'skips provisioning when the toggle menu resolves to nothing'
            provisioner::choose() { :; }

            When call machine_setup::install
            The status should be success
            The stdout should equal 'install[alpha beta]'
            The stderr should be blank
        End

        It 'never removes a deselected piece'
            software::uninstall::pick() { printf 'removal called\n' >&2; }

            When call machine_setup::install
            The status should be success
            The line 1 of stdout should equal 'install[alpha beta]'
            The stderr should be blank
        End

        It 'propagates the status from the install'
            software::install() {
                printf 'install[%s]\n' "$*"

                return 5
            }

            When call machine_setup::install
            The status should equal 5
            The line 1 of stdout should equal 'install[alpha beta]'
            The stderr should be blank
        End

        It 'returns the worst status across the install and the provisioning'
            provisioner::provision_all() {
                printf 'provision[%s]\n' "$*"

                return 7
            }

            When call machine_setup::install
            The status should equal 7
            The line 2 of stdout should equal 'provision[workspace dotfiles]'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # machine_setup::uninstall
    # ==========================================================================
    Describe 'machine_setup::uninstall'

        software::uninstall::pick() { printf 'gamma\n'; }
        software::uninstall() { printf 'uninstall[%s]\n' "$*"; }

        It 'reverses exactly the named software without opening the menu'
            software::uninstall::pick() { printf 'MENU\n'; }

            When call machine_setup::uninstall git tree
            The status should be success
            The stdout should equal 'uninstall[git tree]'
            The stderr should be blank
        End

        It 'opens the removal menu and reverses the chosen software when given no names'
            When call machine_setup::uninstall
            The status should be success
            The stdout should equal 'uninstall[gamma]'
            The stderr should be blank
        End

        It 'removes nothing when the menu resolves to nothing'
            software::uninstall::pick() { :; }

            When call machine_setup::uninstall
            The status should be success
            The stdout should equal 'uninstall[]'
            The stderr should be blank
        End

        It 'propagates the status from the removal'
            software::uninstall() { return 6; }

            When call machine_setup::uninstall git
            The status should equal 6
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # machine_setup::main
    # ==========================================================================
    Describe 'machine_setup::main'

        machine_setup::usage() { printf 'USAGE\n'; }
        software::status_report() { printf 'status %s\n' "$*"; }
        machine_setup::uninstall() { printf 'teardown %s\n' "$*"; }
        machine_setup::install() { printf 'setup %s\n' "$*"; }

        It 'prints usage to stdout for --help'
            When call machine_setup::main --help
            The status should be success
            The stdout should equal 'USAGE'
            The stderr should be blank
        End

        It 'reports status for the named software through the status action'
            When call machine_setup::main status git tree
            The status should be success
            The stdout should equal 'status git tree'
            The stderr should be blank
        End

        It 'removes the named software through the uninstall action'
            When call machine_setup::main uninstall tree
            The status should be success
            The stdout should equal 'teardown tree'
            The stderr should be blank
        End

        It 'runs the interactive setup when called with no arguments'
            When call machine_setup::main
            The status should be success
            The stdout should equal 'setup '
            The stderr should be blank
        End

        It 'survives errexit when called with no arguments (the curl | sh path)'
            # install.sh execs the orchestrator with no arguments under `set -e`.
            # The no-argument default must not shift off a non-existent positional
            # parameter, or errexit aborts the run before the set-up starts. This
            # runs the real script in a subprocess because shellspec disables
            # errexit during a plain `When call`, which would hide the failure;
            # machine_setup::install is stubbed there so no real software runs.
            When run command bash -c '
                set -euo pipefail
                TEST_FLAG=true
                source bin/machine-setup
                machine_setup::install() { printf "setup %s\n" "$*"; }
                machine_setup::main
            '
            The status should be success
            The stdout should equal 'setup '
            The stderr should be blank
        End

        It 'runs the setup for the install action with names'
            When call machine_setup::main install tree
            The status should be success
            The stdout should equal 'setup tree'
            The stderr should be blank
        End

        It 'treats a bare software name as software to set up'
            When call machine_setup::main tree
            The status should be success
            The stdout should equal 'setup tree'
            The stderr should be blank
        End

        It 'propagates the status from the setup'
            machine_setup::install() { return 7; }

            When call machine_setup::main
            The status should equal 7
            The stdout should be blank
            The stderr should be blank
        End

        It 'propagates the status from the status report'
            software::status_report() { return 3; }

            When call machine_setup::main status
            The status should equal 3
            The stdout should be blank
            The stderr should be blank
        End

    End

End
