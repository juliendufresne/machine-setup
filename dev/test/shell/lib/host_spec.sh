# Specs for host probing. The session directories are redirected at a temp tree
# per example, so the result never depends on the real host.
Describe 'lib/host.sh'
    TEST_FLAG=true
    Include lib/host.sh

    # Redirect the session probes at fresh, empty temp directories so a spec
    # controls exactly which session entries appear to be installed.
    setup() {
        export HOST_XSESSIONS_DIR="$SHELLSPEC_TMPBASE/xsessions"
        export HOST_WAYLAND_SESSIONS_DIR="$SHELLSPEC_TMPBASE/wayland-sessions"
        rm -rf "$HOST_XSESSIONS_DIR" "$HOST_WAYLAND_SESSIONS_DIR"
        mkdir -p "$HOST_XSESSIONS_DIR" "$HOST_WAYLAND_SESSIONS_DIR"
    }
    BeforeEach 'setup'

    # ==========================================================================
    # host::_session_entries
    # ==========================================================================
    Describe 'host::_session_entries'

        It 'prints the basename of each installed session entry'
            touch "$HOST_XSESSIONS_DIR/plasma.desktop"
            touch "$HOST_WAYLAND_SESSIONS_DIR/gnome.desktop"
            When call host::_session_entries
            The status should be success
            The line 1 of stdout should equal 'plasma.desktop'
            The line 2 of stdout should equal 'gnome.desktop'
            The stderr should be blank
        End

        It 'prints nothing when no session entry is installed'
            When call host::_session_entries
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'ignores files that are not .desktop entries'
            touch "$HOST_XSESSIONS_DIR/README"
            When call host::_session_entries
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'skips a session directory that does not exist'
            rm -rf "$HOST_XSESSIONS_DIR"
            touch "$HOST_WAYLAND_SESSIONS_DIR/sway.desktop"
            When call host::_session_entries
            The status should be success
            The stdout should equal 'sway.desktop'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # host::has_desktop
    # ==========================================================================
    Describe 'host::has_desktop'

        It 'is true when an X11 session entry is installed'
            touch "$HOST_XSESSIONS_DIR/plasma.desktop"
            When call host::has_desktop
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is true when a Wayland session entry is installed'
            touch "$HOST_WAYLAND_SESSIONS_DIR/gnome.desktop"
            When call host::has_desktop
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when no session entry is installed (a headless server, or WSL)'
            When call host::has_desktop
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

End
