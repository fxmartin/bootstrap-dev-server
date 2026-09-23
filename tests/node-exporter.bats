#!/usr/bin/env bats
# ABOUTME: Tests for the node_exporter installer, start wrapper, unit and firewall scoping
# ABOUTME: Executes the installer offline against a file:// release fixture, root-safe

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export INSTALLER="${PROJECT_ROOT}/scripts/install-node-exporter.sh"
    export WRAPPER="${PROJECT_ROOT}/config/node-exporter-start.sh"
    export UNIT="${PROJECT_ROOT}/config/node-exporter.service"
    export VERIFY="${PROJECT_ROOT}/tests/verify-server.sh"

    # Every privileged or system-touching command resolves to a stub that
    # records its argv. This is the seam the CI contract asks for: the suite
    # runs as root in the job container, so nothing here may rely on
    # permission failures, and nothing may reach a real systemctl/ufw/useradd.
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export STUB_LOG="${TEST_TEMP_DIR}/stub.log"
    mkdir -p "${STUB_DIR}"
    : > "${STUB_LOG}"
    for cmd in systemctl ufw useradd; do
        cat > "${STUB_DIR}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "${cmd} \$*" >> "${STUB_LOG}"
EOF
        chmod +x "${STUB_DIR}/${cmd}"
    done
    # sudo runs its argument list directly - the stubs above take it from there.
    cat > "${STUB_DIR}/sudo" <<'EOF'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOF
    # getent reports the node_exporter user as present only when a flag says so.
    cat > "${STUB_DIR}/getent" <<EOF
#!/usr/bin/env bash
[[ -f "${TEST_TEMP_DIR}/user-exists" ]]
EOF
    # uname -m is the arch seam; everything else falls through to the real one.
    cat > "${STUB_DIR}/uname" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-m" ]]; then echo "\${UNAME_M:-x86_64}"; else /usr/bin/env uname "\$@"; fi
EOF
    chmod +x "${STUB_DIR}/sudo" "${STUB_DIR}/getent" "${STUB_DIR}/uname"
    export PATH="${STUB_DIR}:${PATH}"

    # Install targets, all under the temp tree.
    export NODE_EXPORTER_BIN_DIR="${TEST_TEMP_DIR}/usr-local-bin"
    export NODE_EXPORTER_UNIT_DIR="${TEST_TEMP_DIR}/systemd-system"
    export NODE_EXPORTER_TEXTFILE_DIR="${TEST_TEMP_DIR}/textfile"
}

teardown() {
    common_teardown
}

# Builds a fake upstream release under the temp tree and prints its file:// url.
# The tarball layout and sha256sums.txt format match the real release page.
make_release_fixture() {
    local version="$1" arch="$2"
    local rel="${TEST_TEMP_DIR}/release"
    local stage="${rel}/stage/node_exporter-${version}.linux-${arch}"
    mkdir -p "${stage}"
    cat > "${stage}/node_exporter" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then echo "node_exporter, version ${version} (fake)"; exit 0; fi
echo "fake node_exporter \$*"
EOF
    chmod +x "${stage}/node_exporter"
    tar -C "${rel}/stage" -czf "${rel}/node_exporter-${version}.linux-${arch}.tar.gz" \
        "node_exporter-${version}.linux-${arch}"
    (cd "${rel}" && sha256sum node_exporter-*.tar.gz > sha256sums.txt)
    echo "file://${rel}"
}

pinned_version() {
    sed -n 's/^NODE_EXPORTER_VERSION="\${NODE_EXPORTER_VERSION:-\([0-9.]*\)}"$/\1/p' "${INSTALLER}"
}

# =============================================================================
# Installer: pinning
# =============================================================================

