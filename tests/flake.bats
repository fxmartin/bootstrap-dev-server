#!/usr/bin/env bats
# ABOUTME: Tests for flake.nix configuration
# ABOUTME: Validates Nix flake structure and package definitions

load 'test_helper'

bats_require_minimum_version 1.5.0

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

@test "flake does not include mosh (installed via apt so the server side survives dev shell exits)" {
    run grep "mosh" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
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

@test "flake does not pin python312 (uncached on nixos-unstable, forces source builds)" {
    run grep -E "python312" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
}

@test "flake python devShells use pkgs.python3 (tracks nixpkgs default/cached interpreter)" {
    run grep -c "pkgs\.python3\b" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "flake python devShells use pkgs.python3Packages (tracks nixpkgs default/cached interpreter)" {
    run grep -c "pkgs\.python3Packages\." "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "flake preserves python3Packages toolchain members after python312 rename" {
    for pkg in pip virtualenv isort mypy pylint flake8 pytest; do
        run grep -qE "pkgs\.python3Packages\.${pkg}\b" "${PROJECT_ROOT}/flake.nix"
        [ "$status" -eq 0 ]
    done
}

@test "flake default devShell (dev-server) uses pkgs.python3 as its interpreter" {
    # The package list is shared with dev-env, so the interpreter lives in devPackages.
    run bash -c "sed -n '/devPackages = \\[/,/^        \\];/p' '${PROJECT_ROOT}/flake.nix' | grep -qE 'pkgs\.python3\$'"
    [ "$status" -eq 0 ]
}

@test "devPackages carries the sdlc fleet worker's scanners and Go" {
    # fleet-bootstrap.sh refuses to install the worker without semgrep and
    # osv-scanner; Go repos (agentic-coding-monitor) need go for preflight.
    for pkg in semgrep osv-scanner go; do
        run bash -c "sed -n '/devPackages = \\[/,/^        \\];/p' '${PROJECT_ROOT}/flake.nix' | grep -qE 'pkgs\\.${pkg}\\b'"
        [ "$status" -eq 0 ]
    done
}

@test "flake does not use removed nodePackages aliases (dropped from nixpkgs unstable)" {
    run grep "nodePackages" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
}

@test "flake node toolchain uses top-level packages" {
    for pkg in typescript typescript-language-server eslint prettier; do
        run grep -E "pkgs\.${pkg} " "${PROJECT_ROOT}/flake.nix"
        [ "$status" -eq 0 ]
    done
}

@test "flake python devShell (python-dev) uses pkgs.python3 as its interpreter" {
    run bash -c "sed -n '/name = \"python-dev\"/,\$p' '${PROJECT_ROOT}/flake.nix' | grep -qE 'pkgs\.python3\$'"
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

@test "flake does not include helix (removed from dev shell)" {
    run grep -i "helix" "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
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

# =============================================================================
# Herdr Tests
# =============================================================================

@test "flake provides herdr in the default shell" {
    run grep -q 'pkgs.herdr' "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "herdr resolves from the locked nixpkgs for the server arch" {
    # The January pin predated the package entirely; the lock must have moved.
    command -v nix &>/dev/null || skip "nix not available"
    run nix eval --raw "${PROJECT_ROOT}#nixpkgs-unused" --apply "_: 1" 2>/dev/null
    run nix eval --raw --impure --expr \
        "(builtins.getFlake \"${PROJECT_ROOT}\").inputs.nixpkgs.legacyPackages.x86_64-linux.herdr.version"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# MCP Removal Tests
# =============================================================================
# MCP servers were dropped: Context7 and Sequential Thinking added a
# mcp-servers-nix input that pinned Node.js to v22 and blocked nixpkgs
# upgrades (see mcp-servers-nix#285). GitHub operations already use `gh`.

@test "flake has no mcp-servers-nix input" {
    run grep -q 'mcp-servers-nix' "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
}

@test "flake shell hooks reference no MCP package outputs" {
    run grep -q 'context7-mcp\|mcp-server-sequential-thinking\|sequentialThinkingMcp' "${PROJECT_ROOT}/flake.nix"
    [ "$status" -ne 0 ]
}

@test "flake never mentions mcpServers: no dev shell adds or prunes them" {
    run ! grep -q 'mcpServers' "${PROJECT_ROOT}/flake.nix"
}

@test "flake.lock has no mcp-servers-nix node" {
    run grep -q 'mcp-servers-nix' "${PROJECT_ROOT}/flake.lock"
    [ "$status" -ne 0 ]
}

@test "setup-dev-env.sh prunes stale MCP entries from ~/.claude.json" {
    # Entries left behind point at /nix/store paths that get garbage-collected,
    # so Claude Code would fail to start those servers on every launch.
    run grep -q 'del(.mcpServers' "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
}

@test "health-check.sh no longer checks MCP servers" {
    run grep -qi 'mcp' "${PROJECT_ROOT}/scripts/health-check.sh"
    [ "$status" -ne 0 ]
}

@test "verify-server.sh checks for stale MCP entries instead of configuring them" {
    run grep -q 'mcp-servers-nix' "${PROJECT_ROOT}/tests/verify-server.sh"
    [ "$status" -ne 0 ]
    run grep -q 'Stale MCP entries' "${PROJECT_ROOT}/tests/verify-server.sh"
    [ "$status" -eq 0 ]
}

@test "verify-server.sh points stale MCP entries at the script that prunes them" {
    run grep -q 'Stale MCP entries.*setup-dev-env\.sh' "${PROJECT_ROOT}/tests/verify-server.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# dev-env Profile Tests
# =============================================================================
# The toolset is installed as the user's default Nix profile so it is on PATH in
# every context. These tests never touch a real Nix: `nix` is a stub that logs
# its argv, and every path lives under the temp HOME.

setup_profile_stubs() {
    export HOME="${MOCK_HOME}"
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export NIX_LOG="${TEST_TEMP_DIR}/nix.log"
    export PROFILE_JSON="${TEST_TEMP_DIR}/profile.json"
    mkdir -p "${STUB_DIR}"
    : >"${NIX_LOG}"
    echo '{"elements":{},"version":3}' >"${PROFILE_JSON}"
    cat >"${STUB_DIR}/nix" <<STUB
#!/usr/bin/env bash
echo "nix \$*" >>"${NIX_LOG}"
if [[ "\${1:-}" == "profile" && "\${2:-}" == "list" ]]; then cat "${PROFILE_JSON}"; fi
if [[ "\${1:-}" == "build" && -n "\${STUB_NIX_BUILD_FAIL:-}" ]]; then exit 1; fi
STUB
    cat >"${STUB_DIR}/sudo" <<'STUB'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
STUB
    chmod +x "${STUB_DIR}/nix" "${STUB_DIR}/sudo"
    export PATH="${STUB_DIR}:${PATH}"
}

load_profile_function() {
    local fn="$1"
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    # shellcheck disable=SC1090
    source <(sed -n "/^${fn}()/,/^}\$/p" "${PROJECT_ROOT}/bootstrap-dev-server.sh")
}

# PATH holds only the stubs and what the function shells out to, so no jq is reachable.
install_dev_profile_without_jq() {
    local tool
    for tool in bash cat grep; do
        ln -sf "$(command -v "${tool}")" "${STUB_DIR}/${tool}"
    done
    local PATH="${STUB_DIR}"
    install_dev_profile
}

@test "flake exposes packages.dev-env as a buildEnv" {
    run grep -qE 'packages\.dev-env *= *pkgs\.buildEnv' "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

@test "dev-env and the default devShell share one devPackages list" {
    run grep -cE 'paths = devPackages;' "${PROJECT_ROOT}/flake.nix"
    [ "$output" -eq 1 ]
    run grep -cE 'buildInputs = devPackages;' "${PROJECT_ROOT}/flake.nix"
    [ "$output" -eq 1 ]
    # defined exactly once, as a let binding
    run grep -cE '^ +devPackages = \[' "${PROJECT_ROOT}/flake.nix"
    [ "$output" -eq 1 ]
}

@test "the default devShell no longer carries its own package list" {
    run bash -c "sed -n '/devShells\.default = /,/shellHook/p' '${PROJECT_ROOT}/flake.nix' | grep -v 'pkgs\\.mkShell' | grep -c 'pkgs\\.' || true"
    [ "$output" -eq 0 ]
}

@test "default shellHook no longer performs setup side effects" {
    local hook
    hook="$(sed -n '/devShells\.default = /,/devShells\.minimal/p' "${PROJECT_ROOT}/flake.nix")"
    [[ "${hook}" != *"ensure_symlink"* ]]
    [[ "${hook}" != *".msmtprc"* ]]
    [[ "${hook}" != *"ZSHEOF"* ]]
    [[ "${hook}" != *"mcpServers"* ]]
}

@test "dev shells still exist: default, minimal and python" {
    for shell in default minimal python; do
        run grep -qE "devShells\.${shell} = pkgs\.mkShell" "${PROJECT_ROOT}/flake.nix"
        [ "$status" -eq 0 ]
    done
}

@test "bootstrap installs the profile with the repo flake reference on first run" {
    setup_profile_stubs
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    grep -qF "nix profile install ${HOME}/.config/nix-dev-env#dev-env" "${NIX_LOG}"
    run ! grep -q "nix profile upgrade" "${NIX_LOG}"
}

@test "bootstrap upgrades instead of reinstalling when dev-env is already in the profile" {
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"dev-env":{"attrPath":"packages.x86_64-linux.dev-env","originalUrl":"path:/home/fx/.config/nix-dev-env","storePaths":["/nix/store/aaa-dev-env"]}},"version":3}
JSON
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    grep -qF "nix profile upgrade dev-env" "${NIX_LOG}"
    run ! grep -q "nix profile install" "${NIX_LOG}"
    run ! grep -q "nix profile remove" "${NIX_LOG}"
}

@test "bootstrap's first install refuses lock updates: an uncovered flake.nix fails, never locks on the box" {
    setup_profile_stubs
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    grep -qF "nix profile install ${HOME}/.config/nix-dev-env#dev-env --no-update-lock-file" "${NIX_LOG}"
}

@test "bootstrap's upgrade refuses lock updates: an uncovered flake.nix fails, never locks on the box" {
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"dev-env":{"attrPath":"packages.x86_64-linux.dev-env","originalUrl":"path:/home/fx/.config/nix-dev-env","storePaths":["/nix/store/aaa-dev-env"]}},"version":3}
JSON
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    grep -qF "nix profile upgrade dev-env --no-update-lock-file" "${NIX_LOG}"
}

@test "bootstrap removes stray profile entries, logs them, and keeps dev-env" {
    command -v jq &>/dev/null || skip "jq not available"
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{
 "herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","originalUrl":"flake:nixpkgs","storePaths":["/nix/store/bbb-herdr-0.9.1"]},
 "dev-env":{"attrPath":"packages.x86_64-linux.dev-env","originalUrl":"path:/home/fx/.config/nix-dev-env","storePaths":["/nix/store/aaa-dev-env"]}
},"version":3}
JSON
    load_profile_function install_dev_profile
    run --separate-stderr install_dev_profile
    [ "$status" -eq 0 ]
    [[ "${stderr}" == *"Removing stray profile entry 'herdr'"* ]]
    grep -qF "nix profile remove herdr" "${NIX_LOG}"
    run ! grep -qF "nix profile remove dev-env" "${NIX_LOG}"
}

@test "strays are removed before the install so they cannot collide with dev-env" {
    command -v jq &>/dev/null || skip "jq not available"
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","storePaths":["/nix/store/bbb-herdr-0.9.1"]}},"version":3}
JSON
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    local remove_line install_line
    remove_line="$(grep -n 'nix profile remove' "${NIX_LOG}" | cut -d: -f1)"
    install_line="$(grep -n 'nix profile install' "${NIX_LOG}" | cut -d: -f1)"
    [ "${remove_line}" -lt "${install_line}" ]
}

@test "a failing dev-env build removes nothing and fails the step" {
    command -v jq &>/dev/null || skip "jq not available"
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","storePaths":["/nix/store/bbb-herdr-0.9.1"]}},"version":3}
JSON
    export STUB_NIX_BUILD_FAIL=1
    load_profile_function install_dev_profile
    run --separate-stderr install_dev_profile
    [ "$status" -ne 0 ]
    [[ "${stderr}" == *"left untouched"* ]]
    grep -qF "nix build ${HOME}/.config/nix-dev-env#dev-env --no-update-lock-file --no-link" "${NIX_LOG}"
    run ! grep -q "nix profile remove" "${NIX_LOG}"
    run ! grep -q "nix profile install" "${NIX_LOG}"
}

@test "a successful build precedes the stray removal and the install" {
    command -v jq &>/dev/null || skip "jq not available"
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","storePaths":["/nix/store/bbb-herdr-0.9.1"]}},"version":3}
JSON
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -eq 0 ]
    local build_line remove_line install_line
    build_line="$(grep -n 'nix build' "${NIX_LOG}" | cut -d: -f1)"
    remove_line="$(grep -n 'nix profile remove' "${NIX_LOG}" | cut -d: -f1)"
    install_line="$(grep -n 'nix profile install' "${NIX_LOG}" | cut -d: -f1)"
    [ "${build_line}" -lt "${remove_line}" ]
    [ "${remove_line}" -lt "${install_line}" ]
}

