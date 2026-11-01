#!/usr/bin/env bats
# ABOUTME: Tests the acm fleet setup's peers: config.toml merge, peer SSH key and ssh config block
# ABOUTME: Executes scripts/setup-acm-fleet.sh offline against a sandboxed HOME and a stubbed systemctl

load 'test_helper'

BEGIN="# >>> bootstrap-dev-server acm peers >>>"
END="# <<< bootstrap-dev-server acm peers <<<"

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export SETUP="${PROJECT_ROOT}/scripts/setup-acm-fleet.sh"
    export HOME="${MOCK_HOME}"
    export CONFIG="${MOCK_HOME}/.config/acm/config.toml"
    export KEY="${MOCK_HOME}/.ssh/id_acm_peers"
    export SSH_CONFIG="${MOCK_HOME}/.ssh/config"
    unset XDG_CONFIG_HOME ACM_PHONE_KEYS_FILE

    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export STUB_LOG="${TEST_TEMP_DIR}/stub.log"
    mkdir -p "${STUB_DIR}"
    : >"${STUB_LOG}"
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >>"${STUB_LOG}"
case "\$*" in
    "--user is-active --quiet acmd.service") [[ -f "${TEST_TEMP_DIR}/acmd-active" ]] ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "${STUB_DIR}/systemctl"
    export PATH="${STUB_DIR}:${PATH}"

    export ACM_PEERS_FILE="${TEST_TEMP_DIR}/peers.toml"
    cat >"${ACM_PEERS_FILE}" <<'EOF'
# a comment that must not reach the generated block
[[peers]]
label = "omarchy-xps13"
ssh = "omarchy-xps13"
socket = "/run/user/1000/acm.sock"

[[peers]]
label = "home-lab"
ssh = "someone@home-lab"
socket = "/home/fx/.local/state/acm/acm.sock"
EOF
    # No phone lines in this suite: tests/acm-phone-keys.bats covers them.
    export ACM_PHONE_KEYS_FILE="${TEST_TEMP_DIR}/phones.pub"
    : >"${ACM_PHONE_KEYS_FILE}"
}

teardown() {
    common_teardown
}

@test "the repo's peers file lists the XPS, the M3 Max and home-lab" {
    local peers="${PROJECT_ROOT}/config/acm-peers.toml"
    grep -q 'label = "omarchy-xps13"' "${peers}"
    grep -q 'socket = "/run/user/1000/acm.sock"' "${peers}"
    grep -q 'label = "macbook-pro-m3-max"' "${peers}"
    grep -q 'label = "home-lab"' "${peers}"
}

