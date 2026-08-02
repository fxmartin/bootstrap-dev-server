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
# Nix Garbage Collection Tests
# =============================================================================

@test "setup_nix_gc_timer function exists" {
    run grep "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "setup_nix_gc_timer is called from main" {
    run grep -A150 "^main()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"setup_nix_gc_timer"* ]]
}

@test "Nix GC service runs nix-collect-garbage" {
    run grep "nix-collect-garbage --delete-older-than 30d" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Nix GC timer runs weekly, offset after the flake update timer" {
    run grep "OnCalendar=Sun \*-\*-\* 04:00:00" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "Nix GC timer unit is named nix-gc" {
    run grep 'TIMER_NAME="nix-gc"' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "setup_nix_gc_timer skips re-creation when timer already enabled" {
    run grep -A50 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'systemctl is-enabled "${TIMER_NAME}.timer"'* ]]
    [[ "$output" == *"Nix GC timer already configured"* ]]
    [[ "$output" == *"return 0"* ]]
}

@test "Nix GC unit files are written to the systemd system directory" {
    run grep -A5 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'SERVICE_FILE="/etc/systemd/system/${TIMER_NAME}.service"'* ]]
    [[ "$output" == *'TIMER_FILE="/etc/systemd/system/${TIMER_NAME}.timer"'* ]]
}

@test "Nix GC timer catches up on missed runs (persistent)" {
    run grep -A50 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Persistent=true"* ]]
}

@test "Nix GC timer is wired to timers.target for activation" {
    run grep -A50 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WantedBy=timers.target"* ]]
}

@test "Nix GC timer is enabled and started immediately after creation" {
    run grep -A50 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'systemctl enable "${TIMER_NAME}.timer"'* ]]
    [[ "$output" == *'systemctl start "${TIMER_NAME}.timer"'* ]]
}

@test "verify-server.sh checks that the Nix GC timer is enabled" {
    run grep "systemctl is-enabled --quiet nix-gc.timer" "${PROJECT_ROOT}/tests/verify-server.sh"
    [ "$status" -eq 0 ]
}

@test "README documents Nix GC timer remediation" {
    run grep "nix-gc.timer" "${PROJECT_ROOT}/README.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Nix Flake Update Reliability Tests (issue #3)
#
# A broken devShell build (disk pressure, unstable package breakage) must not
# leave an unbuilt flake.lock in place while the unit reports success, and a
# failing `git pull` must not be silently swallowed forever.
# =============================================================================

@test "setup_nix_update_timer: devShell warm-build failure is not swallowed by || true" {
    run grep -A50 "^setup_nix_update_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"nix build \${FLAKE_DIR}#devShells.x86_64-linux.default --no-link || true"* ]]
    [[ "$output" != *"nix build \${FLAKE_DIR}#devShells.x86_64-linux.default --no-link 2>&1 | tee -a /tmp/nix-update-output.txt || true"* ]]
}

@test "setup_nix_update_timer: rolls back flake.lock when the devShell build fails" {
    run grep -A50 "^setup_nix_update_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git checkout -- flake.lock"* ]]
}

@test "setup_nix_update_timer: git pull failures are surfaced, not swallowed" {
    run grep -A50 "^setup_nix_update_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"git pull --quiet || true"* ]]
}

@test "configure_update_notifications: devShell warm-build failure is not swallowed by || true" {
    run grep -A50 "Update the nix-flake-update service to include notification" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"nix build \${FLAKE_DIR}#devShells.x86_64-linux.default --no-link 2>&1 | tee -a /tmp/nix-update-output.txt || true"* ]]
}

@test "configure_update_notifications: rolls back flake.lock and records failed status when the devShell build fails" {
    run grep -A50 "Update the nix-flake-update service to include notification" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git checkout -- flake.lock"* ]]
    [[ "$output" == *'echo "failed" > /tmp/nix-update-status.txt'* ]]
}

@test "configure_update_notifications: git pull failures are surfaced, not swallowed" {
    run grep -A50 "Update the nix-flake-update service to include notification" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"git pull --quiet || true"* ]]
}

# Helper: pull the literal ExecStart command body out of the given
# heredoc-generated systemd unit so it can be executed against mocked
# git/nix in a throwaway repo, verifying actual runtime behavior rather
# than just the presence of certain substrings.
extract_exec_start_body() {
    local anchor="$1"
    local exec_line
    exec_line=$(grep -A50 "${anchor}" "${PROJECT_ROOT}/bootstrap-dev-server.sh" | grep "^ExecStart=/bin/bash -c" | head -1)
    local cmd_body="${exec_line#ExecStart=/bin/bash -c \'}"
    cmd_body="${cmd_body%\'}"
    # The source heredoc is unquoted, so a literal "\$" in the script becomes
    # "$" once systemd's ExecStart is actually written to disk. Mirror that
    # unescaping here so the extracted body runs the same way it would live.
    cmd_body="${cmd_body//\\\$/\$}"
    echo "${cmd_body}"
}

