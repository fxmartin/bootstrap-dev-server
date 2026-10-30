#!/usr/bin/env bats
# ABOUTME: Tests for lib/rc-block.sh and the rc files generated through it
# ABOUTME: A provisioned server must receive a changed dev-update, not keep its first-ever copy

load 'test_helper'

bats_require_minimum_version 1.5.0

setup() {
    common_setup
    export HOME="${MOCK_HOME}"
    export NO_COLOR=1
    RC="${MOCK_HOME}/.testrc"
    BEGIN="# >>> test block >>>"
    END="# <<< test block <<<"
    log_info() { :; }
    log_ok() { echo "OK: $1"; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    # shellcheck source=../lib/rc-block.sh
    source "${PROJECT_ROOT}/lib/rc-block.sh"
}

teardown() {
    common_teardown
}

write_block() {
    printf '%s\n%s\n%s\n' "${BEGIN}" "$1" "${END}" | write_rc_block "${RC}" "${BEGIN}" "${END}"
}

# =============================================================================
# write_rc_block
# =============================================================================

@test "write_rc_block creates the file when it does not exist" {
    run write_block "body"
    [ "$status" -eq 0 ]
    [ "$(cat "${RC}")" = "$(printf '%s\nbody\n%s' "${BEGIN}" "${END}")" ]
}

@test "write_rc_block appends to a file without the block and keeps its content" {
    echo "# mine" >"${RC}"
    run write_block "body"
    [ "$status" -eq 0 ]
    [ "$(cat "${RC}")" = "$(printf '# mine\n\n%s\nbody\n%s' "${BEGIN}" "${END}")" ]
}

@test "write_rc_block replaces a drifted block in place and keeps everything outside the markers" {
    printf '# above\n%s\nold body\nold line two\n%s\n# below\n' "${BEGIN}" "${END}" >"${RC}"
    run write_block "new body"
    [ "$status" -eq 0 ]
    [ "$(cat "${RC}")" = "$(printf '# above\n%s\nnew body\n%s\n# below' "${BEGIN}" "${END}")" ]
}

@test "write_rc_block saves the previous file as .backup when it rewrites" {
    printf '%s\nold body\n%s\n' "${BEGIN}" "${END}" >"${RC}"
    run write_block "new body"
    [ "$status" -eq 0 ]
    grep -qx "old body" "${RC}.backup"
}

@test "write_rc_block leaves a current block alone and returns 1, like install_systemd_unit" {
    printf '# above\n%s\nbody\n%s\n' "${BEGIN}" "${END}" >"${RC}"
    touch -d '2020-01-01' "${RC}"
    before="$(stat -c '%i %Y' "${RC}")"
    run write_block "body"
    [ "$status" -eq 1 ]
    [ "$(stat -c '%i %Y' "${RC}")" = "${before}" ]
    [ ! -e "${RC}.backup" ]
}

@test "write_rc_block refuses a block with no closing marker rather than eat the rest of the file" {
    printf '%s\nbody\n# everything after this is mine\n' "${BEGIN}" >"${RC}"
    before="$(cat "${RC}")"
    run write_block "new body"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN"*"closing marker"* ]]
    [ "$(cat "${RC}")" = "${before}" ]
}

@test "write_rc_block only treats a whole line as a marker" {
    echo "# see the '${BEGIN}' section" >"${RC}"
    run write_block "body"
    [ "$status" -eq 0 ]
    grep -qx "${BEGIN}" "${RC}"
    grep -q "see the" "${RC}"
}

@test "write_rc_block writes through a symlinked rc file" {
    printf '%s\nold body\n%s\n' "${BEGIN}" "${END}" >"${RC}.real"
    ln -s "${RC}.real" "${RC}"
    run write_block "new body"
    [ "$status" -eq 0 ]
    [ -L "${RC}" ]
    grep -qx "new body" "${RC}.real"
}

@test "write_rc_block keeps the file's mode" {
    printf '%s\nold body\n%s\n' "${BEGIN}" "${END}" >"${RC}"
    chmod 600 "${RC}"
    run write_block "new body"
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "${RC}")" = "600" ]
    [ "$(stat -c %a "${RC}.backup")" = "600" ]
}

