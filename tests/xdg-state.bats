#!/usr/bin/env bats
# ABOUTME: Tests for configure_xdg_state and the verify-server.sh XDG_STATE_HOME checks
# ABOUTME: Offline, temp HOME, stubbed systemctl; nothing real is touched

load 'test_helper'

setup() {
    common_setup
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "${HOME}"
    export SYSTEMCTL_LOG="${TEST_TEMP_DIR}/systemctl.log"
    export SYSTEMCTL_ENV="XDG_STATE_HOME=/x"
    : >"${SYSTEMCTL_LOG}"
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1"; }
    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; }
    systemctl() {
        echo "$*" >>"${SYSTEMCTL_LOG}"
        case "$2" in
            show-environment) [[ -n "${SYSTEMCTL_ENV}" ]] && echo "${SYSTEMCTL_ENV}" ;;
            is-active) return 0 ;;
        esac
        return 0
    }
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/lib/rc-block.sh"
    # shellcheck disable=SC1090
    source <(sed -n '/^configure_xdg_state() {/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")
    # shellcheck disable=SC1090
    source <(sed -n '/^check_xdg_state() {/,/^}$/p' "${PROJECT_ROOT}/tests/verify-server.sh")
}

teardown() {
    common_teardown
}

@test "fresh HOME gets environment.d file, profile block and state dir" {
    run configure_xdg_state
    [ "$status" -eq 0 ]
    [ "$(cat "${HOME}/.config/environment.d/10-xdg-state.conf")" = 'XDG_STATE_HOME=${HOME}/.local/state' ]
    grep -q '^export XDG_STATE_HOME=' "${HOME}/.profile"
    [ -d "${HOME}/.local/state/sdlc" ]
    grep -q 'daemon-reexec' "${SYSTEMCTL_LOG}"
}

@test "second run is a no-op" {
    configure_xdg_state
    cp "${HOME}/.profile" "${TEST_TEMP_DIR}/profile.1"
    : >"${SYSTEMCTL_LOG}"
    run configure_xdg_state
    [ "$status" -eq 0 ]
    cmp "${HOME}/.profile" "${TEST_TEMP_DIR}/profile.1"
    ! grep -q 'daemon-reexec\|restart' "${SYSTEMCTL_LOG}"
}

@test "legacy registry and lock are moved" {
    mkdir -p "${HOME}/.sdlc"
    echo '{"runs":1}' >"${HOME}/.sdlc/registry.json"
    : >"${HOME}/.sdlc/registry.json.lock"
    configure_xdg_state
    [ ! -e "${HOME}/.sdlc/registry.json" ]
    [ ! -e "${HOME}/.sdlc/registry.json.lock" ]
    [ "$(cat "${HOME}/.local/state/sdlc/registry.json")" = '{"runs":1}' ]
    [ -e "${HOME}/.local/state/sdlc/registry.json.lock" ]
}

@test "both registries present: both stay and a warning is logged" {
    mkdir -p "${HOME}/.sdlc" "${HOME}/.local/state/sdlc"
    echo old >"${HOME}/.sdlc/registry.json"
    echo new >"${HOME}/.local/state/sdlc/registry.json"
    run configure_xdg_state
    [[ "${output}" == *"WARN: Both"* ]]
    [ "$(cat "${HOME}/.sdlc/registry.json")" = old ]
    [ "$(cat "${HOME}/.local/state/sdlc/registry.json")" = new ]
}

@test "herdr is never restarted, acmd is" {
    configure_xdg_state
    ! grep -q 'restart herdr' "${SYSTEMCTL_LOG}"
    grep -q 'restart acmd.service' "${SYSTEMCTL_LOG}"
}

@test "bootstrap source never restarts herdr from configure_xdg_state" {
    ! sed -n '/^configure_xdg_state() {/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh" | grep -q 'restart herdr'
}

@test "verify passes when all three checks hold" {
    mkdir -p "${HOME}/.local/state/sdlc"
    echo 'export XDG_STATE_HOME="x"' >"${HOME}/.profile"
    run check_xdg_state
    [[ "${output}" != *FAIL* ]]
    [ "$(grep -c '^PASS' <<<"${output}")" -eq 3 ]
}

@test "verify fails on each missing check" {
    export SYSTEMCTL_ENV=""
    run check_xdg_state
    [ "$(grep -c '^FAIL' <<<"${output}")" -eq 3 ]
}

@test "no systemd user manager: warns and skips systemctl actions" {
    systemctl() {
        echo "$*" >>"${SYSTEMCTL_LOG}"
        [[ "$2" == show-environment ]] && return 1
        return 0
    }
    run configure_xdg_state
    [ "$status" -eq 0 ]
    [[ "${output}" == *"WARN: No systemd user manager"* ]]
    [ -d "${HOME}/.local/state/sdlc" ]
    ! grep -q 'daemon-reexec\|restart' "${SYSTEMCTL_LOG}"
}

@test "drifted environment.d file is rewritten" {
    mkdir -p "${HOME}/.config/environment.d"
    echo 'XDG_STATE_HOME=/wrong' >"${HOME}/.config/environment.d/10-xdg-state.conf"
    configure_xdg_state
    [ "$(cat "${HOME}/.config/environment.d/10-xdg-state.conf")" = 'XDG_STATE_HOME=${HOME}/.local/state' ]
}

@test "acmd inactive: not restarted" {
    systemctl() {
        echo "$*" >>"${SYSTEMCTL_LOG}"
        case "$2" in
            show-environment) echo "XDG_STATE_HOME=/x" ;;
            is-active) return 3 ;;
        esac
        return 0
    }
    configure_xdg_state
    ! grep -q 'restart acmd' "${SYSTEMCTL_LOG}"
}

@test "user manager lacking the variable triggers daemon-reexec on an otherwise clean run" {
    configure_xdg_state
    : >"${SYSTEMCTL_LOG}"
    export SYSTEMCTL_ENV="PATH=/bin"
    configure_xdg_state
    grep -q 'daemon-reexec' "${SYSTEMCTL_LOG}"
}
