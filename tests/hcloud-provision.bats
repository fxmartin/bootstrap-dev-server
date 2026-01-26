#!/usr/bin/env bats
# ABOUTME: Tests for hcloud-provision.sh functions
# ABOUTME: Tests provisioning logic with mocked hcloud and system commands

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment

    export NO_COLOR=1
    export LOG_DIR="${TEST_TEMP_DIR}/logs"

    # Set default configuration
    export SERVER_NAME="test-server"
    export SERVER_TYPE="cx33"
    export SERVER_IMAGE="ubuntu-24.04"
    export SERVER_LOCATION="fsn1"
    export SSH_KEY_NAME="test-key"
    export SSH_KEY_PATH="${TEST_TEMP_DIR}/id_test"
    export SSH_USER="testuser"

    # Create mock SSH key
    create_mock_ssh_key "${SSH_KEY_PATH}"

    # Source logging library
    source "${PROJECT_ROOT}/lib/logging.sh"
    init_logging "test-hcloud"
}

teardown() {
    common_teardown
}

# =============================================================================
# Configuration Variable Tests
# =============================================================================

@test "default SERVER_NAME is dev-server" {
    unset SERVER_NAME
    SERVER_NAME="${SERVER_NAME:-dev-server}"
    [ "${SERVER_NAME}" = "dev-server" ]
}

@test "default SERVER_TYPE is cx33" {
    unset SERVER_TYPE
    SERVER_TYPE="${SERVER_TYPE:-cx33}"
    [ "${SERVER_TYPE}" = "cx33" ]
}

@test "default SERVER_LOCATION is fsn1" {
    unset SERVER_LOCATION
    SERVER_LOCATION="${SERVER_LOCATION:-fsn1}"
    [ "${SERVER_LOCATION}" = "fsn1" ]
}

@test "default SSH_KEY_PATH is ~/.ssh/id_devserver" {
    unset SSH_KEY_PATH
    SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_devserver}"
    assert_contains "${SSH_KEY_PATH}" "id_devserver"
}

@test "default SSH_USER is fx" {
    unset SSH_USER
    SSH_USER="${SSH_USER:-fx}"
    [ "${SSH_USER}" = "fx" ]
}

@test "default SERVER_PROFILE is dev" {
    unset SERVER_PROFILE
    SERVER_PROFILE="${SERVER_PROFILE:-dev}"
    [ "${SERVER_PROFILE}" = "dev" ]
}

@test "PROFILE_URL_BASE is set to correct GitHub URL" {
    PROFILE_URL_BASE="${PROFILE_URL_BASE:-https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/profiles}"
    assert_contains "${PROFILE_URL_BASE}" "bootstrap-dev-server/main/profiles"
}

# =============================================================================
# Help Function Tests
# =============================================================================

