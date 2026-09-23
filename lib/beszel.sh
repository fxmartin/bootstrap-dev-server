#!/usr/bin/env bash
# ABOUTME: Shared helpers for Beszel agent installation
# ABOUTME: Provides the KEY-configured predicate used to gate systemd enablement

# Returns 0 when the Beszel env file declares a non-empty KEY.
#
# The agent exits 1 immediately without a KEY ("Failed to load public keys"),
# so enabling the unit without one leaves WantedBy=default.target to start a
# guaranteed-failing service on every boot. Callers must gate on this.
#
# Rejects: a missing file, an absent KEY line, an empty or whitespace-only
# value, and a commented-out KEY. Accepts quoted values.
beszel_key_configured() {
    local env_file="${1:-}"

    [[ -f "${env_file}" ]] || return 1

    local value
    value="$(sed -n 's/^[[:space:]]*KEY=//p' "${env_file}" | tail -n 1)"

    # Strip one layer of surrounding quotes before testing for emptiness
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    value="${value//[[:space:]]/}"

    [[ -n "${value}" ]]
}
