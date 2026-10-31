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
# The server sat off the tailnet for 34 days and the monitoring agent
# crash-looped for months; neither was in the verification script's remit.

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

@test "verify-server checks the node-exporter unit" {
    run grep -q 'node-exporter' "${VERIFY}"
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

# =============================================================================
# Tailnet tag: must match the policy's tagOwners (tag:trusted), never tag:server
# =============================================================================

# Run verify-server.sh section 13 against a stubbed `tailscale status --json`.
run_section_13() {
    local json="$1" stubdir="${BATS_TEST_TMPDIR}/ts-stub"
    mkdir -p "${stubdir}"
    printf '#!/bin/sh\nif [ "$1" = ip ]; then echo 100.64.0.1; else cat "%s/status.json"; fi\n' "${stubdir}" >"${stubdir}/tailscale"
    chmod +x "${stubdir}/tailscale"
    printf '%s' "${json}" >"${stubdir}/status.json"
    {
        echo 'TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:trusted}"'
        echo 'pass() { echo "PASS: $1"; }; warn() { echo "WARN: $1"; }; fail() { echo "FAIL: $1"; }; info() { :; }; header() { :; }'
        sed -n '/^header "13\. Tailscale Tests"/,/^header "14\./p' "${VERIFY}" | sed '$d'
    } >"${stubdir}/section.sh"
    PATH="${stubdir}:${PATH}" run bash "${stubdir}/section.sh"
}

@test "no tag:server remains in bootstrap, README, runbook, CLAUDE.md or verify-server" {
    run grep -n 'tag:server' "${BOOTSTRAP}" "${VERIFY}" "${PROJECT_ROOT}/README.md" \
        "${PROJECT_ROOT}/docs/fleet-onboarding.md" "${PROJECT_ROOT}/CLAUDE.md"
    [ "${status}" -ne 0 ]
}

@test "TAILSCALE_TAGS defaults to tag:trusted in bootstrap and verify-server" {
    grep -qF 'TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:trusted}"' "${BOOTSTRAP}"
    grep -qF 'TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:trusted}"' "${VERIFY}"
}

@test "verify-server hints name \${TAILSCALE_TAGS}" {
    grep -F 'NeedsLogin' "${VERIFY}" | grep -qF '${TAILSCALE_TAGS}'
}

@test "README and runbook carry no tagOwners or tag:nas ACL snippets" {
    run grep -nE 'tagOwners": |tag:nas' "${PROJECT_ROOT}/README.md" "${PROJECT_ROOT}/docs/fleet-onboarding.md"
    [ "${status}" -ne 0 ]
}

@test "runbook warns about logout on tag change and forbids --reset" {
    grep -qi 'logs it out' "${PROJECT_ROOT}/docs/fleet-onboarding.md"
    grep -qE 'never use `--reset`' "${PROJECT_ROOT}/docs/fleet-onboarding.md"
}

@test "13.2: tagged node with a key expiry gets the tagged-with-expiry warning" {
    run_section_13 '{"BackendState": "Running", "Self": {"Tags": ["tag:trusted"], "KeyExpiry": "2099-01-01T00:00:00Z"}, "Peer": {}}'
    [[ "${output}" == *"is tagged (tag:trusted), but key expiry is still on"* ]]
    [[ "${output}" != *"untagged"* ]]
}

@test "13.2: pretty-printed Tags array is read" {
    run_section_13 $'{\n "Self": {\n  "Tags": [\n   "tag:trusted"\n  ],\n  "KeyExpiry": "2099-01-01T00:00:00Z"\n },\n "Peer": {}\n}'
    [[ "${output}" == *"is tagged (tag:trusted)"* ]]
}

@test "13.2: no Tags and a key expiry gets the untagged warning" {
    run_section_13 '{"BackendState": "Running", "Self": {"Tags": null, "KeyExpiry": "2099-01-01T00:00:00Z"}, "Peer": {}}'
    [[ "${output}" == *"untagged node"* ]]
}

@test "13.2: tagged node with no key expiry passes" {
    run_section_13 '{"BackendState": "Running", "Self": {"Tags": ["tag:trusted"], "KeyExpiry": null}, "Peer": {}}'
    [[ "${output}" == *"PASS: Tailscale node key does not expire"* ]]
    [[ "${output}" != *"WARN"* ]]
}

@test "13.2: a peer's tags do not make an untagged Self look tagged" {
    run_section_13 '{"Self": {"KeyExpiry": "2099-01-01T00:00:00Z"}, "Peer": {"x": {"Tags": ["tag:home-lab"]}}}'
    [[ "${output}" == *"untagged node"* ]]
}

@test "verify-server GitLab failure hints name \${TAILSCALE_TAGS}, not a literal tag" {
    grep -F 'does not answer' "${VERIFY}" | grep -qF '${TAILSCALE_TAGS}'
    grep -F 'does not resolve' "${VERIFY}" | grep -qF -- '--advertise-tags=${TAILSCALE_TAGS}'
}
