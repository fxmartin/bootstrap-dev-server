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

    # The suite may itself run from an ssh session, a herdr pane or tmux.
    unset SSH_TTY SSH_ORIGINAL_COMMAND NO_HERDR HERDR_ENV HERDR_STUB_EXIT TMUX

    # Generate the real zshrc block, then lift the guard out of it.
    run bash "${SETUP_SCRIPT}"
    [ "$status" -eq 0 ]
    sed -n '/^herdr_login_attach() {$/,/^}$/p' "${ZSHRC}" >"${TEST_TEMP_DIR}/guard.sh"
    [ -s "${TEST_TEMP_DIR}/guard.sh" ]
    export GUARD="source '${TEST_TEMP_DIR}/guard.sh'; herdr_login_attach"
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

# A provisioned server logs in with bash: hcloud-provision's adduser gives /bin/bash and
# nothing runs chsh. So ~/.bashrc, not ~/.zshrc, is what a real `ssh dev` reads.
generate_bashrc() {
    log_info() { :; }
    log_ok() { :; }
    log_warn() { :; }
    export REPO_CLONE_DIR="${PROJECT_ROOT}" BOOTSTRAP_SUBDIR="."
    # shellcheck disable=SC1090
    source <(sed -n '/^setup_shell_integration() {/,/^# Install the Dev Toolset/p' "${BOOTSTRAP}")
    setup_shell_integration
}

# Ubuntu's stock ~/.profile stanza is how a login bash reaches ~/.bashrc. The stub goes
# back on PATH first because /etc/profile may reset it, as Alpine's does.
write_stock_profile() {
    cat >"${HOME}/.profile" <<EOF2
export PATH="${STUB_DIR}:\${PATH}"
if [ -n "\${BASH_VERSION}" ]; then
    if [ -f "\${HOME}/.bashrc" ]; then
        . "\${HOME}/.bashrc"
    fi
fi
EOF2
}

