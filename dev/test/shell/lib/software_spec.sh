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

    # ==========================================================================
    # software::cell
    # ==========================================================================
    Describe 'software::cell'

        It 'left-aligns the mark in a column of the given width'
            When call software::cell 1 9
            The status should be success
            The stdout should equal "$(printf '%s%8s' "$OUTPUT_GLYPH_SUCCESS" '')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::status_table
    # ==========================================================================
    Describe 'software::status_table'

        # Reproduce a rendered data row the way the formatter does (the name column
        # is four wide for these single-letter names), so the assertions read as
        # columns of checks and crosses instead of counted spaces.
        sw_row() {
            printf '%-4s  %s%8s  %s%8s  %s' "$1" "$2" '' "$3" '' "$4"
        }

        # Feed the rows to the table on stdin, the way software::status_report does;
        # with no rows the table reads an empty stream, not a lone blank line.
        render() {
            if (($# > 0))
            then
                printf '%s\n' "$@" | software::status_table
            else
                software::status_table </dev/null
            fi
        }

        check="$OUTPUT_GLYPH_SUCCESS"
        cross="$OUTPUT_GLYPH_ERROR"
        dash='-'

        It 'maps the word to available and installed, taking managed from the flag'
            # Each software line is name<TAB>word<TAB>managed. The word fixes the
            # first two columns; managed is the explicit flag, so a 'configured' unit
            # the flag marks unowned (row d) reads installed but not managed. An
            # unavailable unit (row a) dashes the installed and managed columns it
            # leaves false rather than crossing them.
            When call render \
                "$(printf 'a\tunavailable\t0')" \
                "$(printf 'b\tavailable\t0')" \
                "$(printf 'c\tunmanaged\t0')" \
                "$(printf 'd\tconfigured\t0')" \
                "$(printf 'e\tconfigured\t1')"
            The status should be success
            The line 1 of stdout should equal 'name  available  installed  managed'
            The line 2 of stdout should equal "$(sw_row a "$cross" "$dash" "$dash")"
            The line 3 of stdout should equal "$(sw_row b "$check" "$cross" "$cross")"
            The line 4 of stdout should equal "$(sw_row c "$check" "$check" "$cross")"
            The line 5 of stdout should equal "$(sw_row d "$check" "$check" "$cross")"
            The line 6 of stdout should equal "$(sw_row e "$check" "$check" "$check")"
            The stderr should be blank
        End

        It 'dashes only the false columns of an unavailable but owned unit'
            # An unavailable unit the state store still marks owned (managed flag 1)
            # keeps the managed check; only the false installed column dashes.
            When call render "$(printf 'a\tunavailable\t1')"
            The status should be success
            The line 2 of stdout should equal "$(sw_row a "$cross" "$dash" "$check")"
            The stderr should be blank
        End

        It 'widens the name column to its widest entry'
            When call render "$(printf 'openssh-client\tconfigured\t1')"
            The status should be success
            The line 1 of stdout should equal 'name            available  installed  managed'
            The stderr should be blank
        End

        It 'prints nothing for an empty section'
            When call render
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::status_report
    # ==========================================================================
    Describe 'software::status_report'

        # Reproduce a rendered software row the way the formatter does (the name
        # column is four wide for these names), so the assertions read as columns.
        sw_row() {
            printf '%-4s  %s%8s  %s%8s  %s' "$1" "$2" '' "$3" '' "$4"
        }

        check="$OUTPUT_GLYPH_SUCCESS"
        cross="$OUTPUT_GLYPH_ERROR"

        It 'sets the managed column from state ownership, not the status word'
            software::status_of() { printf 'configured'; }

            state::own git
            When call software::status_report git tree
            The status should be success
            The line 1 of stdout should equal 'name  available  installed  managed'
            The line 2 of stdout should equal "$(sw_row git "$check" "$check" "$check")"
            The line 3 of stdout should equal "$(sw_row tree "$check" "$check" "$cross")"
            The stderr should be blank
        End

        It 'treats a provisioner name as unknown software and reports a read error'
            # Provisioners are no longer special-cased: a provisioner name resolves to
            # no software file, so status_of fails for it like any other unknown name.
            software::status_of() {
                [[ "$1" != workspace ]] && printf 'configured' && return 0

                return 2
            }

            When call software::status_report git workspace
            The status should equal 2
            The line 2 of stdout should include 'git'
            The stderr should include "could not read the status of 'workspace'"
        End

        It 'reports every discovered piece when none are named'
            software::discover() { printf 'alpha\nbeta\n'; }
            software::status_of() { printf 'available'; }

            When call software::status_report
            The status should be success
            The line 1 of stdout should include 'available  installed  managed'
            The line 2 of stdout should include 'alpha'
            The line 3 of stdout should include 'beta'
            The stderr should be blank
        End

        It 'reports an error and returns the worst status for a piece it cannot read'
            software::status_of() {
                [[ "$1" == ghost ]] && return 2

                printf 'configured'
            }

            When call software::status_report ok ghost
            The status should equal 2
            The line 2 of stdout should include 'ok'
            The stderr should include "could not read the status of 'ghost'"
        End

    End

End
