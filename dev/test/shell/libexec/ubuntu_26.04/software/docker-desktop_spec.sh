# Specs for the docker-desktop unit on Ubuntu 26.04. TEST_FLAG keeps the unit's
# functions non-readonly so the spec can source it, and the unit's own Execute
# guard keeps it from running when Included. Every system-touching command (sudo,
# apt-get, curl, install, chmod, tee, rm, dpkg, command) is stubbed so no package
# operation or file write ever reaches the real host, and the host probes are
# stubbed so the result never depends on the test machine.
Describe 'libexec/ubuntu_26.04/software/docker-desktop.sh'
    TEST_FLAG=true
    Include libexec/ubuntu_26.04/software/docker-desktop.sh

    # Isolated host plus a log to spy on the commands. DD_ON_PATH drives
    # is_installed (does `command -v docker-desktop` resolve), DD_PRESENT drives
    # is_managed (does `dpkg -s docker-desktop` report the package), DD_HAS_DESKTOP
    # drives is_available, and DD_GT_PRESENT drives whether gnome-terminal already
    # resolves, which is_install's gnome-terminal branch keys on. TMPDIR is pinned
    # under the temp base so the .deb path is stable.
    setup() {
        export CMD_LOG="$SHELLSPEC_TMPBASE/cmd.log"
        helper::isolate
        export MACHINE_SETUP_UNIT_NAME=docker-desktop
        export TMPDIR="$SHELLSPEC_TMPBASE"
        command rm -rf "$XDG_STATE_HOME/machine-setup" # rm is stubbed below, so isolate cannot clear the store; do it for real
        : >"$CMD_LOG"                                   # discard isolate's own rm log
        : "${DD_ON_PATH:=1}"
        : "${DD_PRESENT:=1}"
        : "${DD_HAS_DESKTOP:=1}"
        : "${DD_GT_PRESENT:=1}"
    }
    BeforeEach 'setup'

    # Stubs for the only system-touching commands. sudo runs the wrapped command
    # so its stub is exercised; command is shadowed only for `command -v
    # docker-desktop`; dpkg answers both the presence query and the architecture
    # query; everything else logs its call instead of touching the host.
    sudo()    { "$@"; }
    apt-get() { printf 'apt-get %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    curl()    { printf 'curl %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    install() { printf 'install %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    chmod()   { printf 'chmod %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    tee()     { cat >/dev/null; printf 'tee %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }
    rm()      { printf 'rm %s\n' "$*" >>"${CMD_LOG:-/dev/null}"; }

    dpkg() {
        if [ "$1" = --print-architecture ]
        then printf 'amd64\n'
        else [ "${DD_PRESENT}" = 1 ]
        fi
    }

    command() {
        if [ "$1" = -v ] && [ "$2" = docker-desktop ]
        then [ "${DD_ON_PATH}" = 1 ]
        elif [ "$1" = -v ] && [ "$2" = gnome-terminal ]
        then [ "${DD_GT_PRESENT}" = 1 ]
        else builtin command "$@"
        fi
    }

    host::has_desktop() { [ "${DD_HAS_DESKTOP}" = 1 ]; }

    # ==========================================================================
    # docker::desktop::_deb_path
    # ==========================================================================
    Describe 'docker::desktop::_deb_path'

        It 'reports the .deb path under the temp directory'
            When call docker::desktop::_deb_path
            The status should be success
            The stdout should equal "$SHELLSPEC_TMPBASE/docker-desktop-amd64.deb"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # docker::desktop::_codename
    # ==========================================================================
    Describe 'docker::desktop::_codename'

        It 'prints the release codename read from os-release'
            When call docker::desktop::_codename
            The status should be success
            The stdout should not be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # docker::desktop::_add_apt_repository
    # ==========================================================================
    Describe 'docker::desktop::_add_apt_repository'

        It 'creates the keyring, fetches the key, and writes the sources list'
            docker::desktop::_codename() { printf 'plucky'; }

            When call docker::desktop::_add_apt_repository
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should equal 'install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.list'
        End

        It 'stops and propagates the status when a step fails'
            install() { return 4; }

            When call docker::desktop::_add_apt_repository
            The status should equal 4
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # docker::desktop::_install_gnome_terminal
    # ==========================================================================
    Describe 'docker::desktop::_install_gnome_terminal'

        It 'installs the package and records that we installed it'
            When call docker::desktop::_install_gnome_terminal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get install -y gnome-terminal'
            The path "$XDG_STATE_HOME/machine-setup/managed/docker-desktop_gnome-terminal" should be file
        End

        It 'records nothing when the install fails'
            apt-get() { return 6; }

            When call docker::desktop::_install_gnome_terminal
            The status should equal 6
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/machine-setup/managed/docker-desktop_gnome-terminal" should not be exist
        End

    End

    # ==========================================================================
    # docker::desktop::_warn_orphaned_gnome_terminal
    # ==========================================================================
    Describe 'docker::desktop::_warn_orphaned_gnome_terminal'

        It 'warns and clears the record when we installed gnome-terminal'
            state::disown() { printf 'disown %s\n' "$1" >>"$CMD_LOG"; }  # the real one would use the stubbed rm
            state::own docker-desktop/gnome-terminal

            When call docker::desktop::_warn_orphaned_gnome_terminal
            The status should be success
            The stdout should be blank
            The stderr should include 'gnome-terminal was installed for Docker Desktop'
            The contents of file "$CMD_LOG" should include 'disown docker-desktop/gnome-terminal'
        End

        It 'does nothing when we did not install gnome-terminal'
            When call docker::desktop::_warn_orphaned_gnome_terminal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_available
    # ==========================================================================
    Describe 'unit::is_available'

        It 'is true when the host has a desktop'
            DD_HAS_DESKTOP=1
            When call unit::is_available
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the host is headless'
            DD_HAS_DESKTOP=0
            When call unit::is_available
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # unit::is_installed
    # ==========================================================================
    Describe 'unit::is_installed'

        It 'is true when docker-desktop resolves on the host'
            DD_ON_PATH=1
            When call unit::is_installed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when docker-desktop resolves nowhere'
            DD_ON_PATH=0
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

        It 'is true when dpkg reports the docker-desktop package present'
            DD_PRESENT=1
            When call unit::is_managed
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when dpkg reports the docker-desktop package absent'
            DD_PRESENT=0
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

        It 'is always satisfied because docker-desktop needs no configuration'
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

        It 'installs gnome-terminal too when it is not already present'
            DD_GT_PRESENT=0

            When call unit::install
            The status should be success
            The line 1 of stdout should equal '  ✓ Updating the package lists'
            The line 2 of stdout should equal '  ✓ Installing prerequisite packages'
            The line 3 of stdout should equal '  ✓ Installing gnome-terminal'
            The line 4 of stdout should equal '  ✓ Adding the Docker apt repository'
            The line 5 of stdout should equal '  ✓ Updating the package lists'
            The line 6 of stdout should equal '  ✓ Downloading Docker Desktop'
            The line 7 of stdout should equal '  ✓ Installing the docker-desktop package'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get install -y gnome-terminal'
        End

        It 'skips gnome-terminal when it is already present'
            DD_GT_PRESENT=1

            When call unit::install
            The status should be success
            The line 3 of stdout should equal '  ✓ Adding the Docker apt repository'
            The stdout should not include 'gnome-terminal'
            The stderr should be blank
            The contents of file "$CMD_LOG" should not include 'gnome-terminal'
        End

        It 'downloads and installs the package from the official sources'
            DD_GT_PRESENT=1

            When call unit::install
            The status should be success
            The stdout should not be blank
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'curl -fsSL https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb -o '"$SHELLSPEC_TMPBASE/docker-desktop-amd64.deb"
            The contents of file "$CMD_LOG" should include "apt-get install -y $SHELLSPEC_TMPBASE/docker-desktop-amd64.deb"
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

        It 'reports unavailable when the host has no desktop'
            DD_HAS_DESKTOP=0
            When call runner::status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

        It 'reports available when docker-desktop is not present'
            DD_ON_PATH=0
            When call runner::status
            The status should be success
            The stdout should equal 'available'
            The stderr should be blank
        End

        It 'reports unmanaged when docker-desktop is present but not via our package'
            DD_ON_PATH=1
            DD_PRESENT=0
            When call runner::status
            The status should be success
            The stdout should equal 'unmanaged'
            The stderr should be blank
        End

        It 'reports configured as soon as docker-desktop is present via our package'
            DD_ON_PATH=1
            DD_PRESENT=1
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

        It 'does nothing because docker-desktop needs no configuration'
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

        It 'does nothing because docker-desktop has no configuration to restore'
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

        It 'purges the package and removes the residual files'
            When call unit::uninstall
            The status should be success
            The line 1 of stdout should equal '  ✓ Purging the docker-desktop package'
            The line 2 of stdout should equal '  ✓ Removing residual Docker Desktop files'
            The stderr should be blank
            The contents of file "$CMD_LOG" should include 'apt-get purge -y docker-desktop'
            The contents of file "$CMD_LOG" should include "rm -rf $HOME/.docker/desktop"
            The contents of file "$CMD_LOG" should include 'rm -f /usr/local/bin/com.docker.cli'
        End

        It 'warns that gnome-terminal was left behind when we installed it'
            state::own docker-desktop/gnome-terminal

            When call unit::uninstall
            The status should be success
            The line 1 of stdout should equal '  ✓ Purging the docker-desktop package'
            The line 2 of stdout should equal '  ✓ Removing residual Docker Desktop files'
            The stderr should include 'gnome-terminal was installed for Docker Desktop'
        End

        It 'stops at the failing step and propagates its status'
            apt-get() { return 9; }

            When call unit::uninstall
            The status should equal 9
            The stdout should be blank
            The stderr should equal '  ✗ Purging the docker-desktop package'
        End

    End

    # ==========================================================================
    # docker::desktop::main
    # ==========================================================================
    Describe 'docker::desktop::main'

        It 'hands the action to the runner, which prints the status word'
            DD_HAS_DESKTOP=0
            When call docker::desktop::main status
            The status should be success
            The stdout should equal 'unavailable'
            The stderr should be blank
        End

    End

End