guard_text() {
    sed -n '/^herdr_login_attach() {$/,/^}$/p' "$1" | sed 's/^ *//'
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

@test "a forced command (authorized_keys command=) with a tty does not attach" {
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

@test "a tmux pane does not attach, so herdr never nests inside the fallback" {
    export SSH_TTY=/dev/pts/7 TMUX=/tmp/tmux-1000/default,1234,0
    run_guard
    [ "$status" -eq 0 ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "shells opened after leaving herdr stay plain: zsh, exec zsh, the dev shellHook" {
    export SSH_TTY=/dev/pts/7
    run bash -c "${GUARD}; bash -c \"${GUARD}\"; exec bash -c \"${GUARD}\""
    [ "$status" -eq 0 ]
    [ "$(herdr_call_count)" = "1" ]
}

@test "a client that failed still leaves later shells plain" {
    export SSH_TTY=/dev/pts/7 HERDR_STUB_EXIT=1
    run bash -c "${GUARD}; bash -c \"${GUARD}\""
    [ "$(herdr_call_count)" = "1" ]
}

@test "the login is marked before the client runs, so a killed client cannot leave it unmarked" {
    export SSH_TTY=/dev/pts/7
    cat >"${STUB_DIR}/herdr" <<EOF2
#!/usr/bin/env bash
echo "\${NO_HERDR:-unset}" >"${TEST_TEMP_DIR}/client.no_herdr"
EOF2
    run_guard
    [ "$(cat "${TEST_TEMP_DIR}/client.no_herdr")" = "1" ]
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

@test "a bash login attaches: bash is the login shell on a provisioned server" {
    generate_bashrc
    write_stock_profile
    export SSH_TTY=/dev/pts/7
    run setsid bash --login -i -c 'echo login-reached-prompt'
    [ "$status" -eq 0 ]
    [[ "${output}" == *"login-reached-prompt"* ]]
    [ "$(herdr_call_count)" = "1" ]
}

@test "ssh -t dev cmd: sshd's bash reads ~/.bashrc non-interactively and must not attach" {
    generate_bashrc
    export SSH_TTY=/dev/pts/7
    run --separate-stderr bash -c "source '${HOME}/.bashrc'; echo cmd-output"
    [ "$status" -eq 0 ]
    [ "${output}" = "cmd-output" ]
    [ -z "${stderr}" ]
    [ "$(herdr_call_count)" = "0" ]
}

@test "~/.bashrc and ~/.zshrc carry the same guard" {
    generate_bashrc
    [ -n "$(guard_text "${HOME}/.bashrc")" ]
    [ "$(guard_text "${HOME}/.bashrc")" = "$(guard_text "${ZSHRC}")" ]
}

@test "a ~/.bashrc block from before the guard gains it on the next run, user lines kept" {
    cat >"${HOME}/.bashrc" <<'RC'
# mine, above
# >>> nix-dev-env >>>
alias old='true'
# <<< nix-dev-env <<<
# mine, below
RC
    generate_bashrc
    grep -q '^herdr_login_attach() {$' "${HOME}/.bashrc"
    run ! grep -q "alias old" "${HOME}/.bashrc"
    grep -qx '# mine, above' "${HOME}/.bashrc"
    grep -qx '# mine, below' "${HOME}/.bashrc"
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

# The guard checks TMUX, so the word stays in the rc files; what must go is the launch.
@test "the generated rc files have no tmux auto-launch" {
    generate_bashrc
    run ! grep -Eq 'tmux (attach|new)' "${ZSHRC}"
    run ! grep -Eq 'tmux (attach|new)' "${HOME}/.bashrc"
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
    run ! grep -Eq 'tmux (attach|new)' "${ZSHRC}"
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

# harden_ssh hard-codes the /etc path, so it is pointed into the sandbox. sudo only has
# to run tee and pass `sshd -t`.
load_harden_ssh() {
    export HARDENING="${TEST_TEMP_DIR}/99-hardening.conf"
    log_info() { :; }
    log_ok() { :; }
    log_error() { :; }
    sudo() {
        [[ "$1" == "sshd" ]] || "$@"
    }
    SSH_PORT=22
    SSH_RESTART_NEEDED=false
    # shellcheck disable=SC1090
    source <(sed -n '/^harden_ssh() {/,/^}$/p' "${BOOTSTRAP}" |
        sed "s|/etc/ssh/sshd_config.d/99-hardening.conf|${HARDENING}|")
}

@test "a hardening file without AcceptEnv NO_HERDR is rewritten once and flags the reload" {
    load_harden_ssh
    printf 'Port 22\nPermitRootLogin no\n' >"${HARDENING}"
    harden_ssh
    grep -qx 'AcceptEnv NO_HERDR' "${HARDENING}"
    [ "${SSH_RESTART_NEEDED}" = "true" ]

    # The next bootstrap is a new process: nothing forced, nothing to do
    unset FORCE_SSH_UPDATE
    SSH_RESTART_NEEDED=false
    touch -d '2020-01-01' "${HARDENING}"
    before="$(stat -c '%Y' "${HARDENING}")"
    harden_ssh
    [ "${SSH_RESTART_NEEDED}" = "false" ]
    [ "$(stat -c '%Y' "${HARDENING}")" = "${before}" ]
}

@test "hardening keeps a global AllowTcpForwarding no and ends with the dev user's local-forward block" {
    load_harden_ssh
    DEV_USER=fx
    harden_ssh
    grep -qx 'AllowTcpForwarding no' "${HARDENING}"
    run tail -n 3 "${HARDENING}"
    [ "${lines[0]}" = "Match User fx" ]
    [ "${lines[1]}" = "    AllowTcpForwarding local" ]
    [ "${lines[2]}" = "Match all" ]
    ! grep -Eq 'AllowTcpForwarding (yes|remote|all)' "${HARDENING}"
    grep -qx 'X11Forwarding no' "${HARDENING}"
}

@test "a hardening file without the local-forward block is rewritten once, then left alone" {
    load_harden_ssh
    DEV_USER=fx
    printf 'Port 22\nAllowTcpForwarding no\nAcceptEnv NO_HERDR\n' >"${HARDENING}"
    harden_ssh
    [ "${SSH_RESTART_NEEDED}" = "true" ]
    grep -qx '    AllowTcpForwarding local' "${HARDENING}"

    unset FORCE_SSH_UPDATE
    SSH_RESTART_NEEDED=false
    touch -d '2020-01-01' "${HARDENING}"
    before="$(stat -c '%Y' "${HARDENING}")"
    harden_ssh
    [ "${SSH_RESTART_NEEDED}" = "false" ]
    [ "$(stat -c '%Y' "${HARDENING}")" = "${before}" ]
}
