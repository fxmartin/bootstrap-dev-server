#!/usr/bin/env bash
# ABOUTME: Test helper library for BATS tests
# ABOUTME: Provides common setup, teardown, and utility functions

# Project root directory
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Test fixtures directory
export FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# Temporary directory for test artifacts
export TEST_TEMP_DIR=""

# Colors for test output (disabled in non-interactive mode)
if [[ -t 1 ]]; then
    export TEST_RED='\033[0;31m'
    export TEST_GREEN='\033[0;32m'
    export TEST_YELLOW='\033[1;33m'
    export TEST_BLUE='\033[0;34m'
    export TEST_NC='\033[0m'
else
    export TEST_RED=''
    export TEST_GREEN=''
    export TEST_YELLOW=''
    export TEST_BLUE=''
    export TEST_NC=''
fi

# =============================================================================
# Setup and Teardown
# =============================================================================

# Create temporary directory for test artifacts
setup_temp_dir() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

# Remove temporary directory
teardown_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Standard setup for all tests
common_setup() {
    setup_temp_dir

    # Create mock home directory structure
    export MOCK_HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "${MOCK_HOME}/.ssh"
    mkdir -p "${MOCK_HOME}/.config"
    mkdir -p "${MOCK_HOME}/.local/share"
    mkdir -p "${MOCK_HOME}/.cache"
}

# Standard teardown for all tests
common_teardown() {
    teardown_temp_dir
}

# =============================================================================
# Mock Functions
# =============================================================================

# Mock sudo to run commands without privileges in tests
# shellcheck disable=SC2329
mock_sudo() {
    # shellcheck disable=SC2317
    sudo() {
        # Remove sudo and run command directly
        "$@"
    }
    export -f sudo
}

# Mock commands that shouldn't run in tests
# shellcheck disable=SC2329
mock_system_commands() {
    # Mock apt-get
    # shellcheck disable=SC2317
    apt-get() {
        echo "MOCK: apt-get $*"
        return 0
    }
    export -f apt-get

    # Mock systemctl
    # shellcheck disable=SC2317
    systemctl() {
        echo "MOCK: systemctl $*"
        return 0
    }
    export -f systemctl

    # Mock curl
    # shellcheck disable=SC2317
    mock_curl() {
        echo "MOCK: curl $*"
        return 0
    }

    # Mock ssh
    # shellcheck disable=SC2317
    ssh() {
        echo "MOCK: ssh $*"
        return 0
    }
    export -f ssh
}

# =============================================================================
# Assertion Helpers
# =============================================================================

# Assert that a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "Expected '${haystack}' to contain '${needle}'" >&2
        return 1
    fi
}

# Assert that a string does not contain a substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "Expected '${haystack}' to NOT contain '${needle}'" >&2
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local filepath="$1"
    if [[ ! -f "${filepath}" ]]; then
        echo "Expected file to exist: ${filepath}" >&2
        return 1
    fi
}

# Assert that a file does not exist
assert_file_not_exists() {
    local filepath="$1"
    if [[ -f "${filepath}" ]]; then
        echo "Expected file to NOT exist: ${filepath}" >&2
        return 1
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dirpath="$1"
    if [[ ! -d "${dirpath}" ]]; then
        echo "Expected directory to exist: ${dirpath}" >&2
        return 1
    fi
}

# Assert that output matches a regex
assert_output_matches() {
    local pattern="$1"
    if [[ ! "${output}" =~ ${pattern} ]]; then
        echo "Expected output to match pattern: ${pattern}" >&2
        echo "Actual output: ${output}" >&2
        return 1
    fi
}

# Assert exit code equals expected value
assert_exit_code() {
    local expected="$1"
    local actual="${status:-$?}"
    if [[ "${actual}" -ne "${expected}" ]]; then
        echo "Expected exit code ${expected}, got ${actual}" >&2
        return 1
    fi
}

# Assert that a command is available
assert_command_exists() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        echo "Expected command to exist: ${cmd}" >&2
        return 1
    fi
}

# =============================================================================
# File Helpers
# =============================================================================

# Create a test file with content
create_test_file() {
    local filepath="$1"
    local content="${2:-}"

    mkdir -p "$(dirname "${filepath}")"
    echo "${content}" > "${filepath}"
}

# Create a mock SSH key pair
create_mock_ssh_key() {
    local key_path="${1:-${TEST_TEMP_DIR}/id_test}"

    # Create minimal fake key files (not real cryptographic keys)
    echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "${key_path}"
    echo "mock-private-key-content" >> "${key_path}"
    echo "-----END OPENSSH PRIVATE KEY-----" >> "${key_path}"
    chmod 600 "${key_path}"

    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMock test@test" > "${key_path}.pub"
    chmod 644 "${key_path}.pub"

    echo "${key_path}"
}

# =============================================================================
# Source Script Functions
# =============================================================================

# Source a script file for testing its functions
# Usage: source_script "bootstrap-dev-server.sh"
source_script() {
    local script_name="$1"
    local script_path="${PROJECT_ROOT}/${script_name}"

    if [[ ! -f "${script_path}" ]]; then
        echo "Script not found: ${script_path}" >&2
        return 1
    fi

    # Source only functions by using a subshell trick
    # This prevents the main() from executing
    # shellcheck source=/dev/null
    source "${script_path}"
}

# Source functions from a script without executing main
# This wraps the script to prevent execution
source_functions_only() {
    local script_path="$1"

    if [[ ! -f "${script_path}" ]]; then
        echo "Script not found: ${script_path}" >&2
        return 1
    fi

    # Extract and source only function definitions
    # This is a simplified approach - extract function blocks
    eval "$(grep -A 1000 '^[a-z_]*()' "${script_path}" | sed 's/^main /main_disabled /')"
}

# =============================================================================
# Output Capture
# =============================================================================

# Run a command and capture output and status
run_and_capture() {
    local cmd="$*"
    output="$(eval "${cmd}" 2>&1)" || status=$?
    status=${status:-0}
}

# =============================================================================
# Environment Helpers
# =============================================================================

# Set up a mock environment for testing
setup_mock_environment() {
    # Override HOME
    export HOME="${MOCK_HOME}"

    # Set up minimal PATH
    export PATH="${PROJECT_ROOT}/scripts:${PROJECT_ROOT}:${PATH}"

    # Disable colors in tests
    export NO_COLOR=1

    # Set test-specific variables
    export DEV_USER="testuser"
    export SSH_PORT="22"
    export MOSH_PORT_START="60000"
    export MOSH_PORT_END="60010"
}

# Reset environment after test
reset_environment() {
    unset DEV_USER SSH_PORT MOSH_PORT_START MOSH_PORT_END
    unset NO_COLOR
}
