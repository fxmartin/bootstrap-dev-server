#!/usr/bin/env bats
# ABOUTME: Tests the ntfy installer, start wrapper, unit, server config and firewall scoping
# ABOUTME: Executes the installer offline against a file:// release fixture, root-safe

load 'test_helper'

BLOB="AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFakePhoneKey0123456789+/abcdefghij=="

phone_line() {
    echo "command=\"/home/fx/.nix-profile/bin/acm bridge --allow p3\",restrict ecdsa-sha2-nistp256 ${BLOB} ${1}"
}

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export INSTALLER="${PROJECT_ROOT}/scripts/install-ntfy.sh"
    export WRAPPER="${PROJECT_ROOT}/config/ntfy-start.sh"
    export UNIT="${PROJECT_ROOT}/config/ntfy.service"
    export SERVER_YML="${PROJECT_ROOT}/config/ntfy-server.yml"
    export HOME="${MOCK_HOME}"
    unset XDG_CONFIG_HOME

    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export STUB_LOG="${TEST_TEMP_DIR}/stub.log"
    mkdir -p "${STUB_DIR}"
    : >"${STUB_LOG}"
    for cmd in systemctl ufw useradd chown chgrp; do
        cat >"${STUB_DIR}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "${cmd} \$*" >>"${STUB_LOG}"
EOF
        chmod +x "${STUB_DIR}/${cmd}"
    done
    cat >"${STUB_DIR}/sudo" <<'EOF'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOF
    cat >"${STUB_DIR}/getent" <<EOF
#!/usr/bin/env bash
[[ -f "${TEST_TEMP_DIR}/user-exists" ]]
EOF
    cat >"${STUB_DIR}/uname" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-m" ]]; then echo "\${UNAME_M:-x86_64}"; else /usr/bin/env uname "\$@"; fi
EOF
    chmod +x "${STUB_DIR}/sudo" "${STUB_DIR}/getent" "${STUB_DIR}/uname"
    export PATH="${STUB_DIR}:${PATH}"

    export NTFY_BIN_DIR="${TEST_TEMP_DIR}/usr-local-bin"
    export NTFY_UNIT_DIR="${TEST_TEMP_DIR}/systemd-system"
    export NTFY_CONFIG_DIR="${TEST_TEMP_DIR}/etc-ntfy"
    export NTFY_CREDENTIALS_DIR="${MOCK_HOME}/.config/acm/ntfy"
    export ACM_PHONE_KEYS_FILE="${TEST_TEMP_DIR}/phones.pub"
    : >"${ACM_PHONE_KEYS_FILE}"
    export NTFY_VERSION=9.9.9
}

teardown() {
    common_teardown
}

# A fake upstream release; layout and checksums.txt format match the real page.
make_release_fixture() {
    local version="$1" arch="$2"
    local rel="${TEST_TEMP_DIR}/release"
    local stage="${rel}/stage/ntfy_${version}_linux_${arch}"
    mkdir -p "${stage}"
    cat >"${stage}/ntfy" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then echo "ntfy version ${version}"; exit 0; fi
if [[ "\${1:-} \${2:-}" == "user hash" ]]; then
    read -r first; read -r second
    [[ -n "\${first}" && "\${first}" == "\${second}" ]] || exit 1
    echo "\\\$2a\\\$10\\\$fakehashof\${#first}chars\${RANDOM}"
    exit 0
fi
EOF
    chmod +x "${stage}/ntfy"
    tar -C "${rel}/stage" -czf "${rel}/ntfy_${version}_linux_${arch}.tar.gz" "ntfy_${version}_linux_${arch}"
    (cd "${rel}" && sha256sum ntfy_*.tar.gz >checksums.txt)
    export NTFY_BASE_URL="file://${rel}"
}

rendered() {
    cat "${NTFY_CONFIG_DIR}/server.yml"
}

# =============================================================================
# Installer
# =============================================================================