@test "a failing build with dev-env already installed neither upgrades nor removes" {
    command -v jq &>/dev/null || skip "jq not available"
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{
 "herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","storePaths":["/nix/store/bbb-herdr-0.9.1"]},
 "dev-env":{"attrPath":"packages.x86_64-linux.dev-env","storePaths":["/nix/store/aaa-dev-env"]}
},"version":3}
JSON
    export STUB_NIX_BUILD_FAIL=1
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -ne 0 ]
    run ! grep -q "nix profile remove" "${NIX_LOG}"
    run ! grep -q "nix profile upgrade" "${NIX_LOG}"
}

@test "the apt base packages provide jq for the stray check" {
    # A profile that can hold a stray predates dev-env, so it has no jq of its own.
    local base_packages
    base_packages="$(sed -n '/^install_base_packages()/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")"
    grep -qE '^ +jq \\$' <<<"${base_packages}"
}

@test "a profile with entries fails without jq rather than collide on install" {
    setup_profile_stubs
    cat >"${PROFILE_JSON}" <<'JSON'
{"elements":{"herdr":{"attrPath":"legacyPackages.x86_64-linux.herdr","storePaths":["/nix/store/bbb-herdr-0.9.1"]}},"version":3}
JSON
    load_profile_function install_dev_profile
    run --separate-stderr install_dev_profile_without_jq
    [ "$status" -ne 0 ]
    [[ "${stderr}" == *"ERROR: jq not found"* ]]
    run ! grep -q "nix profile install" "${NIX_LOG}"
}