@test "every peer in the shipped file has an absolute socket" {
    local peers="${PROJECT_ROOT}/config/acm-peers.toml"
    [ "$(grep -c '^label' "${peers}")" -eq "$(grep -c '^socket = "/' "${peers}")" ]
    run grep -E '^socket = "~' "${peers}"
    [ "${status}" -ne 0 ]
}

@test "a first run writes every peer into a marker block in config.toml" {
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qxF "${BEGIN}" "${CONFIG}"
    grep -qxF "${END}" "${CONFIG}"
    [ "$(grep -c '^\[\[peers\]\]$' "${CONFIG}")" -eq 2 ]
    grep -qxF 'label = "omarchy-xps13"' "${CONFIG}"
    grep -qxF 'socket = "/run/user/1000/acm.sock"' "${CONFIG}"
    grep -qxF 'ssh = "someone@home-lab"' "${CONFIG}"
    run grep -c 'must not reach' "${CONFIG}"
    [ "${output}" = "0" ]
}

@test "a peer without a socket is refused" {
    printf '[[peers]]\nlabel = "nosock"\nssh = "nosock"\n' >"${ACM_PEERS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    run grep -c 'nosock' "${CONFIG}"
    [ "${output}" = "0" ]
}

@test "a relative or ~/ socket is refused" {
    for sock in "acm.sock" "~/.local/state/acm/acm.sock"; do
        rm -f "${CONFIG}"
        printf '[[peers]]\nlabel = "relsock"\nssh = "relsock"\nsocket = "%s"\n' "${sock}" >"${ACM_PEERS_FILE}"
        run bash "${SETUP}"
        [ "${status}" -ne 0 ]
        run grep -c 'relsock' "${CONFIG}"
        [ "${output}" = "0" ]
    done
}

@test "the printed authorisation line restricts the peer key to port forwarding" {
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -qE '^restrict,port-forwarding,command="/usr/bin/false" ssh-ed25519 '
    assert_contains "${output}" "acm-peers@"
}

@test "peers and tables the user added outside the block are kept" {
    mkdir -p "$(dirname "${CONFIG}")"
    cat >"${CONFIG}" <<'EOF'
[voice]
enabled = true

[[peers]]
label = "my-own-box"
ssh = "my-own-box"
EOF
    bash "${SETUP}"
    grep -qxF '[voice]' "${CONFIG}"
    grep -qxF 'label = "my-own-box"' "${CONFIG}"
    [ "$(grep -c '^\[\[peers\]\]$' "${CONFIG}")" -eq 3 ]
}

@test "a label the user already defined stays theirs: the repo's entry is left out" {
    mkdir -p "$(dirname "${CONFIG}")"
    cat >"${CONFIG}" <<'EOF'
[[peers]]
label = "home-lab"
ssh = "my-alias"
EOF
    bash "${SETUP}"
    [ "$(grep -c 'label = "home-lab"' "${CONFIG}")" -eq 1 ]
    grep -qxF 'ssh = "my-alias"' "${CONFIG}"
    grep -qxF 'label = "omarchy-xps13"' "${CONFIG}"
}

# Every repo label already defined by hand, so the generated block has no entries.
define_repo_peers_by_hand() {
    mkdir -p "$(dirname "${CONFIG}")"
    cat >"${CONFIG}" <<'EOF'
[[peers]]
label = "omarchy-xps13"
ssh = "my-xps"

[[peers]]
label = "home-lab"
ssh = "my-lab"
EOF
}

@test "with every repo peer defined by hand the block still closes" {
    define_repo_peers_by_hand
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qxF "${BEGIN}" "${CONFIG}"
    grep -qxF "${END}" "${CONFIG}"
}

@test "a block with no entries does not stop a later peer from landing" {
    define_repo_peers_by_hand
    bash "${SETUP}"
    cat >>"${ACM_PEERS_FILE}" <<'EOF'

[[peers]]
label = "new-box"
ssh = "new-box"
EOF
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qxF 'label = "new-box"' "${CONFIG}"
}

@test "an empty peers file writes a closed block" {
    : >"${ACM_PEERS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qxF "${END}" "${CONFIG}"
}

@test "every peer refused still writes a closed block and fails the run" {
    cat >"${ACM_PEERS_FILE}" <<'EOF'
[[peers]]
label = "-bad"
ssh = "-oProxyCommand=evil"
EOF
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    grep -qxF "${END}" "${CONFIG}"
}

@test "a block with no end marker fails the run and is not reported as up to date" {
    bash "${SETUP}"
    sed -i "\\|^${END}\$|d" "${CONFIG}"
    local before
    before="$(cat "${CONFIG}")"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "closing marker"
    [[ "${output}" != *"up to date"* ]]
    [ "$(cat "${CONFIG}")" = "${before}" ]
}

@test "an ssh config block with no end marker fails the run" {
    bash "${SETUP}"
    sed -i '\|^# <<< bootstrap-dev-server acm peer hosts <<<$|d' "${SSH_CONFIG}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "closing marker"
}

@test "a re-run with unchanged peers leaves config.toml alone and acmd running" {
    touch "${TEST_TEMP_DIR}/acmd-active"
    bash "${SETUP}"
    local before
    before="$(cat "${CONFIG}")"
    : >"${STUB_LOG}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${CONFIG}")" = "${before}" ]
    run grep 'restart' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "a removed repo peer leaves the block on the next run" {
    bash "${SETUP}"
    cat >"${ACM_PEERS_FILE}" <<'EOF'
[[peers]]
label = "home-lab"
ssh = "home-lab"
EOF
    bash "${SETUP}"
    run grep -c 'omarchy-xps13' "${CONFIG}"
    [ "${output}" = "0" ]
}

@test "a changed block restarts a running acmd, which reads its peers at start" {
    touch "${TEST_TEMP_DIR}/acmd-active"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -q 'systemctl --user restart acmd.service' "${STUB_LOG}"
}

@test "a stopped acmd is not started: setup_acmd_service owns that" {
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    run grep 'restart' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "an invalid peer is skipped and fails the run, the valid ones still land" {
    cat >>"${ACM_PEERS_FILE}" <<'EOF'

[[peers]]
label = "no-ssh"

[[peers]]
label = "injected"
ssh = "-oProxyCommand=evil"
EOF
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "no-ssh"
    run grep -c 'label = "no-ssh"\|injected\|evil' "${CONFIG}"
    [ "${output}" = "0" ]
    run grep -c 'evil' "${SSH_CONFIG}"
    [ "${output}" = "0" ]
    grep -qxF 'label = "omarchy-xps13"' "${CONFIG}"
}

@test "a missing peers file fails without touching config.toml" {
    export ACM_PEERS_FILE="${TEST_TEMP_DIR}/nope.toml"
    mkdir -p "$(dirname "${CONFIG}")"
    echo '[voice]' >"${CONFIG}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    [ "$(cat "${CONFIG}")" = "[voice]" ]
}

@test "the peer key is generated once, ed25519, passphrase-free, private, and its public half printed" {
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%a' "${KEY}")" = "600" ]
    [ "$(stat -c '%a' "${MOCK_HOME}/.ssh")" = "700" ]
    ssh-keygen -y -P "" -f "${KEY}" >/dev/null
    grep -q '^ssh-ed25519 ' "${KEY}.pub"
    assert_contains "${output}" "$(cut -d' ' -f1,2 "${KEY}.pub")"

    local before
    before="$(cat "${KEY}.pub")"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${KEY}.pub")" = "${before}" ]
    assert_contains "${output}" "$(cut -d' ' -f1,2 "${KEY}.pub")"
}

@test "an existing peer key is kept, and a lost public half is rebuilt from it" {
    mkdir -p "${MOCK_HOME}/.ssh"
    ssh-keygen -q -t ed25519 -N "" -C mine -f "${KEY}"
    local pub
    pub="$(cut -d' ' -f1,2 "${KEY}.pub")"
    rm -f "${KEY}.pub"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(cut -d' ' -f1,2 "${KEY}.pub")" = "${pub}" ]
}

@test "ssh to a peer uses the peer key: acmd's forward runs bare ssh with BatchMode" {
    bash "${SETUP}"
    grep -qxF 'Host omarchy-xps13 home-lab' "${SSH_CONFIG}"
    grep -qF "IdentityFile ~/.ssh/id_acm_peers" "${SSH_CONFIG}"
    grep -qF "IdentitiesOnly yes" "${SSH_CONFIG}"
    grep -qF "StrictHostKeyChecking accept-new" "${SSH_CONFIG}"
    [ "$(stat -c '%a' "${SSH_CONFIG}")" = "600" ]
}

@test "the user's own ssh config survives and a re-run leaves one block" {
    mkdir -p "${MOCK_HOME}/.ssh"
    printf 'Host mine\n    User me\n' >"${SSH_CONFIG}"
    bash "${SETUP}"
    bash "${SETUP}"
    grep -qxF 'Host mine' "${SSH_CONFIG}"
    [ "$(grep -c '^Host omarchy-xps13' "${SSH_CONFIG}")" -eq 1 ]
}

@test "XDG_CONFIG_HOME moves config.toml the way acm resolves it" {
    export XDG_CONFIG_HOME="${TEST_TEMP_DIR}/xdg"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    assert_file_exists "${XDG_CONFIG_HOME}/acm/config.toml"
}

@test "main runs the fleet setup after the acmd service, and a failure does not stop the bootstrap" {
    local bootstrap="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    local body
    body="$(sed -n '/^main() {/,/^}$/p' "${bootstrap}")"
    [ "$(grep -n 'setup_acmd_service' <<<"${body}" | cut -d: -f1)" -lt "$(grep -n '^ *setup_acm_fleet' <<<"${body}" | cut -d: -f1)" ]

    # shellcheck disable=SC1090
    source <(sed -n '/^setup_acm_fleet() {/,/^}$/p' "${bootstrap}")
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1"; }
    export REPO_CLONE_DIR="${TEST_TEMP_DIR}/clone" BOOTSTRAP_SUBDIR="."
    mkdir -p "${REPO_CLONE_DIR}/scripts"
    printf 'exit 1\n' >"${REPO_CLONE_DIR}/scripts/setup-acm-fleet.sh"
    run setup_acm_fleet
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "re-run"
}

@test "the lock pin carries acm's GC-safe key-line (past 9058ae0)" {
    run jq -r '.nodes["agentic-coding-monitor"].locked.rev' "${PROJECT_ROOT}/flake.lock"
    [[ "${output}" != 9058ae0* ]]
}
