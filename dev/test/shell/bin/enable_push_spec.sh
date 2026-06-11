# Specs for the enable-push tool. TEST_FLAG keeps the enable_push::* functions
# non-readonly so the spec can Include the file and stub the git/gpg/command
# calls; the script's own Execute guard keeps enable_push::main from running on
# Include. helper::isolate points HOME at a fresh temp directory so the SSH
# config and prompt-driven paths never read the developer's real ~/.ssh.
Describe 'bin/enable-push'
    TEST_FLAG=true
    Include bin/enable-push

    setup() {
        helper::isolate
    }
    BeforeEach 'setup'

    # ==========================================================================
    # enable_push::remote_host
    # ==========================================================================
    Describe 'enable_push::remote_host'

        It 'returns the host from an HTTPS URL'
            When call enable_push::remote_host 'https://github.com/o/r.git'
            The status should be success
            The stdout should equal 'github.com'
            The stderr should be blank
        End

        It 'returns the host from an scp-style SSH URL'
            When call enable_push::remote_host 'git@github.com:o/r.git'
            The status should be success
            The stdout should equal 'github.com'
            The stderr should be blank
        End

        It 'returns the host from an ssh:// URL'
            When call enable_push::remote_host 'ssh://git@github.com/o/r.git'
            The status should be success
            The stdout should equal 'github.com'
            The stderr should be blank
        End

        It 'returns the alias from a bare host alias URL'
            When call enable_push::remote_host 'gh:o/r'
            The status should be success
            The stdout should equal 'gh'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::ssh_config_content
    # ==========================================================================
    Describe 'enable_push::ssh_config_content'

        It 'flattens an included config relative to the including file'
            mkdir -p "$SHELLSPEC_TMPBASE/ssh/config.d"
            printf 'Host gh\n  HostName github.com\nInclude config.d/extra\n' >"$SHELLSPEC_TMPBASE/ssh/config"
            printf 'Host gl\n  HostName gitlab.com\n' >"$SHELLSPEC_TMPBASE/ssh/config.d/extra"

            When call enable_push::ssh_config_content "$SHELLSPEC_TMPBASE/ssh/config"
            The status should be success
            The stdout should include 'HostName github.com'
            The stdout should include 'HostName gitlab.com'
            The stderr should be blank
        End

        It 'contributes nothing for an unreadable file'
            When call enable_push::ssh_config_content "$SHELLSPEC_TMPBASE/missing"
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::emit_host
    # ==========================================================================
    Describe 'enable_push::emit_host'

        It 'emits the alias and identity file when the hostname matches'
            expected="$(printf 'gh\t~/.ssh/gh')"
            When call enable_push::emit_host github.com github.com '~/.ssh/gh' gh
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

        It 'emits nothing when the hostname does not match'
            When call enable_push::emit_host github.com gitlab.com '~/.ssh/gl' gl
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'skips wildcard patterns and emits the first concrete alias'
            expected="$(printf 'gh\t')"
            When call enable_push::emit_host github.com github.com '' '*' gh
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::matching_ssh_hosts
    # ==========================================================================
    Describe 'enable_push::matching_ssh_hosts'

        It 'emits the alias and identity file of a matching Host block'
            expected="$(printf 'gh\t~/.ssh/gh')"
            Data
              #|Host gh
              #|  HostName github.com
              #|  IdentityFile ~/.ssh/gh
              #|Host gl
              #|  HostName gitlab.com
            End
            When call enable_push::matching_ssh_hosts github.com
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

        It 'matches the key=value spelling and keeps the first identity file'
            expected="$(printf 'gh\t~/.ssh/first')"
            Data
              #|Host=gh
              #|  HostName=github.com
              #|  IdentityFile=~/.ssh/first
              #|  IdentityFile=~/.ssh/second
            End
            When call enable_push::matching_ssh_hosts github.com
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

        It 'emits nothing when no Host block matches'
            Data
              #|Host gl
              #|  HostName gitlab.com
            End
            When call enable_push::matching_ssh_hosts github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::confirm
    # ==========================================================================
    Describe 'enable_push::confirm'

        It 'succeeds on an affirmative reply'
            Data 'y'
            When call enable_push::confirm 'Use this host?'
            The status should be success
            The stdout should be blank
            The stderr should include 'Use this host? [y/N]'
        End

        It 'fails on a negative reply'
            Data 'n'
            When call enable_push::confirm 'Use this host?'
            The status should be failure
            The stdout should be blank
            The stderr should include 'Use this host? [y/N]'
        End

    End

    # ==========================================================================
    # enable_push::menu
    # ==========================================================================
    Describe 'enable_push::menu'

        It 'prints the chosen one-based index on a valid selection'
            Data '2'
            When call enable_push::menu 'Pick one:' a b c
            The status should be success
            The stdout should equal '2'
            The stderr should include 'Pick one:'
        End

        It 'fails on the skip selection'
            Data '0'
            When call enable_push::menu 'Pick one:' a b c
            The status should be failure
            The stdout should be blank
            The stderr should include 'keep current / skip'
        End

        It 'fails on an out-of-range selection'
            Data '9'
            When call enable_push::menu 'Pick one:' a b c
            The status should be failure
            The stdout should be blank
            The stderr should include 'Pick one:'
        End

        It 'fails on a non-numeric selection'
            Data 'x'
            When call enable_push::menu 'Pick one:' a b c
            The status should be failure
            The stdout should be blank
            The stderr should include 'Pick one:'
        End

    End

    # ==========================================================================
    # enable_push::remote_path
    # ==========================================================================
    Describe 'enable_push::remote_path'

        It 'returns the path from an HTTPS URL'
            When call enable_push::remote_path 'https://github.com/o/r.git'
            The status should be success
            The stdout should equal 'o/r.git'
            The stderr should be blank
        End

        It 'returns the path from an scp-style SSH URL'
            When call enable_push::remote_path 'git@github.com:o/r.git'
            The status should be success
            The stdout should equal 'o/r.git'
            The stderr should be blank
        End

        It 'returns the path from a bare host alias URL'
            When call enable_push::remote_path 'gh:o/r'
            The status should be success
            The stdout should equal 'o/r'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::configure_remote
    # ==========================================================================
    Describe 'enable_push::configure_remote'

        seed_config() {
            mkdir -p "$HOME/.ssh"
        }
        BeforeEach 'seed_config'

        It 'leaves the remote unchanged when no SSH host maps to the remote'
            git() { printf 'git %s\n' "$*"; }

            When call enable_push::configure_remote "$SHELLSPEC_TMPBASE/repo" 'https://github.com/o/r.git'
            The status should be success
            The stdout should be blank
            The stderr should include 'no SSH host'
        End

        It 'rewrites the remote to the SSH alias when one host matches and is confirmed'
            git() { printf 'git %s\n' "$*"; }
            printf 'Host gh\n  HostName github.com\n  IdentityFile ~/.ssh/gh\n' >"$HOME/.ssh/config"

            Data 'y'
            When call enable_push::configure_remote "$SHELLSPEC_TMPBASE/repo" 'https://github.com/o/r.git'
            The status should be success
            The stdout should include 'remote set-url origin gh:o/r.git'
            The stdout should include 'set origin remote to gh:o/r.git'
            The stderr should include 'Use SSH host'
        End

        It 'leaves the remote unchanged when the single match is declined'
            git() { printf 'git %s\n' "$*"; }
            printf 'Host gh\n  HostName github.com\n  IdentityFile ~/.ssh/gh\n' >"$HOME/.ssh/config"

            Data 'n'
            When call enable_push::configure_remote "$SHELLSPEC_TMPBASE/repo" 'https://github.com/o/r.git'
            The status should be success
            The stdout should include 'origin remote unchanged'
            The stderr should include 'Use SSH host'
        End

        It 'offers a menu and rewrites the remote when several hosts match'
            git() { printf 'git %s\n' "$*"; }
            printf 'Host gh\n  HostName github.com\nHost gh2\n  HostName github.com\n' >"$HOME/.ssh/config"

            Data '1'
            When call enable_push::configure_remote "$SHELLSPEC_TMPBASE/repo" 'https://github.com/o/r.git'
            The status should be success
            The stdout should include 'remote set-url origin gh:o/r.git'
            The stderr should include 'Select the SSH host'
        End

    End

    # ==========================================================================
    # enable_push::gpg_signing_keys
    # ==========================================================================
    Describe 'enable_push::gpg_signing_keys'

        It 'pairs each primary fingerprint with its primary user id'
            expected="$(printf 'ABCDEF0123456789\tAda Lovelace <ada@example.com>')"
            Data
              #|sec:u:4096:1:0000:::::::::::
              #|fpr:::::::::ABCDEF0123456789::
              #|uid:u::::::::Ada Lovelace <ada@example.com>::
            End
            When call enable_push::gpg_signing_keys
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

        It 'emits one line per secret key'
            expected="$(printf 'AAAA\tAda <ada@example.com>\nBBBB\tBob <bob@example.com>')"
            Data
              #|sec:u:4096:1:0000:::::::::::
              #|fpr:::::::::AAAA::
              #|uid:u::::::::Ada <ada@example.com>::
              #|sec:u:4096:1:1111:::::::::::
              #|fpr:::::::::BBBB::
              #|uid:u::::::::Bob <bob@example.com>::
            End
            When call enable_push::gpg_signing_keys
            The status should be success
            The stdout should equal "$expected"
            The stderr should be blank
        End

        It 'emits nothing for an empty keyring'
            Data ''
            When call enable_push::gpg_signing_keys
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # enable_push::configure_signing_key
    # ==========================================================================
    Describe 'enable_push::configure_signing_key'

        It 'skips signing when gpg is not installed'
            command() { return 1; }

            When call enable_push::configure_signing_key "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'gpg is not installed'
            The stderr should be blank
        End

        It 'skips signing when the keyring holds no secret key'
            command() { :; }
            gpg() { :; }
            git() { printf 'git %s\n' "$*"; }

            When call enable_push::configure_signing_key "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'no GPG secret key'
            The stderr should be blank
        End

        It 'sets the signing key and turns on signing when a key is chosen'
            command() { :; }
            git() { printf 'git %s\n' "$*"; }

            gpg() {
                printf 'sec:u:4096:1:0000:::::::::::\n'
                printf 'fpr:::::::::ABCDEF0123456789::\n'
                printf 'uid:u::::::::Ada Lovelace <ada@example.com>::\n'
            }

            Data '1'
            When call enable_push::configure_signing_key "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'user.signingKey ABCDEF0123456789'
            The stdout should include 'commit.gpgsign true'
            The stdout should include 'tag.gpgsign true'
            The stdout should include 'configured commit and tag signing with ABCDEF0123456789'
            The stderr should include 'Select a GPG key'
        End

        It 'leaves signing unchanged when the selection is skipped'
            command() { :; }
            git() { printf 'git %s\n' "$*"; }

            gpg() {
                printf 'sec:u:4096:1:0000:::::::::::\n'
                printf 'fpr:::::::::ABCDEF0123456789::\n'
                printf 'uid:u::::::::Ada Lovelace <ada@example.com>::\n'
            }

            Data '0'
            When call enable_push::configure_signing_key "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'GPG signing unchanged'
            The stdout should not include 'user.signingKey'
            The stderr should include 'Select a GPG key'
        End

    End

    # ==========================================================================
    # enable_push::prompt_value
    # ==========================================================================
    Describe 'enable_push::prompt_value'

        It 'returns the entered value over the default'
            Data 'Ada'
            When call enable_push::prompt_value 'Git user.name' 'Bob'
            The status should be success
            The stdout should equal 'Ada'
            The stderr should include 'Git user.name [Bob]'
        End

        It 'returns the default when the reply is empty'
            When call enable_push::prompt_value 'Git user.name' 'Bob'
            The status should be success
            The stdout should equal 'Bob'
            The stderr should include 'Git user.name [Bob]'
        End

    End

    # ==========================================================================
    # enable_push::configure_identity
    # ==========================================================================
    Describe 'enable_push::configure_identity'

        identity_git() {
            git() {
                case "$*" in
                    *'config user.name') printf 'Old Name\n' ;;
                    *'config user.email') printf 'old@example.com\n' ;;
                    *) printf 'git %s\n' "$*" ;;
                esac
            }
        }
        BeforeEach 'identity_git'

        It 'writes the local identity when the answers differ from the global defaults'
            Data
              #|New Name
              #|new@example.com
            End
            When call enable_push::configure_identity "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'config --local user.name New Name'
            The stdout should include 'config --local user.email new@example.com'
            The stdout should include 'set user.name to New Name'
            The stdout should include 'set user.email to new@example.com'
            The stderr should include 'Git user.name [Old Name]'
        End

        It 'leaves the local identity alone when the global defaults are kept'
            Data
              #|
              #|
            End
            When call enable_push::configure_identity "$SHELLSPEC_TMPBASE/repo"
            The status should be success
            The stdout should include 'user.name unchanged'
            The stdout should include 'user.email unchanged'
            The stdout should not include 'config --local'
            The stderr should include 'Git user.email [old@example.com]'
        End

    End

    # ==========================================================================
    # enable_push::main
    # ==========================================================================
    Describe 'enable_push::main'

        It 'fails when git is not installed'
            command() { return 1; }

            When call enable_push::main
            The status should equal 1
            The stdout should include 'Repository'
            The stderr should include 'git is not installed'
        End

        It 'fails when the repository has no origin remote'
            command() { :; }
            git() { return 1; }

            When call enable_push::main
            The status should equal 1
            The stdout should include 'Repository'
            The stderr should include 'no origin remote'
        End

        It 'runs every configuration step when git and an origin remote are present'
            command() { :; }
            git() { printf 'https://github.com/o/r.git\n'; }
            enable_push::configure_remote() { printf 'remote[%s]\n' "$*"; }
            enable_push::configure_signing_key() { printf 'signing[%s]\n' "$*"; }
            enable_push::configure_identity() { printf 'identity[%s]\n' "$*"; }

            When call enable_push::main
            The status should be success
            The stdout should include 'remote['
            The stdout should include 'signing['
            The stdout should include 'identity['
            The stderr should be blank
        End

    End

End