@test "the pinned version lives in versions.env and the installer reads it" {
    grep -qE '^NTFY_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "${PROJECT_ROOT}/config/versions.env"
    grep -q 'versions.env' "${INSTALLER}"
}

@test "installs the pinned binary, wrapper, unit and config, and enables the service" {
    make_release_fixture 9.9.9 amd64
    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    [ -x "${NTFY_BIN_DIR}/ntfy" ]
    [ -x "${NTFY_BIN_DIR}/ntfy-start" ]
    assert_file_exists "${NTFY_UNIT_DIR}/ntfy.service"
    assert_file_exists "${NTFY_CONFIG_DIR}/server.yml"
    grep -q 'systemctl enable ntfy.service' "${STUB_LOG}"
    grep -q 'useradd --system' "${STUB_LOG}"
}

@test "arm64 fetches the arm64 tarball" {
    make_release_fixture 9.9.9 arm64
    UNAME_M=aarch64 run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    [ -x "${NTFY_BIN_DIR}/ntfy" ]
}

@test "an unsupported architecture refuses" {
    make_release_fixture 9.9.9 amd64
    UNAME_M=riscv64 run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "Unsupported architecture"
    [ ! -e "${NTFY_BIN_DIR}/ntfy" ]
}

@test "a checksum mismatch refuses and installs nothing" {
    make_release_fixture 9.9.9 amd64
    echo tampered >>"${TEST_TEMP_DIR}/release/ntfy_9.9.9_linux_amd64.tar.gz"
    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "Checksum mismatch"
    [ ! -e "${NTFY_BIN_DIR}/ntfy" ]
}

@test "a release with no checksum entry refuses" {
    make_release_fixture 9.9.9 amd64
    : >"${TEST_TEMP_DIR}/release/checksums.txt"
    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "No checksum"
    [ ! -e "${NTFY_BIN_DIR}/ntfy" ]
}

@test "a re-run with nothing changed downloads nothing and does not restart" {
    make_release_fixture 9.9.9 amd64
    bash "${INSTALLER}"
    rm -rf "${TEST_TEMP_DIR}/release"
    touch "${TEST_TEMP_DIR}/user-exists"
    : >"${STUB_LOG}"
    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run grep 'restart' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
    grep -q 'systemctl start ntfy.service' "${STUB_LOG}"
}

@test "a version bump upgrades the binary and restarts the service" {
    make_release_fixture 9.9.9 amd64
    bash "${INSTALLER}"
    make_release_fixture 9.9.10 amd64
    : >"${STUB_LOG}"
    NTFY_VERSION=9.9.10 run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    "${NTFY_BIN_DIR}/ntfy" --version | grep -q '9.9.10'
    grep -q 'systemctl restart ntfy.service' "${STUB_LOG}"
}

@test "UFW opens the port on tailscale0 only" {
    make_release_fixture 9.9.9 amd64
    bash "${INSTALLER}"
    grep -q 'ufw allow in on tailscale0 to any port 2586 proto tcp' "${STUB_LOG}"
    [ "$(grep -c '^ufw' "${STUB_LOG}")" -eq 1 ]
}

@test "configure_firewall opens ntfy on tailscale0 on both paths, never publicly" {
    run bash -c "sed -n '/^configure_firewall() {/,/^}\$/p' '${BOOTSTRAP}' | grep -c 'ufw allow in on tailscale0 to any port 2586 proto tcp'"
    [ "${output}" = "2" ]
    run bash -c "sed -n '/^configure_firewall() {/,/^}\$/p' '${BOOTSTRAP}' | grep '2586' | grep -v 'in on tailscale0'"
    [ "${status}" -ne 0 ]
}

@test "main installs ntfy in the monitoring phase, before the final SSH reload" {
    local body
    body="$(sed -n '/^main() {/,/^}$/p' "${BOOTSTRAP}")"
    [ "$(grep -n '^ *install_node_exporter' <<<"${body}" | cut -d: -f1)" -lt "$(grep -n '^ *install_ntfy' <<<"${body}" | cut -d: -f1)" ]
    [ "$(grep -n '^ *install_ntfy' <<<"${body}" | cut -d: -f1)" -lt "$(grep -n '^ *restart_ssh_final' <<<"${body}" | cut -d: -f1)" ]
}

