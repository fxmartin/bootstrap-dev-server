#!/usr/bin/env bats
# ABOUTME: Tests verify-server.sh geoip interface and Tailscale SSH checks
# ABOUTME: PATH-stubbed sudo/nft/geoip-shell/tailscale; offline and root-safe

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    mkdir -p "${STUB_DIR}"
    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; }
    warn() { echo "WARN: $1"; }
    info() { echo "INFO: $1"; }
    source <(sed -n '/^check_geoip_interfaces() {/,/^}$/p' "${PROJECT_ROOT}/tests/verify-server.sh")
    printf '#!/bin/sh\nexec "$@"\n' >"${STUB_DIR}/sudo"
    printf '#!/bin/sh\nexit 0\n' >"${STUB_DIR}/geoip-shell"
    chmod +x "${STUB_DIR}"/*
    export PATH="${STUB_DIR}:${PATH}"
    export NFT_OUT="" PREFS_OUT='{"RunSSH": false}'
    printf '#!/bin/sh\nprintf "%%s\\n" "$NFT_OUT"\n' >"${STUB_DIR}/nft"
    printf '#!/bin/sh\n[ "$1 $2" = "debug prefs" ] && printf "%%s\\n" "$PREFS_OUT"\n' >"${STUB_DIR}/tailscale"
    chmod +x "${STUB_DIR}"/*
}

teardown() {
    common_teardown
}

@test "fails when geoip-shell applies to all interfaces" {
    NFT_OUT='chain GEOIP-SHELL_ENABLE { ip saddr @allow accept }' run check_geoip_interfaces
    [[ "${output}" == *"FAIL: geoip-shell applies to ALL interfaces"* ]]
}

@test "fails when geoip-shell lists tailscale0" {
    NFT_OUT='iifname { "eth0", "tailscale0" } jump x' run check_geoip_interfaces
    [[ "${output}" == *"FAIL: geoip-shell applies to tailscale0"* ]]
}

@test "passes when geoip-shell is scoped to the public NIC" {
    NFT_OUT='iifname { "eth0" } jump x' run check_geoip_interfaces
    [[ "${output}" == *"PASS: geoip-shell is scoped"* ]]
    [[ "${output}" != *"FAIL"* ]]
}

@test "fails when Tailscale SSH is on" {
    NFT_OUT='iifname { "eth0" } jump x' PREFS_OUT='{
  "RunSSH": true
}' run check_geoip_interfaces
    [[ "${output}" == *"FAIL: Tailscale SSH is on"* ]]
}

@test "passes when Tailscale SSH is off" {
    NFT_OUT='iifname { "eth0" } jump x' run check_geoip_interfaces
    [[ "${output}" == *"PASS: Tailscale SSH is off"* ]]
}

@test "skips the interface check when geoip-shell is absent" {
    rm "${STUB_DIR}/geoip-shell"
    PATH="${STUB_DIR}:/usr/bin:/bin" run check_geoip_interfaces
    [[ "${output}" != *"FAIL"* ]]
}
