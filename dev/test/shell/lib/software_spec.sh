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
            # The provisioner executable sits at the libexec root, not under a token's
            # software/ directory, so discovery must never list it as software.
            printf '#!/usr/bin/env bash\n' >"$LIBEXEC_DIR/provisioner.sh"
        }
        BeforeEach 'setup_libexec'

        It 'lists the per-OS software only, ignoring the provisioner and other libexec files'
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

    # ==========================================================================
    # software::update_package_manager
    # ==========================================================================
    Describe 'software::update_package_manager'

        output::log() { :; }
        # Fix the OS token so the refresh resolves a known system-upgrade script.
        os::file_token() { printf 'ubuntu_26.04'; }

        setup_libexec() {
            LIBEXEC_DIR="$SHELLSPEC_TMPBASE/libexec"
            rm -rf "$LIBEXEC_DIR"
            mkdir -p "$LIBEXEC_DIR/ubuntu_26.04"
            printf '#!/usr/bin/env bash\nprintf "system-upgrade\\n"\n' >"$LIBEXEC_DIR/ubuntu_26.04/system-upgrade"
            chmod +x "$LIBEXEC_DIR/ubuntu_26.04/system-upgrade"
        }
        BeforeEach 'setup_libexec'

        It 'invokes the host OS token system-upgrade script'
            When call software::update_package_manager
            The status should be success
            The stdout should equal 'system-upgrade'
            The stderr should be blank
        End

        It 'announces the refresh on stderr'
            output::log() { printf 'log %s\n' "$1" >&2; }

            When call software::update_package_manager
            The status should be success
            The stdout should equal 'system-upgrade'
            The stderr should include 'Updating the package manager'
        End

        It 'propagates the system-upgrade exit status'
            printf '#!/usr/bin/env bash\nexit 5\n' >"$LIBEXEC_DIR/ubuntu_26.04/system-upgrade"
            chmod +x "$LIBEXEC_DIR/ubuntu_26.04/system-upgrade"

            When call software::update_package_manager
            The status should equal 5
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::install
    # ==========================================================================
    Describe 'software::install'

        output::log() { :; }
        software::run() { printf 'run %s %s\n' "$1" "$2"; }
        # The package-manager refresh has its own block; here it is a no-op so the
        # staging assertions read only the per-piece calls. A placement test below
        # makes it emit a marker to pin where it runs.
        software::update_package_manager() { :; }

        It 'stages software inputs, then install-and-configure, across every piece'
            When call software::install alpha beta
            The status should be success
            The line 1 of stdout should equal 'run alpha step-install-inputs'
            The line 2 of stdout should equal 'run beta step-install-inputs'
            The line 3 of stdout should equal 'run alpha step-install'
            The line 4 of stdout should equal 'run beta step-install'
            The stderr should be blank
        End

        It 'refreshes the package manager after the inputs and before any install'
            # Emit a marker from the refresh so its position is pinned: it must run
            # after every piece's inputs and before the first install.
            software::update_package_manager() { printf 'refresh\n'; }

            When call software::install alpha beta
            The status should be success
            The line 1 of stdout should equal 'run alpha step-install-inputs'
            The line 2 of stdout should equal 'run beta step-install-inputs'
            The line 3 of stdout should equal 'refresh'
            The line 4 of stdout should equal 'run alpha step-install'
            The line 5 of stdout should equal 'run beta step-install'
            The stderr should be blank
        End

        It 'records a failing package-manager refresh in the worst status and still installs'
            software::update_package_manager() { return 6; }

            When call software::install alpha
            The status should equal 6
            The stdout should include 'run alpha step-install'
            The stderr should be blank
        End

        It 'drops a piece from the install phase when its inputs step fails'
            software::run() {
                [[ "$1" == broken && "$2" == step-install-inputs ]] && return 1

                printf 'run %s %s\n' "$1" "$2"
            }

            When call software::install ok broken
            The status should equal 1
            The line 1 of stdout should equal 'run ok step-install-inputs'
            The line 2 of stdout should equal 'run ok step-install'
            The stdout should not include 'run broken step-install'
            The stderr should be blank
        End

        It 'skips the package-manager refresh and install phase when every piece is dropped'
            software::update_package_manager() { printf 'refresh\n'; }
            software::run() {
                printf 'run %s %s\n' "$1" "$2"
                [[ "$2" == step-install-inputs ]] && return 1

                return 0
            }

            When call software::install alpha
            The status should equal 1
            The stdout should equal 'run alpha step-install-inputs'
            The stdout should not include 'refresh'
            The stderr should be blank
        End

        It 'continues past a failing install-and-configure step and returns the worst status across phases'
            software::run() {
                [[ "$1" == a && "$2" == step-install-inputs ]] && return 2
                [[ "$1" == b && "$2" == step-install ]] && return 5

                printf 'run %s %s\n' "$1" "$2"
            }

            When call software::install a b
            The status should equal 5
            The line 1 of stdout should equal 'run b step-install-inputs'
            The stdout should not include 'run a '
            The stderr should be blank
        End

        It 'skips with a message when no software is given'
            output::log() { printf 'log %s\n' "$1" >&2; }

            When call software::install
            The status should be success
            The stdout should be blank
            The stderr should include 'nothing to set up'
        End

    End

    # ==========================================================================
    # software::uninstall
    # ==========================================================================
    Describe 'software::uninstall'

        output::log() { :; }
        software::run() { printf 'run %s %s\n' "$1" "$2"; }

        It 'stages software inputs, then unconfigure-and-uninstall across every piece'
            When call software::uninstall alpha beta
            The status should be success
            The line 1 of stdout should equal 'run alpha step-uninstall-inputs'
            The line 2 of stdout should equal 'run beta step-uninstall-inputs'
            The line 3 of stdout should equal 'run alpha step-uninstall'
            The line 4 of stdout should equal 'run beta step-uninstall'
            The stderr should be blank
        End

        It 'drops a piece from removal when its inputs step fails'
            software::run() {
                [[ "$1" == broken && "$2" == step-uninstall-inputs ]] && return 1

                printf 'run %s %s\n' "$1" "$2"
            }

            When call software::uninstall ok broken
            The status should equal 1
            The line 1 of stdout should equal 'run ok step-uninstall-inputs'
            The line 2 of stdout should equal 'run ok step-uninstall'
            The stdout should not include 'run broken step-uninstall'
            The stderr should be blank
        End

        It 'continues past a failing removal and returns the worst status'
            software::run() {
                [[ "$1" == broken && "$2" == step-uninstall ]] && return 5

                printf 'run %s %s\n' "$1" "$2"
            }

            When call software::uninstall ok broken
            The status should equal 5
            The stdout should include 'run ok step-uninstall'
            The stderr should be blank
        End

        It 'skips with a message when no software is given'
            output::log() { printf 'log %s\n' "$1" >&2; }

            When call software::uninstall
            The status should be success
            The stdout should be blank
            The stderr should include 'No software to remove'
        End

    End

    # ==========================================================================
    # software::install::pick
    # ==========================================================================
    Describe 'software::install::pick'

        software::description_of() { printf 'desc'; }

        menu::select() {
            local entry

            for entry in "$@"
            do
                printf '%s\n' "$entry"
            done
        }

        It 'skips unavailable software and pre-ticks every available piece with no prior state'
            software::discover() { printf 'alpha\nbeta\ngamma\n'; }

            software::status_of() {
                case "$1" in
                    gamma) printf 'unavailable' ;;
                    *) printf 'available' ;;
                esac
            }
            state::owned() { return 1; }

            When call software::install::pick
            The status should be success
            The line 1 of stdout should equal "$(printf '1\talpha\tdesc')"
            The line 2 of stdout should equal "$(printf '1\tbeta\tdesc')"
            The stderr should be blank
        End

        It 'pre-ticks only the owned software when a previous run recorded some'
            software::discover() { printf 'alpha\nbeta\n'; }
            software::status_of() { printf 'available'; }
            state::owned() { [[ "$1" == alpha ]]; }

            When call software::install::pick
            The status should be success
            The line 1 of stdout should equal "$(printf '1\talpha\tdesc')"
            The line 2 of stdout should equal "$(printf '0\tbeta\tdesc')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # software::uninstall::pick
    # ==========================================================================
    Describe 'software::uninstall::pick'

        software::description_of() { printf 'desc'; }

        menu::select() {
            local entry

            for entry in "$@"
            do
                printf '%s\n' "$entry"
            done
        }

        It 'offers every installed piece unticked, never pre-ticking'
            software::discover() { printf 'alpha\nbeta\ngamma\ndelta\n'; }

            software::status_of() {
                case "$1" in
                    delta) printf 'available' ;;
                    *) printf 'configured' ;;
                esac
            }

            When call software::uninstall::pick
            The status should be success
            The line 1 of stdout should equal "$(printf '0\talpha\tconfigured  desc')"
            The line 2 of stdout should equal "$(printf '0\tbeta\tconfigured  desc')"
            The line 3 of stdout should equal "$(printf '0\tgamma\tconfigured  desc')"
            The stderr should be blank
        End

        It 'offers a foreign install unticked, labelled with its status'
            software::discover() { printf 'alpha\n'; }
            software::status_of() { printf 'unmanaged'; }

            When call software::uninstall::pick
            The status should be success
            The stdout should equal "$(printf '0\talpha\tunmanaged  desc')"
            The stderr should be blank
        End

        It 'prints nothing and skips the menu when nothing is removable'
            software::discover() { printf 'alpha\n'; }
            software::status_of() { printf 'available'; }
            menu::select() { printf 'MENU CALLED\n'; }

            When call software::uninstall::pick
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'labels the menu as an uninstall menu'
            software::discover() { printf 'alpha\n'; }
            software::status_of() { printf 'installed'; }
            menu::select() { printf '%s\n' "$MENU_PROMPT"; }

            When call software::uninstall::pick
            The status should be success
            The stdout should include 'UNINSTALL'
            The stderr should be blank
        End

    End

End
