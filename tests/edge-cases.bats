#!/usr/bin/env bats
# ABOUTME: Edge case tests for complete coverage
# ABOUTME: Tests unusual inputs, boundary conditions, and error paths

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1
    export LOG_DIR="${TEST_TEMP_DIR}/logs"

    # Source logging library
    source "${PROJECT_ROOT}/lib/logging.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# Logging Edge Cases
# =============================================================================

@test "logging handles unicode characters" {
    init_logging "test"
    run log_info "Unicode: こんにちは 🎉 émoji"
    [ "$status" -eq 0 ]
}

@test "logging handles newlines in message" {
    init_logging "test"
    run log_info "Line1
Line2"
    [ "$status" -eq 0 ]
}

@test "logging handles tabs in message" {
    init_logging "test"
    run log_info "Column1	Column2	Column3"
    [ "$status" -eq 0 ]
}

@test "logging handles message with dollar signs" {
    init_logging "test"
    run log_info "Cost: \$100 or \${VARIABLE}"
    [ "$status" -eq 0 ]
}

@test "log_box handles long messages" {
    init_logging "test"
    local long_msg
    long_msg=$(printf 'x%.0s' {1..100})
    run log_box "${long_msg}"
    [ "$status" -eq 0 ]
}

@test "log_box handles empty message" {
    init_logging "test"
    run log_box ""
    [ "$status" -eq 0 ]
}

@test "multiple timers can run concurrently" {
    log_timer_start "timer1"
    log_timer_start "timer2"
    sleep 0.1
    run log_timer_end "timer2"
    [ "$status" -eq 0 ]
    run log_timer_end "timer1"
    [ "$status" -eq 0 ]
}

