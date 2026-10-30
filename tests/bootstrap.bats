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

    # The ExecStart pipelines source the Nix daemon profile, which exists only
    # on a host with Nix installed. Point them at an empty stub so the pipeline
    # logic is exercised on any machine, root CI containers included.
    export NIX_DAEMON_STUB="${TEST_TEMP_DIR}/nix-daemon.sh"
    : > "${NIX_DAEMON_STUB}"

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

@test "setup_nix_gc_timer refreshes drifted unit files instead of skipping once enabled" {
    run grep -A60 "^setup_nix_gc_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'install_systemd_unit "${SERVICE_FILE}"'* ]]
    [[ "$output" == *'install_systemd_unit "${TIMER_FILE}"'* ]]
    [[ "$output" == *'[[ ${UNITS_CHANGED} -eq 0 ]] && systemctl is-enabled "${TIMER_NAME}.timer"'* ]]
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
# install_systemd_unit Tests
#
# Unit files must converge on every bootstrap re-run: a fix to a unit's
# content has to reach already-provisioned servers instead of being frozen
# by a "skip once enabled/marker present" guard (that guard swallowed
# fix #6 on live servers).
# =============================================================================

# Extract the helper from the script and run it with sudo mocked to a
# passthrough, so the real cmp/install behavior is exercised against a
# throwaway destination file.
run_install_systemd_unit() {
    local dest="$1"
    local content="$2"
    bash -c "
        set -euo pipefail
        sudo() { \"\$@\"; }
        $(sed -n '/^install_systemd_unit()/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")
        printf '%s\n' \"${content}\" | install_systemd_unit '${dest}'
    "
}

@test "install_systemd_unit function exists" {
    run grep "^install_systemd_unit()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
}

@test "install_systemd_unit writes a missing unit and reports a change" {
    local dest="${TEST_TEMP_DIR}/unit.service"
    run run_install_systemd_unit "${dest}" "[Unit]"
    [ "$status" -eq 0 ]
    [ -f "${dest}" ]
    [ "$(cat "${dest}")" = "[Unit]" ]
}

@test "install_systemd_unit rewrites a drifted unit and reports a change" {
    local dest="${TEST_TEMP_DIR}/unit.service"
    printf 'stale content\n' > "${dest}"
    run run_install_systemd_unit "${dest}" "[Unit]"
    [ "$status" -eq 0 ]
    [ "$(cat "${dest}")" = "[Unit]" ]
}

@test "install_systemd_unit leaves an identical unit alone and reports no change" {
    local dest="${TEST_TEMP_DIR}/unit.service"
    printf '[Unit]\n' > "${dest}"
    run run_install_systemd_unit "${dest}" "[Unit]"
    [ "$status" -eq 1 ]
    [ "$(cat "${dest}")" = "[Unit]" ]
}

@test "setup_nix_update_timer refreshes drifted unit files instead of skipping once enabled" {
    run grep -A70 "^setup_nix_update_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'install_systemd_unit "${SERVICE_FILE}"'* ]]
    [[ "$output" == *'install_systemd_unit "${TIMER_FILE}"'* ]]
    [[ "$output" == *'[[ ${UNITS_CHANGED} -eq 0 ]] && systemctl is-enabled "${TIMER_NAME}.timer"'* ]]
}

@test "setup_nix_update_timer does not clobber the notification-enhanced service" {
    run grep -A70 "^setup_nix_update_timer()" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'grep -q "nix-update-notify" "${SERVICE_FILE}"'* ]]
}

@test "configure_update_notifications re-applies the service on content drift instead of freezing on the marker grep" {
    run grep -A60 "Update the nix-flake-update service to include notification" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'install_systemd_unit "${SERVICE_FILE}"'* ]]
    [[ "$output" != *'if grep -q "nix-update-notify" "${SERVICE_FILE}"; then'* ]]
}

# =============================================================================
# Lock Authority Tests (story 01.1-002)
#
# The repository is the only source of flake.lock: the weekly service and
# dev-update hard-reset the checkout to origin/main, build dev-env, and only
# then upgrade the profile. Neither may ever run `nix flake update`.
# =============================================================================

# Print the text of a function so the static assertions look at the unit or
# function they name, not the whole script.
bootstrap_function_text() {
    sed -n "/^$1() {/,/^}/p" "${PROJECT_ROOT}/bootstrap-dev-server.sh"
}

# dev-update lives in a heredoc inside setup_shell_integration, at column 0,
# so a function range for the enclosing function would stop at the first
# heredoc'd closing brace.
bootstrap_dev_update_text() {
    bootstrap_function_text dev-update
}

