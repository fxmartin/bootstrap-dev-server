#!/usr/bin/env bats
# ABOUTME: Tests for the ssh-login herdr attach guard and the removal of the tmux auto-launch
# ABOUTME: Runs offline and root-safe against a stubbed herdr; nothing real is attached or started

load 'test_helper'

bats_require_minimum_version 1.5.0

setup() {
    common_setup
    export NO_COLOR=1
    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export SETUP_SCRIPT="${PROJECT_ROOT}/scripts/setup-dev-env.sh"
    export HOME="${MOCK_HOME}"
    export ZSHRC="${MOCK_HOME}/.zshrc"
    export REPO_CLAUDE_DIR="${TEST_TEMP_DIR}/absent-claude"
    export CLAUDE_JSON="${TEST_TEMP_DIR}/claude.json"

    # herdr is the seam: the stub records that it ran and returns immediately,
    # like a client the user has just quit.
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export HERDR_CALLS="${TEST_TEMP_DIR}/herdr.calls"
    mkdir -p "${STUB_DIR}"
    : >"${HERDR_CALLS}"
    cat >"${STUB_DIR}/herdr" <<EOF2
#!/usr/bin/env bash
echo "herdr \$*" >>"${HERDR_CALLS}"
exit "\${HERDR_STUB_EXIT:-0}"
EOF2
    chmod +x "${STUB_DIR}/herdr"
    export PATH="${STUB_DIR}:${PATH}"

    # The suite may itself run from an ssh session or a herdr pane.
    unset SSH_TTY SSH_ORIGINAL_COMMAND NO_HERDR HERDR_ENV HERDR_STUB_EXIT

    # Generate the real zshrc block, then lift the guard out of it.
    run bash "${SETUP_SCRIPT}"
    [ "$status" -eq 0 ]
    sed -n '/^herdr_login_attach() {$/,/^}$/p' "${ZSHRC}" >"${TEST_TEMP_DIR}/guard.sh"
    [ -s "${TEST_TEMP_DIR}/guard.sh" ]
}

teardown() {
    common_teardown
}

# Runs the guard in a fresh shell the way a login does; stdout/stderr land in $output.
run_guard() {
    run bash -c "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach; echo \"after-guard rc=\$?\" >&2"
}

herdr_call_count() {
    wc -l <"${HERDR_CALLS}" | tr -d ' '
}

# =============================================================================
# Attach guard
# =============================================================================

@test "zshrc block calls the guard so a login runs it" {
    grep -qx 'herdr_login_attach' "${ZSHRC}"
}

@test "interactive ssh login attaches the herdr client" {
    export SSH_TTY=/dev/pts/7
    run_guard
    [ "$status" -eq 0 ]
    [ "$(herdr_call_count)" = "1" ]
    [ "$(cat "${HERDR_CALLS}")" = "herdr " ]
}

@test "leaving herdr returns to the login shell, even when the client fails" {
    export SSH_TTY=/dev/pts/7 HERDR_STUB_EXIT=1
    run_guard
    [ "$status" -eq 0 ]
    [[ "${output}" == *"after-guard rc=0"* ]]
}

@test "non-interactive ssh command (no tty) neither attaches nor prints" {
    run --separate-stderr bash -c "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [ -z "${stderr}" ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "ssh command forced with a tty (ssh -t dev cmd) does not attach" {
    export SSH_TTY=/dev/pts/7 SSH_ORIGINAL_COMMAND="acm peers"
    run --separate-stderr bash -c "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [ -z "${stderr}" ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "NO_HERDR=1 skips the attach" {
    export SSH_TTY=/dev/pts/7 NO_HERDR=1
    run --separate-stderr bash -c "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "NO_HERDR=0 does not count as the escape hatch" {
    export SSH_TTY=/dev/pts/7 NO_HERDR=0
    run_guard
    [ "$(herdr_call_count)" = "1" ]
}

