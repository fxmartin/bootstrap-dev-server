#!/usr/bin/env bats
# ABOUTME: Tests for scripts/secure-ssh-key.sh
# ABOUTME: Tests SSH key passphrase helper script

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1
}

teardown() {
    common_teardown
}

# =============================================================================
# Script Structure Tests
# =============================================================================

@test "uses set -euo pipefail" {
    run head -10 "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    assert_contains "${output}" "set -euo pipefail"
}

@test "has ABOUTME comment" {
    run head -5 "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    assert_contains "${output}" "ABOUTME"
}

@test "sources logging library when available" {
    run grep "source.*logging.sh" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "has fallback logging when library not found" {
    run grep "Fallback if library not found" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "default key path is ~/.ssh/id_devserver" {
    run grep "DEFAULT_KEY_PATH" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "id_devserver"
}

@test "accepts custom key path as argument" {
    run grep 'KEY_PATH="${1:-' "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Key Existence Check Tests
# =============================================================================

@test "checks if key file exists" {
    run grep '! -f "${KEY_PATH}"' "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "shows error when key not found" {
    run grep "SSH key not found" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "provides generate command when key missing" {
    run grep "ssh-keygen -t ed25519" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Passphrase Detection Tests
# =============================================================================

@test "checks if key has passphrase" {
    run grep 'ssh-keygen -y -P ""' "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "warns when key has no passphrase" {
    run grep "NO passphrase" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "confirms when key already has passphrase" {
    run grep "already has a passphrase" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Passphrase Requirements Tests
# =============================================================================

@test "mentions passphrase requirements" {
    run grep "Passphrase requirements" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "recommends 12+ characters" {
    run grep "12+" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "recommends password manager" {
    run grep "password manager" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Passphrase Addition Tests
# =============================================================================

@test "uses ssh-keygen -p to add passphrase" {
    run grep "ssh-keygen -p -f" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "shows success message after adding passphrase" {
    run grep "Passphrase added successfully" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "handles passphrase addition failure" {
    run grep "Failed to add passphrase" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Agent Integration Tests
# =============================================================================

@test "mentions ssh-add with Keychain" {
    run grep "ssh-add --apple-use-keychain" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "explains Keychain storage" {
    run grep "macOS Keychain" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# User Guidance Tests
# =============================================================================

@test "provides change passphrase command" {
    run grep "To change the passphrase" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "explains AES-256-CTR encryption" {
    run grep "AES-256" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "explains key file protection" {
    run grep "encrypts your private key" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Output Formatting Tests
# =============================================================================

@test "has header banner" {
    run grep "Secure SSH Key" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

@test "uses color codes" {
    run grep "BLUE\|GREEN\|YELLOW\|RED" "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Integration Tests (with mock key)
# =============================================================================

@test "handles key without passphrase" {
    # Create a key without passphrase
    local test_key="${TEST_TEMP_DIR}/test_key"
    ssh-keygen -t ed25519 -f "${test_key}" -N "" -q

    # Verify it has no passphrase (ssh-keygen -y with empty password succeeds)
    run ssh-keygen -y -P "" -f "${test_key}"
    [ "$status" -eq 0 ]
}

@test "detects key with passphrase" {
    # Create a key with passphrase
    local test_key="${TEST_TEMP_DIR}/test_key_protected"
    ssh-keygen -t ed25519 -f "${test_key}" -N "testpassphrase" -q

    # Verify it has passphrase (ssh-keygen -y with empty password fails with non-zero exit)
    run ssh-keygen -y -P "" -f "${test_key}"
    [ "$status" -ne 0 ]
}
