#!/usr/bin/env bats
# ABOUTME: Tests for tailnet-only SSH lockdown
# ABOUTME: The precondition matters most - a wrong answer locks the operator out

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1
    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"

    # Source the predicate under test
    # shellcheck source=../lib/tailscale.sh
    source "${PROJECT_ROOT}/lib/tailscale.sh"

    # Stub `tailscale` so tests never touch the real daemon
    export STUB_JSON="${TEST_TEMP_DIR}/ts.json"
    tailscale() {
        case "$1" in
            status) cat "${STUB_JSON}" ;;
            *) return 1 ;;
        esac
    }
    export -f tailscale
}

teardown() {
    common_teardown
}

write_status() {
    printf '%s\n' "$1" > "${STUB_JSON}"
}

# =============================================================================
# tailscale_key_never_expires
# =============================================================================
# This gates closing public SSH. A false positive means the node key can still
# expire, and when it does the operator is locked out to the Hetzner console.

@test "refuses when the node has a future key expiry (untagged)" {
    write_status '{"BackendState":"Running","Self":{"KeyExpiry":"2027-03-22T13:17:23Z"}}'
    run tailscale_key_never_expires
    [ "$status" -ne 0 ]
}

@test "accepts when the node reports no key expiry (tagged)" {
    write_status '{"BackendState":"Running","Self":{"KeyExpiry":null}}'
    run tailscale_key_never_expires
    [ "$status" -eq 0 ]
}

@test "accepts when the KeyExpiry field is absent entirely" {
    write_status '{"BackendState":"Running","Self":{"HostName":"dev-server"}}'
    run tailscale_key_never_expires
    [ "$status" -eq 0 ]
}

@test "refuses when the backend is not Running" {
    write_status '{"BackendState":"NeedsLogin","Self":{"KeyExpiry":null}}'
    run tailscale_key_never_expires
    [ "$status" -ne 0 ]
}

@test "refuses when tailscale is unavailable" {
    tailscale() { return 127; }
    export -f tailscale
    run tailscale_key_never_expires
    [ "$status" -ne 0 ]
}

@test "ignores a peer's KeyExpiry when Self has none" {
    # Peers carry their own expiry; only Self gates the lockdown.
    write_status '{"BackendState":"Running","Self":{"HostName":"dev-server"},"Peer":{"x":{"KeyExpiry":"2027-01-01T00:00:00Z"}}}'
    run tailscale_key_never_expires
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firewall Wiring
# =============================================================================

@test "SSH_TAILNET_ONLY defaults to false so a fresh bootstrap cannot lock itself out" {
    run grep -qE 'SSH_TAILNET_ONLY="\$\{SSH_TAILNET_ONLY:-false\}"' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

@test "firewall binds SSH to the tailscale interface in tailnet-only mode" {
    run grep -q 'ufw allow in on tailscale0 to any port' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

@test "tailnet-only mode is gated on the key-never-expires precondition" {
    run grep -q 'tailscale_key_never_expires' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

@test "failing the precondition keeps public SSH open rather than locking out" {
    # The refusal path must not fall through to closing the public rule.
    run grep -q 'refusing to close public SSH' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

@test "mosh follows SSH onto the tailnet, since mosh bootstraps over SSH" {
    run grep -q 'ufw allow in on tailscale0 to any port "${MOSH_PORT_START}' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Tailscale SSH Disabled
# =============================================================================
# `tailscale up --ssh` intercepts port 22 on the tailnet and demands an
# interactive browser check, which breaks headless and scripted access.

@test "bootstrap no longer suggests --ssh" {
    run grep -q 'tailscale up --ssh' "${BOOTSTRAP}"
    [ "$status" -ne 0 ]
}

@test "README no longer suggests --ssh" {
    run grep -q 'tailscale up --ssh' "${PROJECT_ROOT}/README.md"
    [ "$status" -ne 0 ]
}

@test "verify-server no longer suggests --ssh" {
    run grep -q 'tailscale up --ssh' "${PROJECT_ROOT}/tests/verify-server.sh"
    [ "$status" -ne 0 ]
}

@test "bootstrap still advertises a tag" {
    run grep -q 'advertise-tags' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}
