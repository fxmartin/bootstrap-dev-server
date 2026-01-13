# Test Suite for Bootstrap Dev Server

This directory contains BATS (Bash Automated Testing System) tests for the bootstrap-dev-server project.

## Prerequisites

Install BATS:
```bash
# Via Nix (recommended)
nix-shell -p bats

# Via Homebrew (macOS)
brew install bats-core

# Via apt (Ubuntu/Debian)
sudo apt install bats
```

## Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/logging.bats
bats tests/bootstrap.bats
bats tests/hcloud-provision.bats
bats tests/health-check.bats
bats tests/secure-ssh-key.bats

# Run with verbose output
bats --verbose-run tests/

# Run with timing information
bats --timing tests/
```

## Test Files

| File | Description |
|------|-------------|
| `test_helper.bash` | Shared test utilities and setup/teardown functions |
| `logging.bats` | Tests for `lib/logging.sh` logging library |
| `bootstrap.bats` | Tests for `bootstrap-dev-server.sh` functions |
| `hcloud-provision.bats` | Tests for `hcloud-provision.sh` provisioning script |
| `health-check.bats` | Tests for `scripts/health-check.sh` system checks |
| `secure-ssh-key.bats` | Tests for `scripts/secure-ssh-key.sh` key helper |

## Test Structure

Each test file follows this structure:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
    common_setup
    # Test-specific setup
}

teardown() {
    common_teardown
}

@test "descriptive test name" {
    # Test implementation
    run some_command
    [ "$status" -eq 0 ]
    assert_contains "${output}" "expected"
}
```

## Test Helper Functions

The `test_helper.bash` provides:

- `common_setup` / `common_teardown` - Standard setup/teardown
- `setup_temp_dir` / `teardown_temp_dir` - Temporary directory management
- `assert_contains` / `assert_not_contains` - String assertions
- `assert_file_exists` / `assert_dir_exists` - File system assertions
- `create_mock_ssh_key` - Create mock SSH keys for testing
- `setup_mock_environment` - Configure test environment

## Writing New Tests

1. Create a new `.bats` file in the `tests/` directory
2. Load the test helper: `load 'test_helper'`
3. Implement `setup()` and `teardown()` functions
4. Write tests using `@test "name" { ... }` blocks

Example:
```bash
@test "my function does something" {
    # Arrange
    local input="test"

    # Act
    run my_function "${input}"

    # Assert
    [ "$status" -eq 0 ]
    assert_contains "${output}" "expected result"
}
```

## Testing Philosophy

1. **Unit tests** - Test individual functions in isolation
2. **Integration tests** - Test functions working together
3. **No live system tests** - All tests use mocks and temporary files
4. **Fast execution** - Tests should complete in seconds
5. **Idempotent** - Tests clean up after themselves

## Coverage

Tests aim to cover:

- All configuration variables and defaults
- All public functions
- All error paths
- Edge cases (empty input, special characters, etc.)
- Security-sensitive code (SSH, credentials, etc.)
