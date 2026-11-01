#!/usr/bin/env bats
# ABOUTME: Tests the verify-server.sh checks for the acm fleet role: peers, phone keys, ntfy
# ABOUTME: Runs offline against a sandboxed HOME and stubbed ss/tailscale/sudo/systemctl/curl

load 'test_helper'

BLOB="AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFakePhoneKey0123456789+/abcdefghij=="
BEGIN="# >>> bootstrap-dev-server acm phones >>>"
END="# <<< bootstrap-dev-server acm phones <<<"
TS_IP="100.93.110.61"

setup() {
    common_setup
    setup_mock_environment
    export HOME="${MOCK_HOME}"
    unset XDG_CONFIG_HOME
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    mkdir -p "${STUB_DIR}" "${MOCK_HOME}/.ssh" "${MOCK_HOME}/.config/acm"
    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; }
    warn() { echo "WARN: $1"; }
    info() { echo "INFO: $1"; }
    local fn
    for fn in check_acm_peers check_acm_phone_keys check_ntfy; do
        # shellcheck disable=SC1090
        source <(sed -n "/^${fn}() {/,/^}\$/p" "${PROJECT_ROOT}/tests/verify-server.sh")
    done
    export PATH="${STUB_DIR}:${PATH}"
    export ACM_BIN="${TEST_TEMP_DIR}/bin/acm"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    printf '#!/usr/bin/env bash\n' >"${ACM_BIN}"
    chmod +x "${ACM_BIN}"
}

teardown() {
    common_teardown
}

phone_line() {
    echo "command=\"${ACM_BIN} bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel-10-pro"
}

write_block() {
    {
        echo "ssh-ed25519 AAAAlaptop fx@laptop"
        echo "${BEGIN}"
        printf '%s\n' "$@"
        echo "${END}"
    } >"${MOCK_HOME}/.ssh/authorized_keys"
}

stub_ntfy_host() {
    local listen="$1" state="${2:-active}" ufw="${3:-2586/tcp on tailscale0 ALLOW IN Anywhere}" code="${4:-403}"
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "is-active" ]] && { echo "${state}"; [[ "${state}" == active ]]; exit; }
exit 0
EOF
    printf '#!/usr/bin/env bash\necho %s\n' "${TS_IP}" >"${STUB_DIR}/tailscale"
    cat >"${STUB_DIR}/ss" <<EOF
#!/usr/bin/env bash
for addr in ${listen}; do echo "LISTEN 0 4096 \${addr} 0.0.0.0:*"; done
echo "LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*"
EOF
    cat >"${STUB_DIR}/sudo" <<EOF
