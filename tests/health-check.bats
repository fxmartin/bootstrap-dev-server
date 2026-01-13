#!/usr/bin/env bats
# ABOUTME: Tests for scripts/health-check.sh
# ABOUTME: Tests system health check functions and output formatting

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1
}

teardown() {
    common_teardown
}

# =============================================================================
# Version Tests
# =============================================================================

@test "health-check --version outputs version" {
    run bash "${PROJECT_ROOT}/scripts/health-check.sh" --version
    [ "$status" -eq 0 ]
    assert_contains "${output}" "health-check"
}

@test "health-check -v outputs version" {
    run bash "${PROJECT_ROOT}/scripts/health-check.sh" -v
    [ "$status" -eq 0 ]
    assert_contains "${output}" "health-check"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "GENERATION_WARNING_THRESHOLD is defined" {
    run grep "GENERATION_WARNING_THRESHOLD" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "DISK_WARNING_GB is defined" {
    run grep "DISK_WARNING_GB" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "CACHE_WARNING_KB is defined" {
    run grep "CACHE_WARNING_KB" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Helper Function Tests
# =============================================================================

@test "print_status function exists" {
    run grep "print_status()" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "print_status handles ok status" {
    run grep 'ok)' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "print_status handles warn status" {
    run grep 'warn)' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "print_status handles error status" {
    run grep 'error)' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "get_cache_kb function exists" {
    run grep "get_cache_kb()" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "get_cache_human function exists" {
    run grep "get_cache_human()" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Hardening Check Tests
# =============================================================================

@test "checks SSH hardening config exists" {
    run grep "SSH_HARDENING_FILE" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks PermitRootLogin setting" {
    run grep "PermitRootLogin no" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks PasswordAuthentication setting" {
    run grep "PasswordAuthentication no" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firewall Check Tests
# =============================================================================

@test "checks UFW is active" {
    run grep "Status: active" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks SSH port is allowed" {
    run grep 'grep -q "22"' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Mosh ports are configured" {
    run grep "60000:60010" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Fail2Ban Check Tests
# =============================================================================

@test "checks Fail2Ban is installed" {
    run grep "fail2ban-client" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Fail2Ban service is running" {
    run grep "systemctl is-active.*fail2ban" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Fail2Ban SSH jail" {
    run grep "fail2ban-client status sshd" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Services Check Tests
# =============================================================================

@test "checks Nix daemon" {
    run grep "nix-daemon" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks SSH service" {
    run grep "sshd\|ssh.service\|ssh 2" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Disk Space Check Tests
# =============================================================================

@test "checks /nix partition" {
    run grep 'df -k /nix\|df -h /nix' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks home directory space" {
    run grep 'df -h ~' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Nix Store Check Tests
# =============================================================================

@test "checks Nix store size" {
    run grep "/nix/store" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks user generations" {
    run grep "profiles/per-user" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Dev Cache Check Tests
# =============================================================================

@test "checks uv cache" {
    run grep ".cache/uv" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks npm cache" {
    run grep ".npm" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks pnpm cache" {
    run grep "pnpm" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Claude Code Check Tests
# =============================================================================

@test "checks Claude Code availability" {
    run grep "command -v claude" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Claude version" {
    run grep "claude --version" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# MCP Server Check Tests
# =============================================================================

@test "checks MCP config file" {
    run grep "config.json" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Context7 MCP server" {
    run grep "context7" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks GitHub MCP server" {
    run grep '"github"' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks Sequential Thinking MCP server" {
    run grep "sequential-thinking" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Dev Tools Check Tests
# =============================================================================

@test "checks gh tool" {
    run grep "gh" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks rg (ripgrep) tool" {
    run grep "rg" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks fd tool" {
    run grep "fd" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks bat tool" {
    run grep "bat" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks fzf tool" {
    run grep "fzf" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "checks lazygit tool" {
    run grep "lazygit" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "outputs header" {
    run grep "System Health Check" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "outputs hostname" {
    run grep "hostname" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "outputs date" {
    run grep "date" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "outputs quick commands section" {
    run grep "Quick commands" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "suggests nix-collect-garbage" {
    run grep "nix-collect-garbage" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

@test "suggests nix store optimise" {
    run grep "nix store optimise" "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "uses set -euo pipefail" {
    run head -25 "${PROJECT_ROOT}/scripts/health-check.sh"
    assert_contains "${output}" "set -euo pipefail"
}

@test "handles missing directories gracefully" {
    run grep '2>/dev/null' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# ABOUTME Tests
# =============================================================================

@test "has ABOUTME comment" {
    run head -5 "${PROJECT_ROOT}/scripts/health-check.sh"
    assert_contains "${output}" "ABOUTME"
}