@test "an empty profile installs without jq: there is nothing to vet" {
    setup_profile_stubs
    load_profile_function install_dev_profile
    run install_dev_profile_without_jq
    [ "$status" -eq 0 ]
    grep -qF "nix profile install ${HOME}/.config/nix-dev-env#dev-env" "${NIX_LOG}"
}

@test "a failing nix profile install fails the bootstrap step" {
    setup_profile_stubs
    cat >"${STUB_DIR}/nix" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "profile" && "\${2:-}" == "list" ]]; then cat "${PROFILE_JSON}"; exit 0; fi
exit 1
STUB
    load_profile_function install_dev_profile
    run install_dev_profile
    [ "$status" -ne 0 ]
}

@test "post-install instructions no longer make entering dev a required step" {
    run ! grep -q 'Enter dev environment' "${PROJECT_ROOT}/bootstrap-dev-server.sh" "${PROJECT_ROOT}/hcloud-provision.sh"
}

@test "bootstrap wires the profile steps into Phase 4 in order" {
    run bash -c "sed -n '/^main()/,\$p' '${PROJECT_ROOT}/bootstrap-dev-server.sh' | grep -E '^ +(install_dev_profile|configure_profile_path|setup_dev_env)( |\$)' | awk '{print \$1}' | tr '\n' ' '"
    [ "$output" = "install_dev_profile configure_profile_path setup_dev_env " ]
}

