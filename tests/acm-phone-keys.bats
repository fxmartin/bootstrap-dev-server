#!/usr/bin/env bats
# ABOUTME: Tests installing phone keys into authorized_keys: restricted to acm bridge, revocable
# ABOUTME: Executes scripts/setup-acm-fleet.sh offline against a sandboxed HOME

load 'test_helper'

BEGIN="# >>> bootstrap-dev-server acm phones >>>"
END="# <<< bootstrap-dev-server acm phones <<<"
BLOB="AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFakePhoneKey0123456789+/abcdefghij=="
OTHER="AAAAC3NzaC1lZDI1NTE5AAAAIFakeSecondPhoneKey0123456789abcdefghijklm"
LAPTOP="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaptopKeyMustSurviveEverything0123456789ab fx@laptop"

# What `acm mobile key-line` prints.
phone_line() {
    local name="${1:-pixel-10-pro}" blob="${2:-${BLOB}}" level="${3:-p3}"
    local type=ecdsa-sha2-nistp256
    [[ "${blob}" == "${OTHER}" ]] && type=ssh-ed25519
    echo "command=\"/home/fx/.nix-profile/bin/acm bridge --allow ${level}\",restrict ${type} ${blob} ${name}"
}

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export SETUP="${PROJECT_ROOT}/scripts/setup-acm-fleet.sh"
    export HOME="${MOCK_HOME}"
    export AUTH="${MOCK_HOME}/.ssh/authorized_keys"
    unset XDG_CONFIG_HOME

    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    mkdir -p "${STUB_DIR}" "${MOCK_HOME}/.ssh"
    printf '#!/usr/bin/env bash\nexit 1\n' >"${STUB_DIR}/systemctl"
    chmod +x "${STUB_DIR}/systemctl"
    export PATH="${STUB_DIR}:${PATH}"

    export ACM_PEERS_FILE="${PROJECT_ROOT}/config/acm-peers.toml"
    export ACM_PHONE_KEYS_FILE="${TEST_TEMP_DIR}/phones.pub"
    echo "${LAPTOP}" >"${AUTH}"
    chmod 600 "${AUTH}"
}

teardown() {
    common_teardown
}

block() {
    sed -n "/^${BEGIN}\$/,/^${END}\$/p" "${AUTH}"
}

@test "the repo's phone file ships no key and documents the line format" {
    local file="${PROJECT_ROOT}/config/acm-phone-keys.pub"
    assert_file_exists "${file}"
    run grep -vE '^(#|$)' "${file}"
    [ "${status}" -ne 0 ]
    grep -q 'acm mobile key-line' "${file}"
}

@test "a key-line lands in a marker block and the operator's key is untouched" {
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qxF "${LAPTOP}" "${AUTH}"
    run block
    assert_contains "${output}" "$(phone_line)"
    [ "$(stat -c '%a' "${AUTH}")" = "600" ]
}

@test "authorized_keys is created private when it does not exist" {
    rm -f "${AUTH}"
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%a' "${AUTH}")" = "600" ]
}

@test "ed25519 keys and all three levels are accepted, comments and blanks skipped" {
    {
        echo "# phones"
        echo
        phone_line a "${BLOB}" p1
        phone_line b "${OTHER}" p2
        phone_line c "${BLOB}" p3
    } >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(block | grep -c '^command=')" -eq 3 ]
}

@test "revoking: an entry removed from the file leaves authorized_keys on the next run" {
    {
        phone_line pixel-10-pro
        phone_line tablet "${OTHER}"
    } >"${ACM_PHONE_KEYS_FILE}"
    bash "${SETUP}"
    phone_line tablet "${OTHER}" >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    run grep -c "${BLOB}" "${AUTH}"
    [ "${output}" = "0" ]
    grep -qF "${OTHER}" "${AUTH}"
    grep -qxF "${LAPTOP}" "${AUTH}"
}

@test "revoking the last phone empties the block" {
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    bash "${SETUP}"
    : >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    run grep -c "${BLOB}" "${AUTH}"
    [ "${output}" = "0" ]
}

@test "no phones and no block: authorized_keys is not touched at all" {
    : >"${ACM_PHONE_KEYS_FILE}"
    # Back-dated so a write is caught even within stat's one-second resolution.
    touch -d '2020-01-01 00:00:00' "${AUTH}"
    local before
    before="$(stat -c '%Y %s' "${AUTH}")"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%Y %s' "${AUTH}")" = "${before}" ]
    [ "$(cat "${AUTH}")" = "${LAPTOP}" ]
}

@test "a phones block with no end marker fails the run: a revocation that did not apply is never reported as done" {
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    bash "${SETUP}"
    sed -i "\\|^${END}\$|d" "${AUTH}"
    : >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "closing marker"
    [[ "${output}" != *"phone key(s) up to date"* ]]
    [[ "${output}" != *"phone key(s) installed"* ]]
}

# Line of the first match of an extended regex in a file, 0 when absent.
first_line() {
    grep -nE -- "$1" "$2" | head -n 1 | cut -d: -f1 | grep . || echo 0
}

