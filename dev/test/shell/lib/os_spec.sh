# Specs for OS detection. Each example points OS_RELEASE_FILE at a fixture under
# the shellspec temp base so the real /etc/os-release is never read.
Describe 'lib/os.sh'
    TEST_FLAG=true
    Include lib/os.sh

    # A fixture os-release with a plain field, a quoted field, and a value that
    # contains spaces, so the quote stripping can be exercised.
    setup() {
        OS_RELEASE_FILE="$SHELLSPEC_TMPBASE/os-release"
        {
            printf 'ID=ubuntu\n'
            printf 'VERSION_ID="26.04"\n'
            printf 'PRETTY_NAME="Ubuntu 26.04 LTS"\n'
        } >"$OS_RELEASE_FILE"
        export OS_RELEASE_FILE
    }
    BeforeEach 'setup'

    # ==========================================================================
    # os::_release_file
    # ==========================================================================
    Describe 'os::_release_file'

        It 'returns OS_RELEASE_FILE when it is set'
            When call os::_release_file
            The status should be success
            The stdout should equal "$OS_RELEASE_FILE"
            The stderr should be blank
        End

        It 'falls back to /etc/os-release when OS_RELEASE_FILE is unset'
            OS_RELEASE_FILE=''
            When call os::_release_file
            The status should be success
            The stdout should equal '/etc/os-release'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # os::_field
    # ==========================================================================
    Describe 'os::_field'

        It 'reads a single field from the os-release file'
            When call os::_field ID
            The status should be success
            The stdout should equal 'ubuntu'
            The stderr should be blank
        End

        It 'strips the surrounding quotes from a quoted value'
            When call os::_field PRETTY_NAME
            The status should be success
            The stdout should equal 'Ubuntu 26.04 LTS'
            The stderr should be blank
        End

        It 'fails when the os-release file is not readable'
            OS_RELEASE_FILE="$SHELLSPEC_TMPBASE/missing"
            When call os::_field ID
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # os::id
    # ==========================================================================
    Describe 'os::id'

        It 'reports the OS id from the ID field'
            When call os::id
            The status should be success
            The stdout should equal 'ubuntu'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # os::version
    # ==========================================================================
    Describe 'os::version'

        It 'reports the OS version from the VERSION_ID field'
            When call os::version
            The status should be success
            The stdout should equal '26.04'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # os::file_token
    # ==========================================================================
    Describe 'os::file_token'

        It 'joins the id and version into a filename token'
            When call os::file_token
            The status should be success
            The stdout should equal 'ubuntu_26.04'
            The stderr should be blank
        End

    End

End