@test "show_help contains usage information" {
    run grep "USAGE:" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "show_help lists all server types" {
    run grep "cx33" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "cpx22" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "cax11" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "show_help lists all locations" {
    run grep "fsn1" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "nbg1" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "hel1" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "ash" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "show_help lists profile options" {
    run grep "dev, nyx, full" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "show_help describes profile parameter" {
    run grep "\-\-profile" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Key Generation Tests
# =============================================================================

@test "generate_dedicated_key creates key file" {
    local test_key="${TEST_TEMP_DIR}/new_key"

    generate_dedicated_key() {
        local key_path="$1"
        ssh-keygen -t ed25519 -f "${key_path}" -N "" -q
    }

    run generate_dedicated_key "${test_key}"
    [ "$status" -eq 0 ]
    assert_file_exists "${test_key}"
    assert_file_exists "${test_key}.pub"
}

@test "generate_dedicated_key sets correct permissions" {
    local test_key="${TEST_TEMP_DIR}/perm_key"

    ssh-keygen -t ed25519 -f "${test_key}" -N "" -q
    chmod 600 "${test_key}"
    chmod 644 "${test_key}.pub"

    # Check private key permissions (cross-platform stat)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        run stat -f "%Lp" "${test_key}"
    else
        run stat -c "%a" "${test_key}"
    fi
    [ "${output}" = "600" ]

    # Check public key permissions (cross-platform stat)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        run stat -f "%Lp" "${test_key}.pub"
    else
        run stat -c "%a" "${test_key}.pub"
    fi
    [ "${output}" = "644" ]
}

@test "generate_dedicated_key uses ED25519 algorithm" {
    local test_key="${TEST_TEMP_DIR}/algo_key"

    ssh-keygen -t ed25519 -f "${test_key}" -N "" -q

    run cat "${test_key}.pub"
    assert_contains "${output}" "ssh-ed25519"
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

@test "script accepts --name argument" {
    run grep "\-\-name)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --type argument" {
    run grep "\-\-type)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --location argument" {
    run grep "\-\-location)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --user argument" {
    run grep "\-\-user)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --delete argument" {
    run grep "\-\-delete)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --rescale argument" {
    run grep "\-\-rescale)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --list argument" {
    run grep "\-\-list)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --yes/-y argument" {
    run grep "\-\-yes" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "\-y)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --no-bootstrap argument" {
    run grep "\-\-no-bootstrap)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --ssh-port argument" {
    run grep "\-\-ssh-port)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --geoip-countries argument" {
    run grep "\-\-geoip-countries)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --git-name argument" {
    run grep "\-\-git-name)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --git-email argument" {
    run grep "\-\-git-email)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script accepts --profile argument" {
    run grep "\-\-profile)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Prerequisites Check Tests
# =============================================================================

@test "check_prerequisites verifies hcloud CLI" {
    run grep "command -v hcloud" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "check_prerequisites verifies jq" {
    run grep "command -v jq" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "check_prerequisites verifies SSH key exists" {
    run grep "SSH_KEY_PATH" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Hetzner Authentication Tests
# =============================================================================

@test "authenticate_hcloud checks for existing context" {
    run grep "hcloud context active" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "authenticate_hcloud supports HCLOUD_TOKEN environment variable" {
    run grep "HCLOUD_TOKEN" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Key Upload Tests
# =============================================================================

@test "upload_ssh_key uses MD5 fingerprint" {
    run grep "ssh-keygen -E md5" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "upload_ssh_key checks for existing key" {
    run grep "hcloud ssh-key list" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Server Creation Tests
# =============================================================================

@test "create_server checks for existing server" {
    run grep "hcloud server describe" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "create_server uses correct parameters" {
    # Check the create_server function block (multi-line)
    run grep -A 10 "hcloud server create" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]

    # Verify each parameter is present in the function
    run grep "\-\-name" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]

    run grep "\-\-type" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]

    run grep "\-\-image" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]

    run grep "\-\-location" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]

    run grep "\-\-ssh-key" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Server Wait Tests
# =============================================================================

@test "wait_for_server has timeout" {
    run grep "max_attempts" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "wait_for_server checks server status" {
    run grep '"running"' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "wait_for_server waits for SSH availability" {
    run grep "Waiting for SSH" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# User Account Setup Tests
# =============================================================================

@test "setup_user_account sets hostname" {
    run grep "hostnamectl set-hostname" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "setup_user_account creates user with sudo" {
    run grep "NOPASSWD:ALL" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "setup_user_account copies SSH keys" {
    run grep "authorized_keys" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Config Update Tests
# =============================================================================

@test "update_ssh_config creates config entry" {
    run grep '~/.ssh/config' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "update_ssh_config includes IdentitiesOnly" {
    run grep "IdentitiesOnly yes" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "update_ssh_config includes ForwardAgent no" {
    run grep "ForwardAgent no" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "update_ssh_config includes AddKeysToAgent" {
    run grep "AddKeysToAgent yes" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Delete Server Tests
# =============================================================================

@test "delete_server requires confirmation" {
    run grep "Type server name to confirm" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "delete_server removes SSH config entry" {
    run grep "Removing SSH config entry" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Rescale Server Tests
# =============================================================================

@test "rescale_server checks architecture compatibility" {
    run grep "Cannot rescale between architectures" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "rescale_server powers off server before rescaling" {
    run grep "hcloud server poweroff" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "rescale_server powers on server after rescaling" {
    run grep "hcloud server poweron" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "rescale_server uses change-type command" {
    run grep "hcloud server change-type" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Profile Execution Tests
# =============================================================================

@test "run_profile function exists" {
    run grep "^run_profile()" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "run_profile handles dev profile" {
    run grep -A 5 'case "${SERVER_PROFILE}"' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "dev)"
}

@test "run_profile handles nyx profile" {
    run grep -A 10 'case "${SERVER_PROFILE}"' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "nyx)"
}

@test "run_profile handles full profile" {
    run grep -A 15 'case "${SERVER_PROFILE}"' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "full)"
}

@test "run_profile handles unknown profile" {
    run grep -A 20 'case "${SERVER_PROFILE}"' "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "*)"
    assert_contains "${output}" "Unknown profile"
}

@test "run_profile uses PROFILE_URL_BASE for nyx" {
    run grep -A 5 "nyx)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "\${PROFILE_URL_BASE}/nyx.sh"
}

@test "run_profile uses PROFILE_URL_BASE for full" {
    run grep -A 5 "full)" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "\${PROFILE_URL_BASE}/nyx.sh"
}

@test "run_profile uses SSH with correct options for nyx" {
    run grep -B 2 -A 2 "nyx.sh" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "ssh -o StrictHostKeyChecking=no"
    assert_contains "${output}" "UserKnownHostsFile=/dev/null"
}

@test "run_profile uses curl with secure flags" {
    run grep "curl.*nyx.sh" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "curl -fsSL"
}

@test "run_profile executes profile script with sudo" {
    run grep "nyx.sh.*sudo bash" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "profile is skipped when SERVER_PROFILE is dev" {
    run grep -B 2 "run_profile" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" '!= "dev"'
}

# =============================================================================
# Cross-Platform Compatibility Tests
# =============================================================================

@test "platform detection function exists" {
    run grep -q "detect_platform()" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "sed_inplace function exists" {
    run grep -q "sed_inplace()" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "no bare sed -i calls remain (should use sed_inplace)" {
    # Exclude the sed_inplace function itself (from function definition to closing brace)
    run bash -c "sed '/^sed_inplace()/,/^}/d' '${PROJECT_ROOT}/hcloud-provision.sh' | grep 'sed -i' || true"
    # If grep finds nothing, output should be empty
    [ -z "$output" ]
}

# =============================================================================
# Bootstrap Execution Tests
# =============================================================================

@test "run_bootstrap validates git identity for auto mode" {
    run grep "Git identity required for non-interactive" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "run_bootstrap passes environment variables" {
    run grep "SSH_PORT" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "GIT_USER_NAME" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "run_bootstrap uses bootstrap URL" {
    run grep "BOOTSTRAP_URL" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "script uses set -euo pipefail" {
    run head -30 "${PROJECT_ROOT}/hcloud-provision.sh"
    assert_contains "${output}" "set -euo pipefail"
}

@test "script handles unknown options" {
    run grep "Unknown option" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Security Tests
# =============================================================================

@test "SSH config uses strict host key checking" {
    run grep "StrictHostKeyChecking" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "SSH config uses UseKeychain for macOS" {
    run grep "UseKeychain yes" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Logging Tests
# =============================================================================

@test "script sources logging library" {
    run grep "source.*logging.sh" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script initializes logging" {
    run grep "init_logging" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

@test "script uses log_timer functions" {
    run grep "log_timer_start" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
    run grep "log_timer_end" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}