@test "configure_profile_path prepends the profile bin to /etc/environment PATH once" {
    setup_profile_stubs
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    echo 'PATH="/usr/local/bin:/usr/bin:/bin"' >"${ENVIRONMENT_FILE}"
    load_profile_function configure_profile_path
    run configure_profile_path
    [ "$status" -eq 0 ]
    grep -qF "PATH=\"${HOME}/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin\"" "${ENVIRONMENT_FILE}"
    run configure_profile_path
    [ "$status" -eq 0 ]
    [ "$(grep -cF "${HOME}/.nix-profile/bin" "${ENVIRONMENT_FILE}")" -eq 1 ]
    [ "$(grep -cF '>>> nix-profile-path >>>' "${HOME}/.profile")" -eq 1 ]
}

@test "configure_profile_path creates a PATH entry when /etc/environment has none" {
    setup_profile_stubs
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    : >"${ENVIRONMENT_FILE}"
    load_profile_function configure_profile_path
    run configure_profile_path
    [ "$status" -eq 0 ]
    grep -qE "^PATH=\"${HOME}/.nix-profile/bin:" "${ENVIRONMENT_FILE}"
}

# -----------------------------------------------------------------------------
# setup-dev-env.sh: the shellHook side effects, now run by the bootstrap
# -----------------------------------------------------------------------------