@test "an ntfy failure does not stop the bootstrap" {
    # shellcheck disable=SC1090
    source <(sed -n '/^install_ntfy() {/,/^}$/p' "${BOOTSTRAP}")
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1"; }
    export REPO_CLONE_DIR="${TEST_TEMP_DIR}/clone" BOOTSTRAP_SUBDIR="."
    mkdir -p "${REPO_CLONE_DIR}/scripts"
    printf 'exit 1\n' >"${REPO_CLONE_DIR}/scripts/install-ntfy.sh"
    run install_ntfy
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "re-run"
}

# =============================================================================
# Server config: auth on, a user and topic per phone
# =============================================================================

@test "the server config denies by default, keeps state, and turns off public features" {
    grep -q '^auth-default-access: "deny-all"$' "${SERVER_YML}"
    grep -q '^auth-file: "/var/lib/ntfy/user.db"$' "${SERVER_YML}"
    grep -q '^cache-file: "/var/lib/ntfy/cache.db"$' "${SERVER_YML}"
    grep -q '^enable-signup: false$' "${SERVER_YML}"
    grep -q '^web-root: disable$' "${SERVER_YML}"
    run grep -E '^(listen-http|listen-https|upstream-base-url):' "${SERVER_YML}"
    [ "${status}" -ne 0 ]
}

@test "with no phones nothing but UnifiedPush's anonymous publish is granted" {
    make_release_fixture 9.9.9 amd64
    bash "${INSTALLER}"
    run rendered
    assert_not_contains "${output}" "auth-users"
    assert_contains "${output}" '"*:up*:write-only"'
}

@test "each phone gets a user and a topic, plus read on the UnifiedPush prefix" {
    make_release_fixture 9.9.9 amd64
    phone_line pixel-10-pro >"${ACM_PHONE_KEYS_FILE}"
    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run rendered
    assert_output_matches '"pixel-10-pro:\$2a\$10\$[^:"]+:user"'
    assert_contains "${output}" '"pixel-10-pro:acm-pixel-10-pro:read-write"'
    assert_contains "${output}" '"pixel-10-pro:up*:read-only"'
    assert_contains "${output}" '"*:up*:write-only"'
}

