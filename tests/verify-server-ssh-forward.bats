#!/usr/bin/env bats
# ABOUTME: Tests the verify-server.sh check that sshd allows local forwards for acm peers
# ABOUTME: Runs offline against stubbed sudo/sshd; nothing real is queried

load 'test_helper'

setup() {
    common_setup
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    mkdir -p "${STUB_DIR}"
    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; }
    info() { echo "INFO: $1"; }
    # shellcheck disable=SC1090
    source <(sed -n '/^check_ssh_local_forwarding() {/,/^}$/p' "${PROJECT_ROOT}/tests/verify-server.sh")
}

teardown() {
    common_teardown
}

# sudo stub: `-n true` succeeds; `-n sshd -T` prints the value in $SSHD_FORWARDING.
stub_sudo() {
    cat >"${STUB_DIR}/sudo" <<'EOF2'
#!/usr/bin/env bash
[[ "$1" == "-n" ]] && shift
if [[ "$1" == "true" ]]; then exit 0; fi
if [[ "$1" == "sshd" ]]; then
    echo "port 22"
    echo "allowtcpforwarding ${SSHD_FORWARDING}"
    exit 0
fi
exit 1
EOF2
    chmod +x "${STUB_DIR}/sudo"
}

@test "effective allowtcpforwarding local passes" {
    stub_sudo
    export SSHD_FORWARDING=local
    PATH="${STUB_DIR}:${PATH}" run check_ssh_local_forwarding
    [[ "${output}" == PASS:* ]]
}

@test "effective allowtcpforwarding no fails with a re-run hint" {
    stub_sudo
    export SSHD_FORWARDING=no
    PATH="${STUB_DIR}:${PATH}" run check_ssh_local_forwarding
    [[ "${output}" == *"FAIL:"* ]]
    [[ "${output}" == *"INFO: Re-run the bootstrap with the hardening phase"* ]]
}

@test "no passwordless sudo gives an INFO, not a FAIL" {
    printf '#!/usr/bin/env bash\nexit 1\n' >"${STUB_DIR}/sudo"
    chmod +x "${STUB_DIR}/sudo"
    PATH="${STUB_DIR}:${PATH}" run check_ssh_local_forwarding
    [ "$status" -eq 0 ]
    [[ "${output}" == INFO:* ]]
    [[ "${output}" != *FAIL* ]]
}

@test "unparseable sshd -T output fails and reports unknown" {
    stub_sudo
    export SSHD_FORWARDING=""
    PATH="${STUB_DIR}:${PATH}" run check_ssh_local_forwarding
    [[ "${output}" == *"FAIL:"*"unknown"* ]]
}