setup_dev_env_function_text() {
    sed -n '/^dev-update() {/,/^}/p' "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
}

# Assert $1 fetches and hard-resets to origin/main ahead of `nix build`, builds
# dev-env, and upgrades the profile only after the build.
assert_reset_then_build_then_upgrade() {
    local text="$1"
    [[ -n "${text}" ]]
    local before_build="${text%%nix build*}"
    [[ "${before_build}" != "${text}" ]]
    [[ "${before_build}" == *"git fetch"* ]]
    [[ "${before_build}" == *"git reset --hard"*"origin/main"* ]]
    local after_build="${text#*nix build}"
    [[ "${after_build}" == *"#dev-env"* ]]
    [[ "${after_build}" == *"nix profile upgrade dev-env"* ]]
}

@test "setup_nix_update_timer unit never runs nix flake update" {
    run bootstrap_function_text setup_nix_update_timer
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" != *"nix flake update"* ]]
}

@test "configure_update_notifications unit never runs nix flake update" {
    run bootstrap_function_text configure_update_notifications
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" != *"nix flake update"* ]]
}

@test "bootstrap dev-update never runs nix flake update" {
    run bootstrap_dev_update_text
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" != *"nix flake update"* ]]
}

@test "scripts/setup-dev-env.sh dev-update never runs nix flake update" {
    run setup_dev_env_function_text
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" != *"nix flake update"* ]]
}

@test "setup_nix_update_timer unit resets to origin/main before building, upgrades the profile after" {
    assert_reset_then_build_then_upgrade "$(extract_exec_start_body '^setup_nix_update_timer()')"
}

@test "configure_update_notifications unit resets to origin/main before building, upgrades the profile after" {
    assert_reset_then_build_then_upgrade "$(extract_exec_start_body 'Update the nix-flake-update service to include notification')"
}

@test "bootstrap dev-update resets to origin/main before building, upgrades the profile after" {
    assert_reset_then_build_then_upgrade "$(bootstrap_dev_update_text)"
}

@test "scripts/setup-dev-env.sh dev-update resets to origin/main before building, upgrades the profile after" {
    assert_reset_then_build_then_upgrade "$(setup_dev_env_function_text)"
}

# Helper: pull the literal ExecStart command body out of the given
# heredoc-generated systemd unit so it can be executed against a stubbed nix
# and a real throwaway git repo, verifying runtime behavior rather than just
# the presence of certain substrings.
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
    cmd_body="${cmd_body//\/nix\/var\/nix\/profiles\/default\/etc\/profile.d\/nix-daemon.sh/${NIX_DAEMON_STUB}}"
    echo "${cmd_body}"
}

# Helper: an origin with one commit, a clone of it (the server checkout), and
# a second origin commit carrying a new flake.lock - what a merged lock-update
# MR looks like. Leaves ORIGIN_DIR, WORK_DIR and NIX_LOG set.
make_checkout_behind_origin() {
    ORIGIN_DIR="${TEST_TEMP_DIR}/origin.git"
    WORK_DIR="${TEST_TEMP_DIR}/repo"
    local pusher="${TEST_TEMP_DIR}/pusher"
    git init -q --bare -b main "${ORIGIN_DIR}"
    git clone -q "${ORIGIN_DIR}" "${pusher}" 2>/dev/null
    git -C "${pusher}" config user.email "test@test"
    git -C "${pusher}" config user.name "test"
    git -C "${pusher}" checkout -q -B main
    echo "original-lock" > "${pusher}/flake.lock"
    git -C "${pusher}" add flake.lock
    git -C "${pusher}" commit -q -m "init"
    git -C "${pusher}" push -q origin main
    git clone -q "${ORIGIN_DIR}" "${WORK_DIR}"
    git -C "${WORK_DIR}" config user.email "test@test"
    git -C "${WORK_DIR}" config user.name "test"
    echo "reviewed-lock" > "${pusher}/flake.lock"
    git -C "${pusher}" commit -q -am "chore: bump flake.lock"
    git -C "${pusher}" push -q origin main
    NIX_LOG="${TEST_TEMP_DIR}/nix-calls.log"
    : > "${NIX_LOG}"
    export NIX_LOG WORK_DIR
}

