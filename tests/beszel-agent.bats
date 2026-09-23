#!/usr/bin/env bats
# ABOUTME: Tests for Beszel agent installation guards
# ABOUTME: Ensures the systemd user unit is never enabled without a configured KEY

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment

    export NO_COLOR=1
    export ENV_FILE="${TEST_TEMP_DIR}/beszel-agent.env"

    # shellcheck source=../lib/beszel.sh
    source "${PROJECT_ROOT}/lib/beszel.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# beszel_key_configured Tests
# =============================================================================

@test "beszel_key_configured fails when env file is missing" {
    run beszel_key_configured "${TEST_TEMP_DIR}/does-not-exist.env"
    [ "${status}" -ne 0 ]
}

@test "beszel_key_configured fails when KEY is empty" {
    cat > "${ENV_FILE}" <<EOF
# Beszel agent configuration
KEY=
PORT=45876
EOF
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -ne 0 ]
}

@test "beszel_key_configured fails when KEY is only whitespace" {
    printf 'KEY=   \nPORT=45876\n' > "${ENV_FILE}"
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -ne 0 ]
}

@test "beszel_key_configured fails when KEY line is absent entirely" {
    printf 'PORT=45876\n' > "${ENV_FILE}"
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -ne 0 ]
}

@test "beszel_key_configured fails when only a commented KEY is present" {
    printf '# KEY=ssh-ed25519 AAAA\nPORT=45876\n' > "${ENV_FILE}"
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -ne 0 ]
}

@test "beszel_key_configured succeeds when KEY has a value" {
    cat > "${ENV_FILE}" <<EOF
KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample
PORT=45876
EOF
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -eq 0 ]
}

@test "beszel_key_configured succeeds when KEY value is quoted" {
    printf 'KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample"\nPORT=45876\n' > "${ENV_FILE}"
    run beszel_key_configured "${ENV_FILE}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Install-path Guard Tests
# =============================================================================
# Regression: the unit was enabled unconditionally, so WantedBy=default.target
# started it on the next boot with an empty KEY and Restart=always crash-looped
# it indefinitely. Both install paths must gate `enable` on the KEY.

@test "bootstrap-dev-server.sh does not enable beszel unconditionally" {
    run grep -n 'systemctl --user enable beszel-agent' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "${status}" -ne 0 ]
}

@test "install-beszel-agent.sh does not enable beszel unconditionally" {
    run grep -n 'systemctl --user enable beszel-agent' "${PROJECT_ROOT}/scripts/install-beszel-agent.sh"
    [ "${status}" -ne 0 ]
}

@test "bootstrap-dev-server.sh disables the unit when KEY is unconfigured" {
    run grep -qE 'systemctl --user disable (--now )?beszel-agent' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "${status}" -eq 0 ]
}

@test "install-beszel-agent.sh disables the unit when KEY is unconfigured" {
    run grep -qE 'systemctl --user disable (--now )?beszel-agent' "${PROJECT_ROOT}/scripts/install-beszel-agent.sh"
    [ "${status}" -eq 0 ]
}

@test "both install paths gate enablement on beszel_key_configured" {
    run grep -q 'beszel_key_configured' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "${status}" -eq 0 ]
    run grep -q 'beszel_key_configured' "${PROJECT_ROOT}/scripts/install-beszel-agent.sh"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Unit File Tests
# =============================================================================

@test "beszel-agent.service rate-limits restarts so it cannot loop forever" {
    run grep -q '^StartLimitBurst=' "${PROJECT_ROOT}/config/beszel-agent.service"
    [ "${status}" -eq 0 ]
    run grep -q '^StartLimitIntervalSec=' "${PROJECT_ROOT}/config/beszel-agent.service"
    [ "${status}" -eq 0 ]
}

@test "beszel-agent.service declares StartLimit in the [Unit] section" {
    # systemd parses StartLimitIntervalSec/StartLimitBurst in [Unit], not [Service].
    run awk '/^\[Unit\]/{s="Unit"} /^\[Service\]/{s="Service"} /^StartLimit/{print s}' \
        "${PROJECT_ROOT}/config/beszel-agent.service"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    for section in ${output}; do
        [ "${section}" = "Unit" ]
    done
}

@test "embedded unit heredocs match the tracked unit file on StartLimit" {
    run grep -c 'StartLimitBurst' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "${status}" -eq 0 ]
    run grep -c 'StartLimitBurst' "${PROJECT_ROOT}/scripts/install-beszel-agent.sh"
    [ "${status}" -eq 0 ]
}
