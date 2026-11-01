#!/usr/bin/env bash
# ABOUTME: ExecStart wrapper for ntfy.service - binds ntfy to the Tailscale IPv4 only,
# ABOUTME: waiting with bounded backoff for the tailnet to come up
#
# ntfy must never be reachable from the public internet:
#   1. this wrapper binds to the Tailscale address only - never 0.0.0.0. If no
#      tailnet address exists it exits non-zero rather than fall back.
#   2. UFW opens 2586 on tailscale0 only (bootstrap-dev-server.sh, and the
#      installer for standalone use)
#   3. the Tailscale ACL decides which tailnet node may reach dev-server:2586
#
# Installed to /usr/local/bin/ntfy-start by scripts/install-ntfy.sh. Every path
# and the backoff are env-overridable so tests/ntfy.bats can run it without a tailnet.

set -euo pipefail

NTFY_BIN="${NTFY_BIN:-/usr/local/bin/ntfy}"
NTFY_PORT="${NTFY_PORT:-2586}"
NTFY_CONFIG_FILE="${NTFY_CONFIG_FILE:-/etc/ntfy/server.yml}"
TAILSCALE_BIN="${TAILSCALE_BIN:-tailscale}"

# 12 x 10 s covers tailscaled coming up after boot. Past that the unit fails,
# and ntfy.service's StartLimit stops the restart loop.
TAILNET_WAIT_ATTEMPTS="${TAILNET_WAIT_ATTEMPTS:-12}"
TAILNET_WAIT_SECONDS="${TAILNET_WAIT_SECONDS:-10}"

# Prints the node's Tailscale IPv4, or fails while the tailnet is down. Only a
# CGNAT (100.64.0.0/10) address is accepted: anything else is not a tailnet
# address and must never become the bind address.
tailscale_ipv4() {
    local ip
    ip="$("${TAILSCALE_BIN}" ip -4 2>/dev/null | head -n 1 || true)"
    [[ "${ip}" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+$ ]] || return 1
    echo "${ip}"
}

wait_for_tailnet() {
    local attempt ip
    for ((attempt = 1; attempt <= TAILNET_WAIT_ATTEMPTS; attempt++)); do
        if ip="$(tailscale_ipv4)"; then
            echo "${ip}"
            return 0
        fi
        if ((attempt < TAILNET_WAIT_ATTEMPTS)); then
            echo "ntfy-start: no Tailscale IPv4 yet (attempt ${attempt}/${TAILNET_WAIT_ATTEMPTS}), retrying in ${TAILNET_WAIT_SECONDS}s" >&2
            sleep "${TAILNET_WAIT_SECONDS}"
        fi
    done
    return 1
}

main() {
    local ip
    if ! ip="$(wait_for_tailnet)"; then
        echo "ntfy-start: no Tailscale IPv4 after ${TAILNET_WAIT_ATTEMPTS} attempts - refusing to start rather than bind publicly" >&2
        exit 1
    fi

    exec "${NTFY_BIN}" serve \
        --config "${NTFY_CONFIG_FILE}" \
        --listen-http "${ip}:${NTFY_PORT}" \
        --base-url "http://${ip}:${NTFY_PORT}" \
        "$@"
}

main "$@"
