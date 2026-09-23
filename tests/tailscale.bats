#!/usr/bin/env bats
# ABOUTME: Tests for Tailscale install guidance and key-expiry handling
# ABOUTME: Guards against the 180-day node-key expiry that silently drops the server

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1
    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export VERIFY="${PROJECT_ROOT}/tests/verify-server.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# Install Guidance Tests
# =============================================================================
# Regression: bootstrap told the operator to run a bare `tailscale up --ssh`.
# That authenticates as a user, so the node key expires after 180 days and the
# server silently leaves the tailnet. Tagged nodes never expire.

@test "bootstrap recommends advertising a tag" {
    run grep -q 'advertise-tags' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

@test "every suggested 'tailscale up --ssh' carries --advertise-tags" {
    run bash -c "grep -o 'tailscale up --ssh[^\"]*' '${BOOTSTRAP}' | grep -v 'advertise-tags' || true"
    [ -z "${output}" ]
}

@test "README's tailscale up guidance carries --advertise-tags" {
    run bash -c "grep -o 'tailscale up --ssh.*' '${PROJECT_ROOT}/README.md' | grep -v 'advertise-tags' || true"
    [ -z "${output}" ]
}

@test "TAILSCALE_TAGS has a default" {
    run grep -qE 'TAILSCALE_TAGS="\$\{TAILSCALE_TAGS:-[^}]+\}"' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

@test "bootstrap mentions key expiry so the operator knows the failure mode" {
    run grep -qi 'key expiry\|key-expiry' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# verify-server.sh Coverage Tests
# =============================================================================
# The server sat off the tailnet for 34 days and Beszel crash-looped for
# months; neither was in the verification script's remit.

@test "verify-server checks tailscale backend state" {
    run grep -q 'BackendState\|tailscale status' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server fails on NeedsLogin" {
    run grep -q 'NeedsLogin' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server warns on an approaching key expiry" {
    run grep -q 'KeyExpiry' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server checks the beszel agent unit" {
    run grep -q 'beszel-agent' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server detects an enabled-but-failing unit" {
    # is-active alone reports 'activating' for a crash-looping unit, which is
    # neither active nor failed - the check must not treat that as healthy.
    run grep -q 'activating' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server documents the new sections in its coverage header" {
    run grep -qi '13\..*Tailscale\|Tailscale.*13\.' "${VERIFY}"
    [ "${status}" -eq 0 ]
    run grep -qi '14\..*Monitoring\|Monitoring.*14\.' "${VERIFY}"
    [ "${status}" -eq 0 ]
}