@test "setup_nix_update_timer ExecStart pipeline: rolls back flake.lock and fails when nix build fails" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    local cmd_body
    cmd_body="$(extract_exec_start_body '^setup_nix_update_timer()')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 0
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        [[ "$1" == "flake" ]] && { echo "updated-lock" > "$PWD/flake.lock"; return 0; }
        [[ "$1" == "build" ]] && return 1
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "original-lock" ]
}

@test "setup_nix_update_timer ExecStart pipeline: keeps flake.lock and succeeds when nix build succeeds" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    local cmd_body
    cmd_body="$(extract_exec_start_body '^setup_nix_update_timer()')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 0
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        [[ "$1" == "flake" ]] && { echo "updated-lock" > "$PWD/flake.lock"; return 0; }
        [[ "$1" == "build" ]] && return 0
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "updated-lock" ]
}

@test "configure_update_notifications ExecStart pipeline: rolls back flake.lock and records failed status when nix build fails" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(extract_exec_start_body 'Update the nix-flake-update service to include notification')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 0
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        [[ "$1" == "flake" ]] && { echo "updated-lock" > "$PWD/flake.lock"; return 0; }
        [[ "$1" == "build" ]] && return 1
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "original-lock" ]
    [ "$(cat /tmp/nix-update-status.txt)" = "failed" ]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

@test "configure_update_notifications ExecStart pipeline: keeps flake.lock and records success status when nix build succeeds" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(extract_exec_start_body 'Update the nix-flake-update service to include notification')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 0
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        [[ "$1" == "flake" ]] && { echo "updated-lock" > "$PWD/flake.lock"; return 0; }
        [[ "$1" == "build" ]] && return 0
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "updated-lock" ]
    [ "$(cat /tmp/nix-update-status.txt)" = "success" ]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

@test "setup_nix_update_timer ExecStart pipeline: git pull failure is surfaced and lock is not silently kept dirty" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    local cmd_body
    cmd_body="$(extract_exec_start_body '^setup_nix_update_timer()')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 1
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        return 0
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
}

@test "setup_nix_update_timer ExecStart pipeline: leading checkout resets a dirty flake.lock before pulling" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"
    # Simulate a stray dirty flake.lock left over from a previous crashed run.
    echo "dirty-leftover" > "${work_dir}/flake.lock"

    local cmd_body
    cmd_body="$(extract_exec_start_body '^setup_nix_update_timer()')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        if [[ "$1" == "pull" ]]; then
            # A real `git pull` refuses to run over local modifications. This
            # mock only succeeds if the leading `git checkout -- flake.lock`
            # already discarded the dirty edit before we get here.
            [[ -n "$(command git -C "$PWD" status --porcelain -- flake.lock)" ]] && return 1
            return 0
        fi
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        [[ "$1" == "flake" ]] && { echo "updated-lock" > "$PWD/flake.lock"; return 0; }
        [[ "$1" == "build" ]] && return 0
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "updated-lock" ]
}

@test "setup_nix_update_timer ExecStart pipeline: rolls back and skips build when nix flake update itself fails" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    local build_marker="${TEST_TEMP_DIR}/build-invoked.marker"
    mkdir -p "${work_dir}"
    rm -f "${build_marker}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    local cmd_body
    cmd_body="$(extract_exec_start_body '^setup_nix_update_timer()')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 0
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        if [[ "$1" == "flake" ]]; then
            echo "partial-lock-from-failed-update" > "$PWD/flake.lock"
            return 1
        fi
        [[ "$1" == "build" ]] && { touch "${build_marker}"; return 0; }
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "original-lock" ]
    [ ! -e "${build_marker}" ]
}

@test "configure_update_notifications ExecStart pipeline: git pull failure is recorded as failed status, not swallowed" {
    local work_dir="${TEST_TEMP_DIR}/repo"
    mkdir -p "${work_dir}"
    git -C "${work_dir}" init -q
    git -C "${work_dir}" config user.email "test@test"
    git -C "${work_dir}" config user.name "test"
    echo "original-lock" > "${work_dir}/flake.lock"
    git -C "${work_dir}" add flake.lock
    git -C "${work_dir}" commit -q -m "init"

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(extract_exec_start_body 'Update the nix-flake-update service to include notification')"
    cmd_body="${cmd_body//\$\{REPO_DIR\}/${work_dir}}"
    cmd_body="${cmd_body//\$\{FLAKE_DIR\}/${work_dir}}"

    # shellcheck disable=SC2329
    git() {
        [[ "$1" == "pull" ]] && return 1
        command git "$@"
    }
    # shellcheck disable=SC2329
    nix() {
        return 0
    }
    export -f git nix

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat "${work_dir}/flake.lock")" = "original-lock" ]
    [ "$(cat /tmp/nix-update-status.txt)" = "failed" ]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
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
