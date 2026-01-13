#!/usr/bin/env bats
# ABOUTME: Tests for flake.nix configuration
# ABOUTME: Validates Nix flake structure and package definitions

load 'test_helper'

setup() {
    common_setup
    export NO_COLOR=1
}

teardown() {
    common_teardown
}

# =============================================================================
# Flake Structure Tests
# =============================================================================

@test "flake.nix exists" {
    assert_file_exists "${PROJECT_ROOT}/flake.nix"
}

@test "flake.lock exists" {
    assert_file_exists "${PROJECT_ROOT}/flake.lock"
}

@test "flake has description" {
    run grep "description" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake uses nixpkgs input" {
    run grep "nixpkgs" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Dev Shell Tests
# =============================================================================

@test "flake defines devShells" {
    run grep "devShells" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake has default devShell" {
    run grep "default" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake has minimal devShell" {
    run grep "minimal" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake has python devShell" {
    run grep "python" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Package Inclusion Tests
# =============================================================================

@test "flake includes Claude Code" {
    run grep -i "claude" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes git" {
    run grep "git" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes ripgrep" {
    run grep "ripgrep" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes fd" {
    run grep "fd" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes fzf" {
    run grep "fzf" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes bat" {
    run grep "bat" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes lazygit" {
    run grep "lazygit" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes gh (GitHub CLI)" {
    run grep "gh" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes tmux" {
    run grep "tmux" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes mosh" {
    run grep "mosh" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Python Environment Tests
# =============================================================================

@test "flake includes Python" {
    run grep -i "python" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes uv package manager" {
    run grep "uv" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes ruff linter" {
    run grep "ruff" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Node.js Environment Tests
# =============================================================================

@test "flake includes Node.js" {
    run grep -i "node" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes bun runtime" {
    run grep "bun" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes pnpm" {
    run grep "pnpm" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Container Tools Tests
# =============================================================================

@test "flake includes podman" {
    run grep "podman" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Shell Script Tools Tests
# =============================================================================

@test "flake includes shellcheck" {
    run grep "shellcheck" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes shfmt" {
    run grep "shfmt" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes bats" {
    run grep "bats" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Nix Tools Tests
# =============================================================================

@test "flake includes nil (Nix language server)" {
    run grep "nil" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes nixfmt" {
    run grep "nixfmt" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Editor Tests
# =============================================================================

@test "flake includes neovim" {
    run grep -i "neovim\|nvim" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake includes helix" {
    run grep -i "helix" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "flake allows unfree packages" {
    run grep "allowUnfree" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "flake defines shellHook" {
    run grep "shellHook" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Syntax Validation Tests
# =============================================================================

@test "flake has valid nix syntax" {
    if command -v nix &>/dev/null; then
        run nix-instantiate --parse "${PROJECT_ROOT}/flake.nix"
        [ "$status" -eq 0 ]
    else
        skip "nix not available"
    fi
}

@test "flake check passes" {
    if command -v nix &>/dev/null; then
        run nix flake check "${PROJECT_ROOT}" --no-build
        [ "$status" -eq 0 ]
    else
        skip "nix not available"
    fi
}