@test "the README revokes in the order that reaches the clone: merge, dev-update, then both scripts" {
    local readme="${PROJECT_ROOT}/README.md"
    local heading merge pull fleet ntfy
    heading="$(first_line '^\*\*Revoking a phone\.\*\*' "${readme}")"
    [ "${heading}" -gt 0 ]
    local section="${TEST_TEMP_DIR}/revoking.md"
    tail -n "+${heading}" "${readme}" | sed '/^\*\*ntfy\*\*/,$d' >"${section}"

    merge="$(first_line 'merge request' "${section}")"
    pull="$(first_line '^dev-update$' "${section}")"
    fleet="$(first_line 'bash .*scripts/setup-acm-fleet\.sh' "${section}")"
    ntfy="$(first_line 'bash .*scripts/install-ntfy\.sh' "${section}")"
    [ "${merge}" -gt 0 ]
    [ "${pull}" -gt "${merge}" ]
    [ "${fleet}" -gt "${pull}" ]
    [ "${ntfy}" -gt "${fleet}" ]
}

@test "the README's urgent revocation brings the override into force before the scripts run" {
    local readme="${PROJECT_ROOT}/README.md"
    local heading
    heading="$(first_line '^\*\*Revoking a phone\.\*\*' "${readme}")"
    tail -n "+${heading}" "${readme}" | sed '/^\*\*ntfy\*\*/,$d' >"${TEST_TEMP_DIR}/revoking.md"
    grep -qF 'cp ~/.local/share/bootstrap-dev-server/config/acm-phone-keys.pub ~/.config/acm/phone-keys.pub' "${TEST_TEMP_DIR}/revoking.md"
}

@test "no revocation note promises a re-run alone, without bringing the clone up to date" {
    run grep -n 'by removing its line and re-running' "${PROJECT_ROOT}/config/acm-phone-keys.pub"
    [ "${status}" -ne 0 ]
    run grep -n 'remove its line and re-run the bootstrap' "${PROJECT_ROOT}/docs/fleet-onboarding.md"
    [ "${status}" -ne 0 ]
    grep -q 'dev-update' "${PROJECT_ROOT}/config/acm-phone-keys.pub"
    run grep -n 'after revoking a phone' "${SETUP}"
    [ "${status}" -ne 0 ]
    run grep -n 'Removing a line and re-running revokes it' "${PROJECT_ROOT}/docs/stories/epic-01-agentic-fleet-host.md"
    [ "${status}" -ne 0 ]
}

@test "a re-run with the same phones does not rewrite authorized_keys" {
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    bash "${SETUP}"
    local before
    before="$(cat "${AUTH}")"
    rm -f "${AUTH}.backup"
    bash "${SETUP}"
    [ "$(cat "${AUTH}")" = "${before}" ]
    assert_file_not_exists "${AUTH}.backup"
}

# Each of these must never reach authorized_keys.
assert_refused() {
    local line="$1"
    { phone_line tablet "${OTHER}"; echo "${line}"; } >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "line 2"
    run grep -cF -- "${line}" "${AUTH}"
    [ "${output}" = "0" ]
    # The rest still converges, so one typo cannot hold a revocation back.
    grep -qF "${OTHER}" "${AUTH}"
    grep -qxF "${LAPTOP}" "${AUTH}"
}

@test "refused: a bare key with no forced command" {
    assert_refused "ecdsa-sha2-nistp256 ${BLOB} pixel-10-pro"
}

@test "refused: a forced command without restrict" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\" ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: restrict re-opened with another option" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\",restrict,port-forwarding ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: a forced command that is not acm bridge" {
    assert_refused "command=\"/bin/bash\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: acm bridge chained to something else" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3; /bin/sh\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: a relative acm path" {
    assert_refused "command=\"acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: a /nix/store acm path, which garbage collection deletes" {
    assert_refused "command=\"/nix/store/abc-acm/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: a /nix/store path dressed up with .." {
    assert_refused "command=\"/home/../nix/store/abc-acm/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: an unknown level" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p9\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel"
}

@test "refused: a key type the Android Keystore cannot hold" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\",restrict ssh-rsa ${BLOB} pixel"
}

@test "refused: a name with spaces, which would break the ntfy user" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} pixel 10"
}

@test "refused: the name everyone, which ntfy reads as anonymous" {
    assert_refused "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} everyone"
}

@test "a private key in the file is refused and its body never reaches authorized_keys" {
    printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----\n' >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    run grep -c 'b3BlbnNzaC1rZXktdjEAAAAA' "${AUTH}"
    [ "${output}" = "0" ]
}

@test "the same key unrestricted outside the block fails the run: it would bypass the forced command" {
    echo "ecdsa-sha2-nistp256 ${BLOB} stray" >>"${AUTH}"
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "outside"
}

@test "a missing keys file fails and leaves the block as it is: nothing is revoked by accident" {
    phone_line >"${ACM_PHONE_KEYS_FILE}"
    bash "${SETUP}"
    export ACM_PHONE_KEYS_FILE="${TEST_TEMP_DIR}/nope.pub"
    run bash "${SETUP}"
    [ "${status}" -ne 0 ]
    grep -qF "${BLOB}" "${AUTH}"
}

@test "the secret path wins over the repo file when ACM_PHONE_KEYS_FILE is unset" {
    unset ACM_PHONE_KEYS_FILE
    mkdir -p "${MOCK_HOME}/.config/acm"
    phone_line >"${MOCK_HOME}/.config/acm/phone-keys.pub"
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    grep -qF "${BLOB}" "${AUTH}"
}

@test "with neither set the repo file is used" {
    unset ACM_PHONE_KEYS_FILE
    run bash "${SETUP}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${AUTH}")" = "${LAPTOP}" ]
}