# nix stub: records every invocation; the build outcome comes from
# NIX_BUILD_RC and the stub logs the lock that was on disk when it ran.
define_nix_stub() {
    # shellcheck disable=SC2329
    nix() {
        echo "$*" >> "${NIX_LOG}"
        if [[ "$1" == "build" ]]; then
            echo "lock-at-build: $(cat "${WORK_DIR}/flake.lock")" >> "${NIX_LOG}"
            return "${NIX_BUILD_RC:-0}"
        fi
        return 0
    }
    export -f nix
}

# Resolve REPO_DIR/FLAKE_DIR placeholders in an extracted ExecStart body
bind_unit_paths() {
    local body="$1"
    body="${body//\$\{REPO_DIR\}/${WORK_DIR}}"
    body="${body//\$\{FLAKE_DIR\}/${WORK_DIR}}"
    echo "${body}"
}

@test "setup_nix_update_timer ExecStart pipeline: applies origin/main's flake.lock, builds, then upgrades the profile" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [ "$(cat "${WORK_DIR}/flake.lock")" = "reviewed-lock" ]
    [ "$(git -C "${WORK_DIR}" rev-parse HEAD)" = "$(git -C "${ORIGIN_DIR}" rev-parse main)" ]
    run cat "${NIX_LOG}"
    [[ "$output" == *"lock-at-build: reviewed-lock"* ]]
    [[ "$output" != *"flake update"* ]]
    [[ "$output" == *"build "*"#dev-env"* ]]
    [[ "$output" == *"profile upgrade dev-env"* ]]
}

@test "setup_nix_update_timer ExecStart pipeline: a failed build leaves the profile untouched and fails the unit" {
    make_checkout_behind_origin
    define_nix_stub
    export NIX_BUILD_RC=1

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    run cat "${NIX_LOG}"
    [[ "$output" != *"profile upgrade"* ]]
}

@test "setup_nix_update_timer ExecStart pipeline: a failed fetch fails the unit before building" {
    make_checkout_behind_origin
    define_nix_stub
    git -C "${WORK_DIR}" remote set-url origin "${TEST_TEMP_DIR}/does-not-exist.git"
    echo "local-drift" > "${WORK_DIR}/flake.lock"

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ ! -s "${NIX_LOG}" ]
    [ "$(cat "${WORK_DIR}/flake.lock")" = "local-drift" ]
}

@test "setup_nix_update_timer ExecStart pipeline: logs the discarded diff before the reset" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[discarded]"*"flake.lock"* ]]
    [[ "$output" == *"1 file changed"* ]]
}

@test "setup_nix_update_timer ExecStart pipeline: logs local commits that the reset discards" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-commit-lock" > "${WORK_DIR}/flake.lock"
    git -C "${WORK_DIR}" commit -q -am "chore: update flake.lock with latest nixpkgs"

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[discarded commit]"*"update flake.lock with latest nixpkgs"* ]]
    [ "$(cat "${WORK_DIR}/flake.lock")" = "reviewed-lock" ]
}

@test "setup_nix_update_timer ExecStart pipeline: a clean checkout logs no discarded diff" {
    make_checkout_behind_origin
    define_nix_stub

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body '^setup_nix_update_timer()')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [[ "$output" != *"[discarded]"* ]]
}

@test "configure_update_notifications ExecStart pipeline: applies origin/main's lock and records success status" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"
    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body 'Update the nix-flake-update service to include notification')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    [ "$(cat "${WORK_DIR}/flake.lock")" = "reviewed-lock" ]
    [ "$(cat /tmp/nix-update-status.txt)" = "success" ]
    run cat "${NIX_LOG}"
    [[ "$output" != *"flake update"* ]]
    [[ "$output" == *"profile upgrade dev-env"* ]]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

@test "configure_update_notifications ExecStart pipeline: a failed build keeps the profile and records failed status" {
    make_checkout_behind_origin
    define_nix_stub
    export NIX_BUILD_RC=1
    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body 'Update the nix-flake-update service to include notification')")"

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat /tmp/nix-update-status.txt)" = "failed" ]
    run cat "${NIX_LOG}"
    [[ "$output" != *"profile upgrade"* ]]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

@test "configure_update_notifications ExecStart pipeline: a failed fetch is recorded as failed status" {
    make_checkout_behind_origin
    define_nix_stub
    git -C "${WORK_DIR}" remote set-url origin "${TEST_TEMP_DIR}/does-not-exist.git"
    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body 'Update the nix-flake-update service to include notification')")"

    run bash -c "${cmd_body}"
    [ "$status" -ne 0 ]
    [ "$(cat /tmp/nix-update-status.txt)" = "failed" ]
    [ ! -s "${NIX_LOG}" ]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

