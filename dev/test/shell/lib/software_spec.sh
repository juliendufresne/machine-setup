# Specs for the software module. TEST_FLAG keeps the software::* functions and the
# directory globals non-readonly so the spec can Include the library, point the
# directory env-vars at fixtures, and stub the per-piece calls. The software
# executables and the menu are stubbed, so the helpers are checked without a real host.
# helper::isolate redirects the state store and HOME.
Describe 'lib/software.sh'
    TEST_FLAG=true
    Include lib/software.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # software::discover
    # ==========================================================================
    Describe 'software::discover'

        # Fix the OS token so discovery reads a known software/ directory.
        os::file_token() { printf 'ubuntu_26.04'; }

        setup_libexec() {
            LIBEXEC_DIR="$SHELLSPEC_TMPBASE/libexec"
            rm -rf "$LIBEXEC_DIR"
            mkdir -p "$LIBEXEC_DIR/ubuntu_26.04/software"
            printf '#!/usr/bin/env bash\n' >"$LIBEXEC_DIR/ubuntu_26.04/software/git.sh"
            printf '#!/usr/bin/env bash\n' >"$LIBEXEC_DIR/ubuntu_26.04/software/tree.sh"
            : >"$LIBEXEC_DIR/README"
        }
        BeforeEach 'setup_libexec'

        It 'lists the per-OS software only, ignoring other files in libexec'
            When call software::discover
            The status should be success
            The stdout should equal "$(printf 'git\ntree')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::run
    # ==========================================================================
    Describe 'software::run'

        # Fix the OS token so the software file resolves under a known directory.
        os::file_token() { printf 'ubuntu_26.04'; }

        setup_libexec() {
            LIBEXEC_DIR="$SHELLSPEC_TMPBASE/libexec"
            rm -rf "$LIBEXEC_DIR"
            mkdir -p "$LIBEXEC_DIR/ubuntu_26.04/software"
            printf '#!/usr/bin/env bash\nprintf "software %%s\\n" "$1"\n' >"$LIBEXEC_DIR/ubuntu_26.04/software/git.sh"
            chmod +x "$LIBEXEC_DIR/ubuntu_26.04/software/git.sh"
        }
        BeforeEach 'setup_libexec'

        It 'runs a per-OS software file under the token software directory with the action'
            When call software::run git status
            The status should be success
            The stdout should equal 'software status'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::status_of
    # ==========================================================================
    Describe 'software::status_of'

        It 'prints the status word the software reports'
            software::run() { printf 'configured'; }

            When call software::status_of demo
            The status should be success
            The stdout should equal 'configured'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::description_of
    # ==========================================================================
    Describe 'software::description_of'

        setup_share() {
            SHARE_DIR="$SHELLSPEC_TMPBASE/share"
            rm -rf "$SHARE_DIR"
            mkdir -p "$SHARE_DIR/git"
            printf 'Version control\n' >"$SHARE_DIR/git/description"
        }
        BeforeEach 'setup_share'

        It 'prints the one-line description for a unit that has one'
            When call software::description_of git
            The status should be success
            The stdout should equal 'Version control'
            The stderr should be blank
        End

        It 'prints nothing when the description file is absent'
            When call software::description_of ghost
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::mark
    # ==========================================================================
    Describe 'software::mark'

        It 'prints a check for a true flag'
            When call software::mark 1
            The status should be success
            The stdout should equal "$OUTPUT_GLYPH_SUCCESS"
            The stderr should be blank
        End

        It 'prints a cross for a false flag'
            When call software::mark 0
            The status should be success
            The stdout should equal "$OUTPUT_GLYPH_ERROR"
            The stderr should be blank
        End

        It 'prints a dash for a not-applicable flag'
            When call software::mark -
            The status should be success
            The stdout should equal '-'
            The stderr should be blank
        End

        It 'wraps the glyph in colour when colour is enabled'
            output::color_enabled() { return 0; }

            When call software::mark 1
            The status should be success
            The stdout should include '0;32m'
            The stdout should include "$OUTPUT_GLYPH_SUCCESS"
            The stderr should be blank
        End

    End

End
