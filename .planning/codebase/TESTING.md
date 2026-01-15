# Testing Patterns

**Analysis Date:** 2026-01-15

## Test Framework

**Runner:**
- BATS (Bash Automated Testing System)
- Package: `pkgs.bats` in `flake.nix`

**Assertion Library:**
- Custom assertions in `tests/test_helper.bash`
- Built-in BATS: `[ "$status" -eq 0 ]`, `[[ "$output" =~ pattern ]]`

**Run Commands:**
```bash
bats tests/                           # Run all tests
bats tests/logging.bats               # Single file
bats --verbose-run tests/             # Verbose output
bats --timing tests/                  # With timing
```

## Test File Organization

**Location:**
- All tests in `tests/` directory
- Co-located helper: `tests/test_helper.bash`

**Naming:**
- `{feature}.bats` for feature tests
- `test_helper.bash` for shared utilities
- `verify-server.sh` for post-install verification

**Structure:**
```
tests/
├── test_helper.bash      # Shared fixtures & assertions (296 lines)
├── bootstrap.bats        # Bootstrap script tests (433 lines)
├── hcloud-provision.bats # Provisioning tests (458 lines)
├── logging.bats          # Logging library tests (273 lines)
├── health-check.bats     # Health check tests (331 lines)
├── edge-cases.bats       # Edge case scenarios (326 lines)
├── flake.bats            # Flake validation tests (244 lines)
├── secure-ssh-key.bats   # SSH key helper tests (201 lines)
├── verify-server.sh      # Post-install verification (433 lines)
└── README.md             # Testing documentation
```

## Test Structure

**Suite Organization:**
```bash
#!/usr/bin/env bats
# ABOUTME: Tests for lib/logging.sh
# ABOUTME: Validates logging functions, timers, and log file creation

load 'test_helper'

setup() {
    common_setup
    export LOG_DIR="${TEST_TEMP_DIR}/logs"
    export NO_COLOR=1
    source "${PROJECT_ROOT}/lib/logging.sh"
}

teardown() {
    common_teardown
}

@test "init_logging creates log directory" {
    init_logging "test-script"
    assert_dir_exists "${LOG_DIR}"
}

@test "log_info outputs message to stdout" {
    init_logging "test"
    run log_info "test message"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "test message"
    assert_contains "${output}" "[INFO]"
}
```

**Patterns:**
- `load 'test_helper'` for shared utilities
- `setup()` for per-test initialization
- `teardown()` for cleanup
- `run` command for capturing output
- `[ "$status" -eq 0 ]` for exit code checks

## Mocking

**Framework:**
- Custom mocking functions in `test_helper.bash`

**Patterns:**
```bash
# Mock sudo to run without privileges
mock_sudo() {
    sudo() {
        "$@"
    }
    export -f sudo
}

# Mock system commands
mock_system_commands() {
    apt-get() { echo "mock apt-get $*"; }
    systemctl() { echo "mock systemctl $*"; }
    export -f apt-get systemctl
}

# Create mock SSH key pair
create_mock_ssh_key() {
    local key_path="${1:-${TEST_TEMP_DIR}/id_test}"
    echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "${key_path}"
    echo "mock-public-key" > "${key_path}.pub"
}
```

**What to Mock:**
- System commands (apt-get, systemctl, curl)
- sudo (run without privileges)
- SSH operations
- Network calls

**What NOT to Mock:**
- Pure bash functions
- File system operations in temp directory
- Internal library functions

## Fixtures and Factories

**Test Data:**
```bash
# Setup temp directory
setup_temp_dir() {
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
}

# Teardown temp directory
teardown_temp_dir() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Common setup
common_setup() {
    setup_temp_dir
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "${HOME}"
    export NO_COLOR=1
}
```

**Location:**
- All in `tests/test_helper.bash`
- Temp directories created per-test
- Cleaned up in teardown

## Coverage

**Requirements:**
- No enforced coverage target
- Focus on critical paths and edge cases

**Test Count:**
- 281 tests across 7 test files
- Coverage includes: logging, bootstrap, provisioning, health checks, edge cases

**View Coverage:**
```bash
bats tests/              # Run all tests
bats --count tests/      # Count tests
```

## Test Types

**Unit Tests:**
- Test individual functions in isolation
- Mock all external dependencies
- Fast execution (<100ms per test)
- Examples: `logging.bats`

**Integration Tests:**
- Test multiple modules together
- Mock only external boundaries
- Examples: `bootstrap.bats`

**Edge Case Tests:**
- Boundary conditions and error paths
- Unicode handling, special characters
- Examples: `edge-cases.bats`

**E2E Tests:**
- Not used (no live system tests)
- Philosophy: All tests use mocks and temp files

## Common Patterns

**Async Testing:**
```bash
@test "function handles timeout" {
    run timeout 5 some_function
    [ "$status" -eq 0 ]
}
```

**Error Testing:**
```bash
@test "function fails on invalid input" {
    run some_function "invalid"
    [ "$status" -ne 0 ]
    assert_contains "${output}" "error"
}
```

**Output Verification:**
```bash
@test "function outputs expected message" {
    run some_function
    [ "$status" -eq 0 ]
    assert_contains "${output}" "expected text"
    assert_not_contains "${output}" "error"
}
```

**Snapshot Testing:**
- Not used in this codebase

## Custom Assertions

**From `test_helper.bash`:**
```bash
assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ ! "${haystack}" == *"${needle}"* ]]; then
        echo "Expected '${haystack}' to contain '${needle}'"
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        echo "Expected file to exist: ${path}"
        return 1
    fi
}

assert_dir_exists() {
    local path="$1"
    if [[ ! -d "${path}" ]]; then
        echo "Expected directory to exist: ${path}"
        return 1
    fi
}
```

---

*Testing analysis: 2026-01-15*
*Update when test patterns change*