@test "already inside herdr does not nest another client" {
    export SSH_TTY=/dev/pts/7 HERDR_ENV=1
    run_guard
    [ "$status" -eq 0 ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "a missing herdr binary is skipped silently" {
    export SSH_TTY=/dev/pts/7
    mkdir "${TEST_TEMP_DIR}/empty"
    run --separate-stderr env PATH="${TEST_TEMP_DIR}/empty" "${BASH}" -c "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [ -z "${stderr}" ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "the guard is valid zsh too, when zsh is available" {
    command -v zsh &>/dev/null || skip "zsh not available"
    export SSH_TTY=/dev/pts/7
    run zsh -fc "source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
    [ "$status" -eq 0 ]
    [ "$(herdr_call_count)" = "1" ]
}

# =============================================================================
# tmux is gone
# =============================================================================

@test "the generated zshrc has no tmux auto-launch" {
    run ! grep -qi 'tmux' "${ZSHRC}"
}

@test "the bootstrap no longer configures tmux" {
    run ! grep -q 'configure_tmux' "${BOOTSTRAP}"
    run ! grep -q '# >>> nix-dev-env tmux >>>' <(sed -n '/^remove_tmux_config()/,/^}$/!p' "${BOOTSTRAP}")
}

@test "a zshrc written with the old tmux launch loses it on the next run, user lines kept" {
    cat >"${ZSHRC}" <<'RC'
# mine, above
# >>> nix-dev-env zsh config >>>
alias old='true'
if [[ ( -n "$SSH_CONNECTION" || -n "$MOSH_CONNECTION" ) && -z "$TMUX" ]]; then
  tmux attach-session -t main 2>/dev/null || tmux new-session -s main
fi
# <<< nix-dev-env zsh config <<<
# mine, below
RC
    run bash "${SETUP_SCRIPT}"
    [ "$status" -eq 0 ]
    run ! grep -qi 'tmux' "${ZSHRC}"
    grep -qx '# mine, above' "${ZSHRC}"
    grep -qx '# mine, below' "${ZSHRC}"
    grep -qx 'herdr_login_attach' "${ZSHRC}"
}

@test "remove_tmux_config strips the marked block from ~/.tmux.conf and keeps the rest" {
    log_info() { :; }
    log_ok() { :; }
    # shellcheck disable=SC1090
    source <(sed -n '/^remove_tmux_config()/,/^}$/p' "${BOOTSTRAP}")
    cat >"${HOME}/.tmux.conf" <<'CONF'
set -g status-position top

# >>> nix-dev-env tmux >>>
set -g mouse on
# <<< nix-dev-env tmux <<<
bind x kill-pane
CONF
    run remove_tmux_config
    [ "$status" -eq 0 ]
    run ! grep -q 'nix-dev-env tmux' "${HOME}/.tmux.conf"
    run ! grep -q 'mouse on' "${HOME}/.tmux.conf"
    grep -qx 'set -g status-position top' "${HOME}/.tmux.conf"
    grep -qx 'bind x kill-pane' "${HOME}/.tmux.conf"
    # Second run is a no-op
    cp "${HOME}/.tmux.conf" "${TEST_TEMP_DIR}/after-first"
    run remove_tmux_config
    [ "$status" -eq 0 ]
    cmp -s "${HOME}/.tmux.conf" "${TEST_TEMP_DIR}/after-first"
}

@test "remove_tmux_config ignores a missing ~/.tmux.conf and an unclosed block" {
    log_info() { :; }
    log_ok() { :; }
    log_warn() { :; }
    # shellcheck disable=SC1090
    source <(sed -n '/^remove_tmux_config()/,/^}$/p' "${BOOTSTRAP}")
    run remove_tmux_config
    [ "$status" -eq 0 ]
    printf '# >>> nix-dev-env tmux >>>\nset -g mouse on\nmy-line\n' >"${HOME}/.tmux.conf"
    run remove_tmux_config
    [ "$status" -eq 0 ]
    grep -qx 'my-line' "${HOME}/.tmux.conf"
}

# =============================================================================
# sshd lets the escape hatch through
# =============================================================================

@test "hardened sshd config accepts NO_HERDR" {
    grep -qx 'AcceptEnv NO_HERDR' <(sed -n '/^harden_ssh()/,/^SSHEOF$/p' "${BOOTSTRAP}")
}

@test "an existing hardening file without AcceptEnv NO_HERDR is rewritten" {
    run grep -n 'AcceptEnv NO_HERDR' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
    # one in the heredoc, one in the drift check
    [ "$(echo "${output}" | wc -l)" -ge 2 ]
}