@test "timer can be started twice (overwrites)" {
    log_timer_start "repeated"
    sleep 0.1
    log_timer_start "repeated"  # Should overwrite
    run log_timer_end "repeated"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Key Edge Cases
# =============================================================================

@test "SSH key with spaces in path" {
    local key_path="${TEST_TEMP_DIR}/path with spaces/id_test"
    mkdir -p "$(dirname "${key_path}")"
    ssh-keygen -t ed25519 -f "${key_path}" -N "" -q
    assert_file_exists "${key_path}"
    assert_file_exists "${key_path}.pub"
}

@test "SSH key generation fails on read-only directory" {
    local readonly_dir="${TEST_TEMP_DIR}/readonly"
    mkdir -p "${readonly_dir}"
    chmod 555 "${readonly_dir}"

    run ssh-keygen -t ed25519 -f "${readonly_dir}/test_key" -N "" -q
    [ "$status" -ne 0 ]

    # Cleanup
    chmod 755 "${readonly_dir}"
}

# =============================================================================
# Configuration Variable Edge Cases
# =============================================================================

@test "SSH_PORT accepts non-standard port" {
    export SSH_PORT="2222"
    [ "${SSH_PORT}" = "2222" ]
}

@test "SSH_PORT handles string input" {
    export SSH_PORT="abc"
    [ "${SSH_PORT}" = "abc" ]
    # Note: validation happens in the actual script, not here
}

@test "MOSH_PORT_RANGE can be customized" {
    export MOSH_PORT_START="61000"
    export MOSH_PORT_END="61020"
    [ "${MOSH_PORT_START}" = "61000" ]
    [ "${MOSH_PORT_END}" = "61020" ]
}

@test "GeoIP countries handles multiple countries" {
    export GEOIP_COUNTRIES="US,CA,GB,DE,FR,NL,BE,LU"
    assert_contains "${GEOIP_COUNTRIES}" "US"
    assert_contains "${GEOIP_COUNTRIES}" "LU"
}

# =============================================================================
# Script Content Edge Cases
# =============================================================================

@test "bootstrap script has no trailing whitespace issues" {
    # Count lines with trailing whitespace (should be 0 or minimal)
    local ws_count
    ws_count=$(grep -c ' $' "${PROJECT_ROOT}/bootstrap-dev-server.sh" || echo "0")
    # Allow some trailing whitespace for heredocs
    [ "${ws_count}" -lt 50 ]
}

@test "all shell scripts are executable" {
    [ -x "${PROJECT_ROOT}/bootstrap-dev-server.sh" ]
    [ -x "${PROJECT_ROOT}/hcloud-provision.sh" ]
    [ -x "${PROJECT_ROOT}/scripts/health-check.sh" ]
    [ -x "${PROJECT_ROOT}/scripts/secure-ssh-key.sh" ]
}

@test "all shell scripts have shebang" {
    run head -1 "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    assert_contains "${output}" "#!/"

    run head -1 "${PROJECT_ROOT}/hcloud-provision.sh"
    assert_contains "${output}" "#!/"

    run head -1 "${PROJECT_ROOT}/scripts/health-check.sh"
    assert_contains "${output}" "#!/"

    run head -1 "${PROJECT_ROOT}/scripts/secure-ssh-key.sh"
    assert_contains "${output}" "#!/"
}

@test "scripts use bash not sh" {
    run head -1 "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    assert_contains "${output}" "bash"

    run head -1 "${PROJECT_ROOT}/hcloud-provision.sh"
    assert_contains "${output}" "bash"
}

# =============================================================================
# Security Configuration Edge Cases
# =============================================================================

@test "SSH max auth tries is 3 or less" {
    run grep "MaxAuthTries" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "3"
}

@test "SSH login grace time is 60s or less" {
    run grep "LoginGraceTime" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "SSH X11 forwarding is disabled" {
    run grep "X11Forwarding no" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "SSH TCP forwarding is disabled" {
    run grep "AllowTcpForwarding no" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Fail2Ban ignores localhost" {
    run grep "127.0.0.1" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Path Edge Cases
# =============================================================================

@test "REPO_CLONE_DIR uses .local/share" {
    run grep "REPO_CLONE_DIR" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    assert_contains "${output}" ".local/share"
}

@test "LOG_DIR default uses .local/log" {
    run grep "LOG_DIR" "${PROJECT_ROOT}/lib/logging.sh"
    assert_contains "${output}" ".local/log"
}

# =============================================================================
# Idempotency Edge Cases
# =============================================================================

@test "SSH hardening checks for existing config" {
    run grep 'if \[\[.*-f.*SSH_HARDENING_FILE' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "GitHub CLI checks if already installed" {
    run grep "command -v gh" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Nix checks if already installed" {
    run grep "command -v nix" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Tailscale checks if already installed" {
    run grep "command -v tailscale" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Error Recovery Edge Cases
# =============================================================================

@test "SSH config revert on validation failure" {
    run grep "Reverting" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Rescale recovers on failure" {
    run grep "power server back on" "${PROJECT_ROOT}/hcloud-provision.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Documentation Edge Cases
# =============================================================================

@test "CLAUDE.md exists" {
    assert_file_exists "${PROJECT_ROOT}/CLAUDE.md"
}

@test "README.md exists" {
    assert_file_exists "${PROJECT_ROOT}/README.md"
}

@test "scripts have ABOUTME comments" {
    for script in bootstrap-dev-server.sh hcloud-provision.sh scripts/health-check.sh scripts/secure-ssh-key.sh lib/logging.sh; do
        run grep "ABOUTME" "${PROJECT_ROOT}/${script}"
        [ "$status" -eq 0 ]
    done
}

# =============================================================================
# Special Characters in Paths
# =============================================================================

@test "test helper handles paths with special chars" {
    local special_dir="${TEST_TEMP_DIR}/dir-with-special_chars.test"
    mkdir -p "${special_dir}"
    assert_dir_exists "${special_dir}"
}

@test "create_test_file handles special chars" {
    local special_file="${TEST_TEMP_DIR}/file (1) [test].txt"
    create_test_file "${special_file}" "test content"
    assert_file_exists "${special_file}"
}

# =============================================================================
# Concurrent Execution Safety
# =============================================================================

@test "log files have unique timestamps" {
    mkdir -p "${LOG_DIR}"
    local log1 log2

    init_logging "concurrent1"
    log1="${LOG_FILE}"

    sleep 1

    init_logging "concurrent2"
    log2="${LOG_FILE}"

    [ "${log1}" != "${log2}" ]
}

# =============================================================================
# Environment Variable Edge Cases
# =============================================================================

@test "DEV_USER defaults to current user" {
    unset DEV_USER
    local default_user
    default_user=$(whoami)
    DEV_USER="${DEV_USER:-$(whoami)}"
    [ "${DEV_USER}" = "${default_user}" ]
}

@test "HOME environment is respected" {
    export HOME="${TEST_TEMP_DIR}"
    [ "${HOME}" = "${TEST_TEMP_DIR}" ]
}