#!/usr/bin/env bash
echo "${ufw}"
EOF
    printf '#!/usr/bin/env bash\necho %s\n' "${code}" >"${STUB_DIR}/curl"
    chmod +x "${STUB_DIR}"/*
    NTFY_UNIT_FILE="${TEST_TEMP_DIR}/ntfy.service"
    export NTFY_UNIT_FILE
    touch "${NTFY_UNIT_FILE}"
}

@test "peers file with peers and a peer key passes" {
    printf '[[peers]]\nlabel = "x"\nssh = "x"\n' >"${MOCK_HOME}/.config/acm/config.toml"
    touch "${MOCK_HOME}/.ssh/id_acm_peers" "${MOCK_HOME}/.ssh/id_acm_peers.pub"
    run check_acm_peers
    assert_contains "${output}" "PASS:"
    assert_not_contains "${output}" "FAIL"
}

@test "a missing peers file fails with a re-run hint" {
    run check_acm_peers
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "re-run the bootstrap"
}

@test "a peers file without peers fails" {
    printf '[voice]\nenabled = true\n' >"${MOCK_HOME}/.config/acm/config.toml"
    run check_acm_peers
    assert_contains "${output}" "FAIL:"
}

@test "a missing peer key fails" {
    printf '[[peers]]\nlabel = "x"\nssh = "x"\n' >"${MOCK_HOME}/.config/acm/config.toml"
    run check_acm_peers
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "id_acm_peers"
}

@test "the check's line form is the installer's, so verify cannot pass what setup refuses" {
    local lib_re verify_re
    lib_re="$(sed -n "s/^ACM_PHONE_LINE_RE='\\(.*\\)'\$/\\1/p" "${PROJECT_ROOT}/lib/acm-phone-keys.sh")"
    verify_re="$(sed -n "s/^ *local safe='\\(.*\\)'\$/\\1/p" "${PROJECT_ROOT}/tests/verify-server.sh")"
    [ -n "${lib_re}" ]
    [ "${lib_re}" = "${verify_re}" ]
}

@test "a restricted phone line passes" {
    write_block "$(phone_line)"
    run check_acm_phone_keys
    assert_contains "${output}" "PASS: 1 phone key"
    assert_not_contains "${output}" "FAIL"
}

@test "no phones enrolled is information, not a failure" {
    echo "ssh-ed25519 AAAAlaptop fx@laptop" >"${MOCK_HOME}/.ssh/authorized_keys"
    run check_acm_phone_keys
    assert_contains "${output}" "INFO:"
    assert_not_contains "${output}" "FAIL"
}

@test "an unrestricted line inside the block fails" {
    write_block "$(phone_line)" "ecdsa-sha2-nistp256 ${BLOB}2 hand-added"
    run check_acm_phone_keys
    assert_contains "${output}" "FAIL:"
}

@test "a /nix/store forced command fails" {
    write_block "command=\"/nix/store/abc/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
    run check_acm_phone_keys
    assert_contains "${output}" "FAIL:"
}

@test "a forced command whose binary is missing fails: sshd would run nothing" {
    rm -f "${ACM_BIN}"
    write_block "$(phone_line)"
    run check_acm_phone_keys
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "${ACM_BIN}"
}

@test "an acm bridge line outside the block with a loose option fails" {
    write_block
    echo "command=\"${ACM_BIN} bridge --allow p3\",no-pty ecdsa-sha2-nistp256 ${BLOB} stray" >>"${MOCK_HOME}/.ssh/authorized_keys"
    run check_acm_phone_keys
    assert_contains "${output}" "FAIL:"
}

@test "an unrelated key whose comment says bridge is left alone" {
    write_block "$(phone_line)"
    echo "ssh-ed25519 AAAAother my bridge host" >>"${MOCK_HOME}/.ssh/authorized_keys"
    run check_acm_phone_keys
    assert_contains "${output}" "PASS: 1 phone key"
    assert_not_contains "${output}" "FAIL"
}

@test "a phone's key also present unrestricted outside the block fails" {
    write_block "$(phone_line)"
    echo "ecdsa-sha2-nistp256 ${BLOB} stray" >>"${MOCK_HOME}/.ssh/authorized_keys"
    run check_acm_phone_keys
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "outside"
}

@test "ntfy on the Tailscale IP only, firewalled and answering 403 passes" {
    stub_ntfy_host "${TS_IP}:2586"
    run check_ntfy
    assert_contains "${output}" "PASS: ntfy listens on ${TS_IP}:2586 only"
    assert_contains "${output}" "PASS: UFW"
    assert_contains "${output}" "PASS: anonymous"
    assert_not_contains "${output}" "FAIL"
    assert_not_contains "${output}" "WARN"
}

@test "ntfy on 0.0.0.0 fails" {
    stub_ntfy_host "0.0.0.0:2586"
    run check_ntfy
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "0.0.0.0:2586"
}

@test "ntfy on the Tailscale IP and a wildcard fails" {
    stub_ntfy_host "${TS_IP}:2586 [::]:2586"
    run check_ntfy
    assert_contains "${output}" "FAIL:"
}

@test "ntfy not listening at all fails" {
    stub_ntfy_host ""
    run check_ntfy
    assert_contains "${output}" "FAIL:"
}

@test "a stopped ntfy fails" {
    stub_ntfy_host "" failed
    run check_ntfy
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "journalctl -u ntfy"
}

@test "a missing UFW rule warns" {
    stub_ntfy_host "${TS_IP}:2586" active "22/tcp ALLOW Anywhere"
    run check_ntfy
    assert_contains "${output}" "WARN:"
}

@test "an anonymous read that succeeds fails: auth is off" {
    stub_ntfy_host "${TS_IP}:2586" active "2586/tcp on tailscale0 ALLOW IN Anywhere" 200
    run check_ntfy
    assert_contains "${output}" "FAIL:"
    assert_contains "${output}" "auth"
}

@test "ntfy not installed warns, as for node_exporter" {
    stub_ntfy_host "${TS_IP}:2586"
    rm -f "${NTFY_UNIT_FILE}"
    run check_ntfy
    assert_contains "${output}" "WARN:"
    assert_not_contains "${output}" "PASS"
}