@test "the phone's password is private, stable across runs and never logged" {
    make_release_fixture 9.9.9 amd64
    phone_line pixel-10-pro >"${ACM_PHONE_KEYS_FILE}"
    run bash "${INSTALLER}"
    local pw_file="${NTFY_CREDENTIALS_DIR}/pixel-10-pro.password"
    [ "$(stat -c '%a' "${pw_file}")" = "600" ]
    [ "$(stat -c '%a' "${NTFY_CREDENTIALS_DIR}")" = "700" ]
    local pw
    pw="$(cat "${pw_file}")"
    [ "${#pw}" -ge 24 ]
    assert_not_contains "${output}" "${pw}"
    assert_contains "${output}" "${pw_file}"

    local before
    before="$(rendered)"
    : >"${STUB_LOG}"
    run bash "${INSTALLER}"
    assert_not_contains "${output}" "${pw}"
    [ "$(cat "${pw_file}")" = "${pw}" ]
    [ "$(rendered)" = "${before}" ]
    run grep 'restart' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "the rendered config is not world-readable: it holds password hashes" {
    make_release_fixture 9.9.9 amd64
    phone_line pixel-10-pro >"${ACM_PHONE_KEYS_FILE}"
    bash "${INSTALLER}"
    [ "$(stat -c '%a' "${NTFY_CONFIG_DIR}/server.yml")" = "640" ]
    grep -q 'chgrp ntfy .*server.yml' "${STUB_LOG}"
}

@test "revoking a phone removes its user, topic and credentials, and restarts ntfy" {
    make_release_fixture 9.9.9 amd64
    {
        phone_line pixel-10-pro
        phone_line tablet
    } >"${ACM_PHONE_KEYS_FILE}"
    bash "${INSTALLER}"
    phone_line tablet >"${ACM_PHONE_KEYS_FILE}"
    : >"${STUB_LOG}"
    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run rendered
    assert_not_contains "${output}" "pixel-10-pro"
    assert_contains "${output}" "acm-tablet"
    assert_file_not_exists "${NTFY_CREDENTIALS_DIR}/pixel-10-pro.password"
    assert_file_not_exists "${NTFY_CREDENTIALS_DIR}/pixel-10-pro.hash"
    grep -q 'systemctl restart ntfy.service' "${STUB_LOG}"
}

@test "two keys with one name make one ntfy user, and invalid lines make none" {
    make_release_fixture 9.9.9 amd64
    {
        phone_line pixel-10-pro
        phone_line pixel-10-pro
        echo "ssh-ed25519 AAAA unrestricted"
    } >"${ACM_PHONE_KEYS_FILE}"
    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run rendered
    [ "$(grep -c ':user"' <<<"${output}")" -eq 1 ]
    assert_not_contains "${output}" "unrestricted"
}

@test "a missing keys file fails before the config is rewritten: no user is dropped by accident" {
    make_release_fixture 9.9.9 amd64
    phone_line pixel-10-pro >"${ACM_PHONE_KEYS_FILE}"
    bash "${INSTALLER}"
    export ACM_PHONE_KEYS_FILE="${TEST_TEMP_DIR}/nope.pub"
    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    run rendered
    assert_contains "${output}" "pixel-10-pro"
}

# =============================================================================
# Start wrapper: Tailscale IP or nothing
# =============================================================================

make_tailscale_stub() {
    printf '#!/usr/bin/env bash\necho "%s"\n' "$1" >"${STUB_DIR}/tailscale"
    chmod +x "${STUB_DIR}/tailscale"
    printf '#!/usr/bin/env bash\necho "ntfy $*"\n' >"${TEST_TEMP_DIR}/fake-ntfy"
    chmod +x "${TEST_TEMP_DIR}/fake-ntfy"
    export NTFY_BIN="${TEST_TEMP_DIR}/fake-ntfy" TAILSCALE_BIN="${STUB_DIR}/tailscale"
    export TAILNET_WAIT_ATTEMPTS=2 TAILNET_WAIT_SECONDS=0
}

@test "the wrapper binds to the Tailscale IP and advertises it as the base URL" {
    make_tailscale_stub 100.93.110.61
    run bash "${WRAPPER}"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "serve"
    assert_contains "${output}" "--listen-http 100.93.110.61:2586"
    assert_contains "${output}" "--base-url http://100.93.110.61:2586"
    assert_contains "${output}" "--config /etc/ntfy/server.yml"
}

@test "the wrapper refuses to start without a tailnet address" {
    make_tailscale_stub ""
    run bash "${WRAPPER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "refusing to start"
    assert_not_contains "${output}" "serve"
}

@test "the wrapper refuses a non-tailnet address" {
    make_tailscale_stub 203.0.113.7
    run bash "${WRAPPER}"
    [ "${status}" -ne 0 ]
    assert_not_contains "${output}" "serve"
}

@test "the unit runs the wrapper as the ntfy user, sandboxed, with a capped restart loop" {
    grep -q '^User=ntfy$' "${UNIT}"
    grep -q '^ExecStart=/usr/local/bin/ntfy-start$' "${UNIT}"
    grep -q '^NoNewPrivileges=true$' "${UNIT}"
    grep -q '^ProtectSystem=strict$' "${UNIT}"
    grep -q '^StateDirectory=ntfy$' "${UNIT}"
    grep -q '^StartLimitBurst=' "${UNIT}"
}
