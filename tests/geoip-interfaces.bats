#!/usr/bin/env bats
# ABOUTME: Tests geoip-shell interface selection and the install/reconfigure paths
# ABOUTME: PATH-stubbed ip/sudo/geoip-shell; offline and root-safe

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export CALLS="${TEST_TEMP_DIR}/calls"
    mkdir -p "${STUB_DIR}"
    : >"${CALLS}"
    unset GEOIP_IFACES
    printf '#!/bin/sh\necho "default via 10.0.0.1 dev eth0 proto dhcp src 1.2.3.4 metric 100"\n' >"${STUB_DIR}/ip"
    printf '#!/bin/sh\necho "$@" >>"%s"\n[ -n "$GEOIP_FAIL" ] && exit 1\nexit 0\n' "${CALLS}" >"${STUB_DIR}/geoip-shell"
    printf '#!/bin/sh\nexec "$@"\n' >"${STUB_DIR}/sudo"
    chmod +x "${STUB_DIR}"/*
    export PATH="${STUB_DIR}:${PATH}"
    source "${PROJECT_ROOT}/lib/geoip.sh"
    source "${PROJECT_ROOT}/lib/logging.sh"
}

teardown() {
    common_teardown
}

load_installer() {
    export REPO_CLONE_DIR="${PROJECT_ROOT}" BOOTSTRAP_SUBDIR="." GEOIP_ENABLED=true GEOIP_COUNTRIES="LU,FR,GR"
    source <(sed -n '/^install_geoip_shell() {/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")
}

@test "detects the default-route interface" {
    run geoip_interfaces
    [ "${status}" -eq 0 ]
    [ "${output}" = "eth0" ]
}

@test "GEOIP_IFACES overrides detection" {
    GEOIP_IFACES="enp1s0" run geoip_interfaces
    [ "${output}" = "enp1s0" ]
}

@test "refuses 'all' and tailscale0 in the override" {
    GEOIP_IFACES="all" run geoip_interfaces
    [ "${status}" -ne 0 ]
    GEOIP_IFACES="eth0 tailscale0" run geoip_interfaces
    [ "${status}" -ne 0 ]
}

@test "fails with no output when no default route exists" {
    printf '#!/bin/sh\nexit 0\n' >"${STUB_DIR}/ip"
    run geoip_interfaces
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
}

@test "refuses a default route that goes over tailscale0 (exit node)" {
    printf '#!/bin/sh\necho "default dev tailscale0 scope link"\n' >"${STUB_DIR}/ip"
    run geoip_interfaces
    [ "${status}" -ne 0 ]
}

@test "reconfigure path passes -i <iface>, never -i all" {
    load_installer
    run install_geoip_shell
    [ "${status}" -eq 0 ]
    grep -q -- '-i eth0 ' "${CALLS}"
    ! grep -q -- '-i all' "${CALLS}"
}

@test "reconfigure path fails loudly when geoip-shell fails" {
    load_installer
    GEOIP_FAIL=1 run install_geoip_shell
    [ "${status}" -ne 0 ]
}

@test "no interface: skips geoblocking and never configures" {
    printf '#!/bin/sh\nexit 0\n' >"${STUB_DIR}/ip"
    load_installer
    run install_geoip_shell
    [ "${status}" -ne 0 ]
    [ ! -s "${CALLS}" ]
}

@test "bootstrap no longer hardcodes -i all" {
    run grep -n -- 'configure.* -i all' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "${status}" -ne 0 ]
}

@test "accepts a comma-separated override and normalises it to spaces" {
    GEOIP_IFACES="eth0,eth1" run geoip_interfaces
    [ "${status}" -eq 0 ]
    [ "${output}" = "eth0 eth1" ]
}

@test "refuses an override that mixes a public NIC with tailscale0" {
    GEOIP_IFACES="eth0,tailscale0" run geoip_interfaces
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
}

@test "whitespace-only override yields no interface" {
    GEOIP_IFACES="   " run geoip_interfaces
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
}

@test "install aborts when lib/geoip.sh is missing" {
    load_installer
    BOOTSTRAP_SUBDIR="no-such-dir" run install_geoip_shell
    [ "${status}" -ne 0 ]
    [ ! -s "${CALLS}" ]
}