run_setup_dev_env() {
    export HOME="${MOCK_HOME}"
    export REPO_CLAUDE_DIR="${TEST_TEMP_DIR}/repo-claude"
    mkdir -p "${REPO_CLAUDE_DIR}/agents" "${REPO_CLAUDE_DIR}/commands"
    echo "# claude" >"${REPO_CLAUDE_DIR}/CLAUDE.md"
    echo '{}' >"${REPO_CLAUDE_DIR}/settings.json"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
}

@test "setup-dev-env.sh symlinks the Claude config and is idempotent" {
    run_setup_dev_env
    [ "$status" -eq 0 ]
    [ "$(readlink "${HOME}/.claude/agents")" = "${REPO_CLAUDE_DIR}/agents" ]
    [ "$(readlink "${HOME}/.claude/CLAUDE.md")" = "${REPO_CLAUDE_DIR}/CLAUDE.md" ]
    [ "$(readlink "${HOME}/.claude/settings.json")" = "${REPO_CLAUDE_DIR}/settings.json" ]
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Linked"* ]]
}

@test "setup-dev-env.sh backs up a real file before linking over it" {
    mkdir -p "${MOCK_HOME}/.claude"
    echo "mine" >"${MOCK_HOME}/.claude/CLAUDE.md"
    run_setup_dev_env
    [ "$status" -eq 0 ]
    [ "$(cat "${HOME}/.claude/CLAUDE.md.backup")" = "mine" ]
}

@test "setup-dev-env.sh writes the zshrc and msmtprc templates without clobbering" {
    run_setup_dev_env
    [ "$status" -eq 0 ]
    grep -q "nix-dev-env" "${HOME}/.zshrc"
    [ "$(stat -c %a "${HOME}/.msmtprc")" = "600" ]
    echo "# edited" >>"${HOME}/.msmtprc"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    grep -q "# edited" "${HOME}/.msmtprc"
}

@test "setup-dev-env.sh prunes stale MCP servers and keeps the rest" {
    command -v jq &>/dev/null || skip "jq not available"
    echo '{"mcpServers":{"context7":{},"sequential-thinking":{},"keep":{}}}' >"${MOCK_HOME}/.claude.json"
    run_setup_dev_env
    [ "$status" -eq 0 ]
    run jq -c '.mcpServers | keys' "${MOCK_HOME}/.claude.json"
    [ "$output" = '["keep"]' ]
}

@test "setup-dev-env.sh passes shellcheck" {
    command -v shellcheck &>/dev/null || skip "shellcheck not available"
    run shellcheck -x -P SCRIPTDIR -S warning "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
}

@test "setup-dev-env.sh leaves ~/.claude.json untouched when no MCP entry is stale" {
    command -v jq &>/dev/null || skip "jq not available"
    echo '{"mcpServers":{"keep":{}}}' >"${MOCK_HOME}/.claude.json"
    before="$(cat "${MOCK_HOME}/.claude.json")"
    run_setup_dev_env
    [ "$status" -eq 0 ]
    [[ "${output}" != *"Pruned"* ]]
    [ "$(cat "${MOCK_HOME}/.claude.json")" = "${before}" ]
}

@test "setup-dev-env.sh skips Claude linking when the repo config dir is absent" {
    export HOME="${MOCK_HOME}"
    export REPO_CLAUDE_DIR="${TEST_TEMP_DIR}/does-not-exist"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    [ ! -e "${HOME}/.claude/agents" ]
}

@test "setup-dev-env.sh repairs a wrong symlink and keeps zshrc idempotent" {
    mkdir -p "${MOCK_HOME}/.claude"
    ln -s /nonexistent "${MOCK_HOME}/.claude/agents"
    run_setup_dev_env
    [ "$status" -eq 0 ]
    [ "$(readlink "${HOME}/.claude/agents")" = "${REPO_CLAUDE_DIR}/agents" ]
    count_before="$(grep -c "nix-dev-env" "${HOME}/.zshrc")"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    [ "$(grep -c "nix-dev-env" "${HOME}/.zshrc")" = "${count_before}" ]
}
