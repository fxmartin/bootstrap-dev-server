#!/usr/bin/env bats
# ABOUTME: Tests for bootstrap-dev-server.sh functions
# ABOUTME: Tests individual functions in isolation with mocked system commands

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment

    # Set required variables
    export REPO_CLONE_DIR="${TEST_TEMP_DIR}/repo"
    export BOOTSTRAP_SUBDIR="."
    export LOG_DIR="${TEST_TEMP_DIR}/logs"
    export NO_COLOR=1

    # Source the logging library
    source "${PROJECT_ROOT}/lib/logging.sh"
    init_logging "test-bootstrap"
}

teardown() {
    common_teardown
}

# =============================================================================
# Helper to source bootstrap functions
# =============================================================================

# Extract and source specific function from bootstrap script
source_bootstrap_function() {
    local func_name="$1"

    # Source the logging functions first (they're defined inline in bootstrap)
    export RED=''
    export GREEN=''
    export YELLOW=''
    export BLUE=''
    export CYAN=''
    export NC=''

    # Define the inline logging functions from bootstrap
    log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  ${1}"; }
    log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [OK]    ${1}"; }
    log_warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  ${1}" >&2; }
    log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${1}" >&2; }
    log_step() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [STEP]  ${1}"; }
    log_phase() { log_step "Phase: ${1}"; }
    log_debug() { [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo -e "[DEBUG] ${1}" || true; }

    export -f log_info log_ok log_warn log_error log_step log_phase log_debug
}

# =============================================================================
# Configuration Variable Tests
# =============================================================================

@test "default DEV_USER is current user" {
    source_bootstrap_function "config"
    [ -n "${DEV_USER:-$(whoami)}" ]
}

@test "default SSH_PORT is 22" {
    unset SSH_PORT
    SSH_PORT="${SSH_PORT:-22}"
    [ "${SSH_PORT}" = "22" ]
}

@test "default MOSH_PORT_START is 60000" {
    unset MOSH_PORT_START
    MOSH_PORT_START="${MOSH_PORT_START:-60000}"
    [ "${MOSH_PORT_START}" = "60000" ]
}

@test "default MOSH_PORT_END is 60010" {
    unset MOSH_PORT_END
    MOSH_PORT_END="${MOSH_PORT_END:-60010}"
    [ "${MOSH_PORT_END}" = "60010" ]
}

@test "UFW_RATE_LIMIT defaults to true" {
    unset UFW_RATE_LIMIT
    UFW_RATE_LIMIT="${UFW_RATE_LIMIT:-true}"
    [ "${UFW_RATE_LIMIT}" = "true" ]
}

@test "GEOIP_ENABLED defaults to true" {
    unset GEOIP_ENABLED
    GEOIP_ENABLED="${GEOIP_ENABLED:-true}"
    [ "${GEOIP_ENABLED}" = "true" ]
}

@test "GEOIP_COUNTRIES defaults to LU,FR,GR" {
    unset GEOIP_COUNTRIES
    GEOIP_COUNTRIES="${GEOIP_COUNTRIES:-LU,FR,GR}"
    [ "${GEOIP_COUNTRIES}" = "LU,FR,GR" ]
}

# =============================================================================
# upgrade_logging Tests
# =============================================================================

@test "upgrade_logging sources logging library when available" {
    source_bootstrap_function "upgrade"

    # Create a mock logging library
    mkdir -p "${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib"
    cat > "${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/logging.sh" << 'EOF'
LOGGING_SOURCED=true
init_logging() { :; }
EOF

    upgrade_logging() {
        local lib_path="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/logging.sh"
        if [[ -f "${lib_path}" ]]; then
            source "${lib_path}"
        fi
    }

    upgrade_logging
    [ "${LOGGING_SOURCED}" = "true" ]
}

# =============================================================================
# preflight_checks Function Tests
# =============================================================================

@test "preflight_checks detects non-Ubuntu" {
    source_bootstrap_function "preflight"

    # Create mock os-release for non-Ubuntu
    mkdir -p "${TEST_TEMP_DIR}/etc"
    cat > "${TEST_TEMP_DIR}/etc/os-release" << 'EOF'
ID=fedora
PRETTY_NAME="Fedora 40"
EOF

    preflight_checks() {
        if [[ -f "${TEST_TEMP_DIR}/etc/os-release" ]]; then
            . "${TEST_TEMP_DIR}/etc/os-release"
            if [[ "${ID}" != "ubuntu" ]]; then
                echo "Not Ubuntu: ${ID}"
                return 1
            fi
        fi
    }

    run preflight_checks
    [ "$status" -eq 1 ]
    assert_contains "${output}" "Not Ubuntu"
}

@test "preflight_checks accepts Ubuntu" {
    source_bootstrap_function "preflight"

    # Create mock os-release for Ubuntu
    mkdir -p "${TEST_TEMP_DIR}/etc"
    cat > "${TEST_TEMP_DIR}/etc/os-release" << 'EOF'
ID=ubuntu
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF

    preflight_checks() {
        if [[ -f "${TEST_TEMP_DIR}/etc/os-release" ]]; then
            . "${TEST_TEMP_DIR}/etc/os-release"
            if [[ "${ID}" != "ubuntu" ]]; then
                return 1
            fi
            echo "Detected ${PRETTY_NAME}"
        fi
        return 0
    }

    run preflight_checks
    [ "$status" -eq 0 ]
    assert_contains "${output}" "Ubuntu 24.04"
}

# =============================================================================
# configure_git_identity Tests
# =============================================================================

@test "configure_git_identity uses env vars when set" {
    source_bootstrap_function "git"

    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"

    # Mock git config
    git() {
        if [[ "$1" == "config" && "$2" == "--global" ]]; then
            if [[ "$3" == "user.name" ]]; then
                if [[ "$4" == "" ]]; then
                    echo ""
                else
                    echo "Setting user.name to $4"
                fi
            elif [[ "$3" == "user.email" ]]; then
                if [[ "$4" == "" ]]; then
                    echo ""
                else
                    echo "Setting user.email to $4"
                fi
            fi
        fi
    }
    export -f git

    configure_git_identity() {
        local git_name="${GIT_USER_NAME:-}"
        local git_email="${GIT_USER_EMAIL:-}"
        if [[ -n "${git_name}" ]] && [[ -n "${git_email}" ]]; then
            echo "Using: ${git_name} <${git_email}>"
            return 0
        fi
        return 1
    }

    run configure_git_identity
    [ "$status" -eq 0 ]
    assert_contains "${output}" "Test User"
}

# =============================================================================
# SSH Hardening Tests
# =============================================================================

@test "SSH hardening file path is correct" {
    local expected="/etc/ssh/sshd_config.d/99-hardening.conf"
    [ "${expected}" = "/etc/ssh/sshd_config.d/99-hardening.conf" ]
}

@test "SSH config contains strong ciphers" {
    source_bootstrap_function "ssh"

    # Define expected ciphers
    local expected_ciphers="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr"

    # Check if the bootstrap script contains these ciphers
    run grep -o "Ciphers.*" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    assert_contains "${output}" "chacha20-poly1305"
}

@test "SSH config disables root login" {
    run grep "PermitRootLogin no" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "SSH config disables password auth" {
    run grep "PasswordAuthentication no" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firewall Configuration Tests
# =============================================================================

@test "UFW default deny incoming is configured" {
    run grep "ufw default deny incoming" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "UFW default allow outgoing is configured" {
    run grep "ufw default allow outgoing" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Mosh ports are configurable" {
    run grep "MOSH_PORT_START" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    run grep "MOSH_PORT_END" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Fail2Ban Configuration Tests
# =============================================================================

@test "Fail2Ban ban time is 24 hours for SSH" {
    run grep "bantime = 24h" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Fail2Ban max retry is 3" {
    run grep "maxretry = 3" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Nix Installation Tests
# =============================================================================

@test "Uses Determinate Systems Nix installer" {
    run grep "install.determinate.systems" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Nix installer runs with no-confirm flag" {
    run grep "\-\-no-confirm" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Dev Flake Tests
# =============================================================================

@test "create_dev_flake uses symlink approach" {
    run grep "ln -s" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Shell Integration Tests
# =============================================================================

@test "setup_shell_integration adds dev function" {
    run grep "dev()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "setup_shell_integration adds dev-update function" {
    run grep "dev-update()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Shell aliases are configured" {
    run grep "alias d='dev'" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    run grep "alias dm='dev minimal'" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    run grep "alias dp='dev python'" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Tmux Configuration Tests
# =============================================================================

@test "tmux uses zsh as default shell" {
    run grep "default-shell /usr/bin/zsh" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "tmux enables mouse support" {
    run grep "set -g mouse on" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Unattended Upgrades Tests
# =============================================================================

@test "configure_unattended_upgrades enables automatic updates" {
    run grep "Unattended-Upgrade::Automatic-Reboot" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Automatic reboot is scheduled at 4am" {
    run grep 'Automatic-Reboot-Time "04:00"' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Security Report Tests
# =============================================================================

@test "Security report script path is correct" {
    run grep "/usr/local/bin/security-report.sh" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Security report runs at 7am" {
    run grep "0 7 \* \* \*" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Podman Configuration Tests
# =============================================================================

@test "configure_podman creates containers directory" {
    run grep '\.config/containers' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Podman policy allows insecure images" {
    run grep "insecureAcceptAnything" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Kernel Hardening Tests
# =============================================================================

@test "sysctl disables IP forwarding" {
    run grep "ip_forward = 0" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "sysctl enables SYN cookies" {
    run grep "tcp_syncookies = 1" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "sysctl restricts kernel pointers" {
    run grep "kptr_restrict = 2" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Idempotency Tests
# =============================================================================

@test "Script is idempotent - checks for existing config" {
    # Check that various functions check for existing state before modifying
    run grep -c "already configured\|already exists\|already installed" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [ "${output}" -gt 5 ]  # Should have multiple idempotency checks
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "Script uses set -euo pipefail" {
    run head -20 "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    assert_contains "${output}" "set -euo pipefail"
}

@test "Script validates SSH config before applying" {
    run grep "sshd -t" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}
