#!/usr/bin/env bash
# ABOUTME: Shared helpers for Tailscale state inspection
# ABOUTME: Provides the key-expiry predicate that gates closing public SSH

# Returns 0 only when this node's key will never expire, i.e. it is tagged
# (tailnet-owned) or has expiry disabled in the admin console.
#
# This gates the tailnet-only SSH lockdown. An untagged node key expires after
# 180 days; if public SSH is already closed when that happens, the only way
# back in is the Hetzner web console. Fails closed: any doubt returns non-zero.
#
# jq is not installed on the server outside the dev shell, hence the string
# parsing. Only Self is consulted - peers carry their own KeyExpiry values.
tailscale_key_never_expires() {
    local status_json
    status_json="$(tailscale status --json 2>/dev/null)" || return 1
    [[ -n "${status_json}" ]] || return 1

    # The backend must actually be authenticated for the answer to mean anything
    local backend
    backend="$(echo "${status_json}" | grep -o '"BackendState": *"[^"]*"' | head -1 | cut -d'"' -f4)"
    [[ "${backend}" == "Running" ]] || return 1

    # Scope to Self, which precedes Peer in the output. Truncating on the
    # "Peer" key works whether the JSON is pretty-printed or compact.
    local self_json expiry
    self_json="${status_json%%\"Peer\":*}"
    expiry="$(echo "${self_json}" | grep -o '"KeyExpiry": *"[^"]*"' | head -1 | cut -d'"' -f4)"

    [[ -z "${expiry}" || "${expiry}" == "null" ]]
}