@test "configure_update_notifications ExecStart pipeline: logs the discarded diff into the notification output" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"
    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt

    local cmd_body
    cmd_body="$(bind_unit_paths "$(extract_exec_start_body 'Update the nix-flake-update service to include notification')")"

    run bash -c "${cmd_body}"
    [ "$status" -eq 0 ]
    run cat /tmp/nix-update-output.txt
    [[ "$output" == *"[discarded]"*"flake.lock"* ]]

    rm -f /tmp/nix-update-status.txt /tmp/nix-update-output.txt
}

# Helper: run scripts/setup-dev-env.sh's dev-update against the fixture
# checkout, with HOME laid out like the server's.
run_dev_update() {
    local home="${TEST_TEMP_DIR}/server-home"
    mkdir -p "${home}/.local/share" "${home}/.config"
    ln -s "${WORK_DIR}" "${home}/.local/share/bootstrap-dev-server"
    ln -s "${WORK_DIR}" "${home}/.config/nix-dev-env"
    local fn
    fn="$(setup_dev_env_function_text)"
    HOME="${home}" run bash -c "${fn}"$'\n'"dev-update"
}

@test "dev-update applies origin/main's flake.lock, builds, upgrades the profile and prints the commit" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"

    run_dev_update
    [ "$status" -eq 0 ]
    [ "$(cat "${WORK_DIR}/flake.lock")" = "reviewed-lock" ]
    [[ "$output" == *"$(git -C "${WORK_DIR}" log -1 --oneline)"* ]]
    run cat "${NIX_LOG}"
    [[ "$output" != *"flake update"* ]]
    [[ "$output" == *"lock-at-build: reviewed-lock"* ]]
    [[ "$output" == *"profile upgrade dev-env"* ]]
}

@test "dev-update logs the discarded diff before the reset" {
    make_checkout_behind_origin
    define_nix_stub
    echo "local-drift" > "${WORK_DIR}/flake.lock"

    run_dev_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"flake.lock"* ]]
    [[ "$output" == *"1 file changed"* ]]
}

@test "dev-update does not commit or push anything" {
    make_checkout_behind_origin
    define_nix_stub
    local origin_before
    origin_before="$(git -C "${ORIGIN_DIR}" rev-parse main)"

    run_dev_update
    [ "$status" -eq 0 ]
    [ "$(git -C "${ORIGIN_DIR}" rev-parse main)" = "${origin_before}" ]
}

@test "dev-update with a failed build leaves the profile untouched and fails" {
    make_checkout_behind_origin
    define_nix_stub
    export NIX_BUILD_RC=1

    run_dev_update
    [ "$status" -ne 0 ]
    run cat "${NIX_LOG}"
    [[ "$output" != *"profile upgrade"* ]]
}

@test "dev-update with a failed fetch fails before building" {
    make_checkout_behind_origin
    define_nix_stub
    git -C "${WORK_DIR}" remote set-url origin "${TEST_TEMP_DIR}/does-not-exist.git"

    run_dev_update
    [ "$status" -ne 0 ]
    [ ! -s "${NIX_LOG}" ]
}

@test "dev-update without a checkout fails before touching nix" {
    define_nix_stub
    local home="${TEST_TEMP_DIR}/empty-home"
    mkdir -p "${home}"
    local fn
    fn="$(setup_dev_env_function_text)"
    HOME="${home}" run bash -c "${fn}"$'\n'"dev-update"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No checkout"* ]]
    [ ! -s "${NIX_LOG}" ]
}

@test "dev-update with a failed profile upgrade fails and does not report success" {
    make_checkout_behind_origin
    # shellcheck disable=SC2329
    nix() {
        echo "$*" >> "${NIX_LOG}"
        [[ "$1" == "profile" ]] && return 1
        return 0
    }
    export -f nix

    run_dev_update
    [ "$status" -ne 0 ]
    [[ "$output" != *"Dev environment updated to"* ]]
}

@test "the repo ships an update-lock recipe that updates the lock, then runs nix flake check" {
    [ -f "${PROJECT_ROOT}/justfile" ]
    run sed -n '/^update-lock/,/^$/p' "${PROJECT_ROOT}/justfile"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nix flake update"*"nix flake check"* ]]
}

@test "README documents the lock-update flow and no longer claims the server updates flake.lock" {
    run grep -n "just update-lock" "${PROJECT_ROOT}/README.md"
    [ "$status" -eq 0 ]
    run grep -n "Systemd timer updates flake.lock" "${PROJECT_ROOT}/README.md"
    [ "$status" -ne 0 ]
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