@test "installer pins an explicit node_exporter version" {
    run pinned_version
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "installer never downloads from /releases/latest" {
    run grep -n 'releases/latest' "${INSTALLER}"
    [ "${status}" -ne 0 ]
}

@test "installer verifies sha256sums.txt before extracting" {
    run grep -q 'sha256sums.txt' "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run grep -q 'sha256sum -c' "${INSTALLER}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Installer: execution against the file:// fixture
# =============================================================================

@test "installer installs the verified binary, wrapper, unit, user and firewall rule" {
    local version
    version="$(pinned_version)"
    export NODE_EXPORTER_BASE_URL
    NODE_EXPORTER_BASE_URL="$(make_release_fixture "${version}" amd64)"

    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]

    # Binary is the one from the tarball
    [ -x "${NODE_EXPORTER_BIN_DIR}/node_exporter" ]
    run "${NODE_EXPORTER_BIN_DIR}/node_exporter" --version
    assert_contains "${output}" "version ${version}"

    # Wrapper and unit are copied verbatim from config/
    [ -x "${NODE_EXPORTER_BIN_DIR}/node-exporter-start" ]
    cmp -s "${WRAPPER}" "${NODE_EXPORTER_BIN_DIR}/node-exporter-start"
    cmp -s "${UNIT}" "${NODE_EXPORTER_UNIT_DIR}/node-exporter.service"

    # Reserved textfile directory exists
    [ -d "${NODE_EXPORTER_TEXTFILE_DIR}" ]

    # Dedicated nologin system user
    run grep 'useradd' "${STUB_LOG}"
    assert_contains "${output}" "--system"
    assert_contains "${output}" "nologin"
    assert_contains "${output}" "node_exporter"

    # Unit reloaded and enabled
    run grep 'systemctl' "${STUB_LOG}"
    assert_contains "${output}" "systemctl daemon-reload"
    assert_contains "${output}" "systemctl enable --now node-exporter.service"

    # Firewall: tailscale0 only
    run grep 'ufw' "${STUB_LOG}"
    assert_contains "${output}" "ufw allow in on tailscale0 to any port 9100 proto tcp"
}

@test "installer refuses a tarball whose checksum does not match" {
    local version
    version="$(pinned_version)"
    export NODE_EXPORTER_BASE_URL
    NODE_EXPORTER_BASE_URL="$(make_release_fixture "${version}" amd64)"
    local rel="${TEST_TEMP_DIR}/release"
    sed -i 's/^[0-9a-f]\{8\}/deadbeef/' "${rel}/sha256sums.txt"

    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "hecksum"
    assert_file_not_exists "${NODE_EXPORTER_BIN_DIR}/node_exporter"
    run grep -c 'systemctl enable' "${STUB_LOG}"
    [ "${output}" = "0" ]
}

@test "installer refuses when sha256sums.txt has no entry for the tarball" {
    local version
    version="$(pinned_version)"
    export NODE_EXPORTER_BASE_URL
    NODE_EXPORTER_BASE_URL="$(make_release_fixture "${version}" amd64)"
    : > "${TEST_TEMP_DIR}/release/sha256sums.txt"

    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "hecksum"
    assert_file_not_exists "${NODE_EXPORTER_BIN_DIR}/node_exporter"
}

@test "installer skips the download when the pinned version is already installed" {
    local version
    version="$(pinned_version)"
    # No release fixture at all: a download attempt would fail loudly.
    export NODE_EXPORTER_BASE_URL="file://${TEST_TEMP_DIR}/no-such-release"
    mkdir -p "${NODE_EXPORTER_BIN_DIR}"
    printf '#!/usr/bin/env bash\necho "node_exporter, version %s (fake)"\n' "${version}" \
        > "${NODE_EXPORTER_BIN_DIR}/node_exporter"
    chmod +x "${NODE_EXPORTER_BIN_DIR}/node_exporter"

    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "already installed"
}

@test "installer maps aarch64 to the linux-arm64 tarball" {
    local version
    version="$(pinned_version)"
    export NODE_EXPORTER_BASE_URL
    NODE_EXPORTER_BASE_URL="$(make_release_fixture "${version}" arm64)"
    export UNAME_M=aarch64

    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "linux-arm64"
    [ -x "${NODE_EXPORTER_BIN_DIR}/node_exporter" ]
}

@test "installer refuses an architecture without an upstream build" {
    export NODE_EXPORTER_BASE_URL="file://${TEST_TEMP_DIR}/unused"
    export UNAME_M=armv7l

    run bash "${INSTALLER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "nsupported"
}

@test "installer does not recreate an existing node_exporter user" {
    local version
    version="$(pinned_version)"
    export NODE_EXPORTER_BASE_URL
    NODE_EXPORTER_BASE_URL="$(make_release_fixture "${version}" amd64)"
    touch "${TEST_TEMP_DIR}/user-exists"

    run bash "${INSTALLER}"
    [ "${status}" -eq 0 ]
    run grep -c 'useradd' "${STUB_LOG}"
    [ "${output}" = "0" ]
}

# =============================================================================
# Start wrapper: tailnet-only bind with bounded backoff
# =============================================================================

# Installs a fake `tailscale` that fails the first $1 calls, then prints $2.
fake_tailscale() {
    local failures="$1" ip="${2:-100.64.0.5}"
    cat > "${STUB_DIR}/tailscale" <<EOF
#!/usr/bin/env bash
count_file="${TEST_TEMP_DIR}/tailscale-calls"
n=\$(( \$(cat "\${count_file}" 2>/dev/null || echo 0) + 1 ))
echo "\${n}" > "\${count_file}"
[[ "\${n}" -le ${failures} ]] && exit 1
echo "${ip}"
EOF
    chmod +x "${STUB_DIR}/tailscale"
}

# Installs a fake node_exporter that records its argv and exits.
fake_node_exporter() {
    export NODE_EXPORTER_BIN="${STUB_DIR}/node_exporter"
    cat > "${NODE_EXPORTER_BIN}" <<EOF
#!/usr/bin/env bash
echo "\$*" > "${TEST_TEMP_DIR}/node_exporter.argv"
EOF
    chmod +x "${NODE_EXPORTER_BIN}"
}

@test "wrapper binds node_exporter to the Tailscale IPv4 with the required collectors" {
    fake_tailscale 0 100.64.0.5
    fake_node_exporter
    export NODE_EXPORTER_TEXTFILE_DIR="${TEST_TEMP_DIR}/textfile"

    run bash "${WRAPPER}"
    [ "${status}" -eq 0 ]
    run cat "${TEST_TEMP_DIR}/node_exporter.argv"
    assert_contains "${output}" "--web.listen-address=100.64.0.5:9100"
    assert_contains "${output}" "--collector.systemd"
    assert_contains "${output}" "--collector.textfile.directory=${TEST_TEMP_DIR}/textfile"
    assert_not_contains "${output}" "0.0.0.0"
}

@test "wrapper waits for the tailnet with bounded backoff, then starts" {
    fake_tailscale 2 100.64.0.5
    fake_node_exporter
    export TAILNET_WAIT_ATTEMPTS=4
    export TAILNET_WAIT_SECONDS=0

    run bash "${WRAPPER}"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "retrying"
    [ "$(cat "${TEST_TEMP_DIR}/tailscale-calls")" = "3" ]
    run cat "${TEST_TEMP_DIR}/node_exporter.argv"
    assert_contains "${output}" "--web.listen-address=100.64.0.5:9100"
}

@test "wrapper exits non-zero without starting when the tailnet never comes up" {
    fake_tailscale 99
    fake_node_exporter
    export TAILNET_WAIT_ATTEMPTS=3
    export TAILNET_WAIT_SECONDS=0

    run bash "${WRAPPER}"
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "3 attempts"
    assert_file_not_exists "${TEST_TEMP_DIR}/node_exporter.argv"
    [ "$(cat "${TEST_TEMP_DIR}/tailscale-calls")" = "3" ]
}

@test "wrapper rejects a non-tailnet address rather than binding to it" {
    fake_tailscale 0 0.0.0.0
    fake_node_exporter
    export TAILNET_WAIT_ATTEMPTS=1
    export TAILNET_WAIT_SECONDS=0

    run bash "${WRAPPER}"
    [ "${status}" -ne 0 ]
    assert_file_not_exists "${TEST_TEMP_DIR}/node_exporter.argv"
}

@test "wrapper never contains a 0.0.0.0 bind" {
    run grep -n '0\.0\.0\.0' "${WRAPPER}"
    # The only mention allowed is the comment explaining why it is forbidden.
    run bash -c "grep -v '^ *#' '${WRAPPER}' | grep -c '0\.0\.0\.0' || true"
    [ "${output}" = "0" ]
}

# =============================================================================
# Unit file
# =============================================================================

@test "unit runs as the dedicated node_exporter user at system level" {
    run grep -q '^User=node_exporter$' "${UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^WantedBy=multi-user.target$' "${UNIT}"
    [ "${status}" -eq 0 ]
}

@test "unit starts through the wrapper, never node_exporter directly" {
    run grep -q '^ExecStart=/usr/local/bin/node-exporter-start$' "${UNIT}"
    [ "${status}" -eq 0 ]
    run grep -c 'listen-address' "${UNIT}"
    [ "${output}" = "0" ]
}

@test "unit orders after tailscaled and network-online" {
    run grep '^After=' "${UNIT}"
    assert_contains "${output}" "tailscaled.service"
    assert_contains "${output}" "network-online.target"
}

@test "unit rate-limits restarts so a dead tailnet cannot crash-loop forever" {
    run grep -q '^StartLimitBurst=' "${UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^StartLimitIntervalSec=' "${UNIT}"
    [ "${status}" -eq 0 ]
}

@test "unit declares StartLimit in the [Unit] section" {
    # systemd parses StartLimitIntervalSec/StartLimitBurst in [Unit], not [Service].
    run awk '/^\[Unit\]/{s="Unit"} /^\[Service\]/{s="Service"} /^StartLimit/{print s}' "${UNIT}"
    [ "${status}" -eq 0 ]
    [ -n "${output}" ]
    for section in ${output}; do
        [ "${section}" = "Unit" ]
    done
}

@test "unit documents the tailnet-only security model" {
    run grep -qi 'no authentication' "${UNIT}"
    [ "${status}" -eq 0 ]
    run grep -qi 'ACL' "${UNIT}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Bootstrap: firewall scoping and phase wiring
# =============================================================================

@test "bootstrap opens 9100 on tailscale0 only" {
    run grep -q "ufw allow in on tailscale0 to any port 9100 proto tcp" "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

@test "bootstrap never opens 9100 on the public interface" {
    run bash -c "grep -n 'ufw .*9100' '${BOOTSTRAP}' | grep -v 'in on tailscale0' || true"
    [ -z "${output}" ]
}

@test "bootstrap opens 9100 in both firewall modes" {
    # configure_firewall resets ufw on every run and returns early in
    # tailnet-only mode, so the rule has to be present on both paths.
    run grep -c "ufw allow in on tailscale0 to any port 9100 proto tcp" "${BOOTSTRAP}"
    [ "${output}" -ge 2 ]
}

@test "bootstrap delegates the install to scripts/install-node-exporter.sh" {
    run grep -q 'scripts/install-node-exporter.sh' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
    run grep -q '^    install_node_exporter$' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Bootstrap: legacy Beszel removal (executed)
# =============================================================================

source_remove_beszel_agent() {
    eval "$(awk '/^remove_beszel_agent\(\)/,/^}/' "${BOOTSTRAP}")"
    log_info() { echo "INFO: $*"; }
    log_ok() { echo "OK: $*"; }
}

@test "remove_beszel_agent disables the user unit and deletes every leftover" {
    export HOME="${MOCK_HOME}"
    mkdir -p "${HOME}/.config/systemd/user" "${HOME}/.local/bin"
    touch "${HOME}/.config/systemd/user/beszel-agent.service" \
        "${HOME}/.local/bin/beszel-agent" "${HOME}/.config/beszel-agent.env"
    source_remove_beszel_agent

    run remove_beszel_agent
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "removed"
    assert_file_not_exists "${HOME}/.config/systemd/user/beszel-agent.service"
    assert_file_not_exists "${HOME}/.local/bin/beszel-agent"
    assert_file_not_exists "${HOME}/.config/beszel-agent.env"
    run grep 'systemctl' "${STUB_LOG}"
    assert_contains "${output}" "systemctl --user disable --now beszel-agent"
    assert_contains "${output}" "systemctl --user daemon-reload"
}

@test "remove_beszel_agent is a no-op on a clean server" {
    export HOME="${MOCK_HOME}"
    source_remove_beszel_agent

    run remove_beszel_agent
    [ "${status}" -eq 0 ]
    run grep -c 'systemctl' "${STUB_LOG}"
    [ "${output}" = "0" ]
}

@test "the Beszel agent is gone from the tree, not left optional" {
    assert_file_not_exists "${PROJECT_ROOT}/lib/beszel.sh"
    assert_file_not_exists "${PROJECT_ROOT}/scripts/install-beszel-agent.sh"
    assert_file_not_exists "${PROJECT_ROOT}/config/beszel-agent.service"
    assert_file_not_exists "${PROJECT_ROOT}/tests/beszel-agent.bats"
    run grep -il 'beszel' "${PROJECT_ROOT}/README.md" "${PROJECT_ROOT}/CLAUDE.md" "${PROJECT_ROOT}/tests/README.md"
    [ -z "${output}" ]
}

# =============================================================================
# verify-server.sh coverage
# =============================================================================

@test "verify-server checks the node-exporter unit is active, not merely activating" {
    run grep -q 'node-exporter' "${VERIFY}"
    [ "${status}" -eq 0 ]
    run bash -c "grep -A12 'is-active node-exporter' '${VERIFY}' | grep -c activating"
    [ "${output}" -ge 1 ]
}

@test "verify-server scrapes /metrics on the Tailscale IP for node_exporter_build_info" {
    run grep -q 'node_exporter_build_info' "${VERIFY}"
    [ "${status}" -eq 0 ]
    run grep -q ':9100/metrics' "${VERIFY}"
    [ "${status}" -eq 0 ]
}

@test "verify-server fails when anything listens on 0.0.0.0:9100" {
    run grep -q 'ss -ltn' "${VERIFY}"
    [ "${status}" -eq 0 ]
    run grep -q '0\.0\.0\.0:9100' "${VERIFY}"
    [ "${status}" -eq 0 ]
}