@test "lib/rc-block.sh passes shellcheck" {
    command -v shellcheck &>/dev/null || skip "shellcheck not available"
    run shellcheck -S warning "${PROJECT_ROOT}/lib/rc-block.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Provisioned servers: the generated rc blocks converge on the next bootstrap
# =============================================================================

# The dev-update a server provisioned before story 01.1-002 carries: it bumps
# the lock on the box, commits it and pushes.
old_dev_update() {
    cat <<'OLD'
dev-update() {
  (cd "$FLAKE_DIR" && nix flake update)
  (cd "$REPO_DIR" && git add flake.lock && git commit -m "chore: update flake.lock" && git push)
}
OLD
}

provisioned_rc() {
    local rc="$1" begin="$2" end="$3"
    {
        echo "# mine above"
        echo "${begin}"
        old_dev_update
        echo "${end}"
        echo "# mine below"
    } >"${rc}"
}

# setup_shell_integration's heredoc holds column-0 closing braces, so its range
# has to end at the next section banner rather than at the first `}`.
load_setup_shell_integration() {
    export REPO_CLONE_DIR="${PROJECT_ROOT}"
    export BOOTSTRAP_SUBDIR="."
    # shellcheck disable=SC1090
    source <(sed -n '/^setup_shell_integration() {/,/^# Install the Dev Toolset/p' \
        "${PROJECT_ROOT}/bootstrap-dev-server.sh")
}

@test "a provisioned ~/.zshrc loses the lock-bumping dev-update on the next setup" {
    provisioned_rc "${HOME}/.zshrc" "# >>> nix-dev-env zsh config >>>" "# <<< nix-dev-env zsh config <<<"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    run ! grep -q "nix flake update" "${HOME}/.zshrc"
    run ! grep -q "git add flake.lock" "${HOME}/.zshrc"
    grep -q "git reset --hard --quiet origin/main" "${HOME}/.zshrc"
    grep -qx "# mine above" "${HOME}/.zshrc"
    grep -qx "# mine below" "${HOME}/.zshrc"
    grep -q "nix flake update" "${HOME}/.zshrc.backup"
}

@test "the earliest zsh template's dev-update alias is replaced too" {
    {
        echo "# >>> nix-dev-env zsh config >>>"
        echo "alias dev-update='cd ~/.config/nix-dev-env && nix flake update && cd -'"
        echo "# <<< nix-dev-env zsh config <<<"
    } >"${HOME}/.zshrc"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    run ! grep -q "nix flake update" "${HOME}/.zshrc"
}

@test "a current ~/.zshrc is not rewritten on the next setup" {
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    touch -d '2020-01-01' "${HOME}/.zshrc"
    before="$(stat -c '%i %Y' "${HOME}/.zshrc")"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    [ "$(stat -c '%i %Y' "${HOME}/.zshrc")" = "${before}" ]
    [ ! -e "${HOME}/.zshrc.backup" ]
}

@test "a ~/.zshrc without the block keeps its content instead of being overwritten" {
    echo "# mine" >"${HOME}/.zshrc"
    run bash "${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    [ "$status" -eq 0 ]
    grep -qx "# mine" "${HOME}/.zshrc"
    grep -q "^dev-update() {" "${HOME}/.zshrc"
}

@test "a provisioned ~/.bashrc loses the lock-bumping dev-update on the next bootstrap" {
    provisioned_rc "${HOME}/.bashrc" "# >>> nix-dev-env >>>" "# <<< nix-dev-env <<<"
    load_setup_shell_integration
    run setup_shell_integration
    [ "$status" -eq 0 ]
    run ! grep -q "nix flake update" "${HOME}/.bashrc"
    run ! grep -q "git add flake.lock" "${HOME}/.bashrc"
    grep -q "git reset --hard --quiet origin/main" "${HOME}/.bashrc"
    grep -qx "# mine above" "${HOME}/.bashrc"
    grep -qx "# mine below" "${HOME}/.bashrc"
}

@test "setup_shell_integration writes a fresh ~/.bashrc block once and then leaves it alone" {
    echo "# ubuntu default" >"${HOME}/.bashrc"
    load_setup_shell_integration
    run setup_shell_integration
    [ "$status" -eq 0 ]
    [ "$(grep -c '^# >>> nix-dev-env >>>$' "${HOME}/.bashrc")" = "1" ]
    grep -qx "# ubuntu default" "${HOME}/.bashrc"

    touch -d '2020-01-01' "${HOME}/.bashrc"
    before="$(stat -c '%i %Y' "${HOME}/.bashrc")"
    run setup_shell_integration
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
    [ "$(stat -c '%i %Y' "${HOME}/.bashrc")" = "${before}" ]
}

@test "the generated ~/.bashrc block parses and defines dev-update" {
    load_setup_shell_integration
    run setup_shell_integration
    [ "$status" -eq 0 ]
    run bash -n "${HOME}/.bashrc"
    [ "$status" -eq 0 ]
    run bash -c "source '${HOME}/.bashrc' && declare -F dev-update"
    [ "$status" -eq 0 ]
}

@test "setup_shell_integration fails loudly when the rc-block library is missing" {
    load_setup_shell_integration
    export REPO_CLONE_DIR="${TEST_TEMP_DIR}/no-such-checkout"
    run setup_shell_integration
    [ "$status" -ne 0 ]
    [[ "$output" == *"lib/rc-block.sh"* ]]
}
