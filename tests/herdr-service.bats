#!/usr/bin/env bats
# ABOUTME: Tests for the herdr server user service and the flake's pinned herdr 0.9.3
# ABOUTME: Runs offline and root-safe against stubbed systemctl/loginctl/pgrep; no real systemd is touched

load 'test_helper'

bats_require_minimum_version 1.5.0

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export FLAKE="${PROJECT_ROOT}/flake.nix"
    export UNIT_FILE="${MOCK_HOME}/.config/systemd/user/herdr.service"
    export SOCKET="${MOCK_HOME}/.config/herdr/herdr.sock"

    # systemctl, loginctl and sudo are the seams: each records its argv, and the
    # state files below steer the answers. Nothing reaches a real service manager.
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export STUB_LOG="${TEST_TEMP_DIR}/stub.log"
    mkdir -p "${STUB_DIR}"
    : >"${STUB_LOG}"
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >>"${STUB_LOG}"
case "\$*" in
    "--user show-environment") [[ ! -f "${TEST_TEMP_DIR}/no-user-manager" ]] ;;
    "--user is-active --quiet herdr.service") [[ -f "${TEST_TEMP_DIR}/unit-active" ]] ;;
    *) exit 0 ;;
esac
EOF
    cat >"${STUB_DIR}/loginctl" <<EOF
#!/usr/bin/env bash
echo "loginctl \$*" >>"${STUB_LOG}"
if [[ "\${1:-}" == "show-user" ]]; then
    [[ -f "${TEST_TEMP_DIR}/linger-on" ]] && echo yes || echo no
fi
exit 0
EOF
    cat >"${STUB_DIR}/sudo" <<'EOF'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOF
    chmod +x "${STUB_DIR}/systemctl" "${STUB_DIR}/loginctl" "${STUB_DIR}/sudo"
    export PATH="${STUB_DIR}:${PATH}"
    stub_pgrep

    # The profile holds herdr, as it does once install_dev_profile has run.
    mkdir -p "${MOCK_HOME}/.nix-profile/bin"
    printf '#!/usr/bin/env bash\necho "herdr 0.9.3"\n' >"${MOCK_HOME}/.nix-profile/bin/herdr"
    chmod +x "${MOCK_HOME}/.nix-profile/bin/herdr"

    # HERDR_ENV too: the suite may itself run from a herdr pane.
    unset RESTART_HERDR HERDR_ENV

    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    local fn
    for fn in herdr_unit_content herdr_server_pids stop_unmanaged_herdr ensure_linger setup_herdr_service; do
        # shellcheck disable=SC1090
        source <(sed -n "/^${fn}()/,/^}\$/p" "${BOOTSTRAP}")
    done
}

teardown() {
    if [[ -n "${FOREIGN_PID:-}" ]]; then
        kill -KILL "${FOREIGN_PID}" 2>/dev/null || true
    fi
    common_teardown
}

# pgrep answers from the pids in $TEST_TEMP_DIR/procs that are alive and not
# zombies (PID 1 in the job container never reaps, so kill -0 would lie).
stub_pgrep() {
    : >"${TEST_TEMP_DIR}/procs"
    cat >"${STUB_DIR}/pgrep" <<EOF
#!/usr/bin/env bash
while read -r pid; do
    [[ -n "\${pid}" ]] || continue
    state="\$(awk '/^State:/ {print \$2}' "/proc/\${pid}/status" 2>/dev/null || true)"
    [[ -n "\${state}" && "\${state}" != "Z" ]] && echo "\${pid}"
done <"${TEST_TEMP_DIR}/procs"
exit 0
EOF
    chmod +x "${STUB_DIR}/pgrep"
}

# A long-lived stand-in for a herdr server started outside the unit.
start_foreign_server() {
    sleep 300 &
    FOREIGN_PID=$!
    echo "${FOREIGN_PID}" >"${TEST_TEMP_DIR}/procs"
}

foreign_alive() {
    local state
    state="$(awk '/^State:/ {print $2}' "/proc/${FOREIGN_PID}/status" 2>/dev/null || true)"
    [[ -n "${state}" && "${state}" != "Z" ]]
}

# =============================================================================
# Flake: herdr pinned to the fleet version through an overlay
# =============================================================================

@test "flake pins herdr 0.9.3 from upstream's linux x86_64 release binary" {
    run grep -F 'version = "0.9.3";' "${FLAKE}"
    [ "${status}" -eq 0 ]
    run grep -F 'https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64' "${FLAKE}"
    [ "${status}" -eq 0 ]
}

@test "flake pins the herdr release binary by hash" {
    run grep -F 'hash = "sha256-GKjcZfHC+khYhDRDVt6hz9kRxvBs9G+njhk/QIf026c=";' "${FLAKE}"
    [ "${status}" -eq 0 ]
}

@test "the pinned hash is the SHA-256 the XPS's pacman package carries" {
    local sri hex
    sri="$(sed -n 's/.*hash = "sha256-\(GKjc[^"]*\)";.*/\1/p' "${FLAKE}")"
    hex="$(printf '%s' "${sri}" | base64 -d | od -An -v -tx1 | tr -d ' \n')"
    [[ "${hex}" == 18a8dc65* ]]
    [[ "${hex}" == *f4dba7 ]]
}

@test "the overlay applies on x86_64-linux only; other systems keep prev.herdr" {
    run grep -F 'prev.stdenv.hostPlatform.system == "x86_64-linux"' "${FLAKE}"
    [ "${status}" -eq 0 ]
    run grep -E "^ +prev\\.herdr;\$" "${FLAKE}"
    [ "${status}" -eq 0 ]
}

@test "the overlay installs the release binary without a source build" {
    run grep -F 'install -Dm755 "$src" "$out/bin/herdr"' "${FLAKE}"
    [ "${status}" -eq 0 ]
    run grep -F 'dontUnpack = true;' "${FLAKE}"
    [ "${status}" -eq 0 ]
}

@test "a comment says to drop the overlay once nixpkgs ships the fleet version" {
    run grep -iE 'drop this overlay once the fleet moves to a version nixpkgs ships' "${FLAKE}"
    [ "${status}" -eq 0 ]
}

@test "nixpkgs is imported with the herdr overlay, and the env and shell use pkgs.herdr" {
    run grep -F 'overlays = [ herdrOverlay ];' "${FLAKE}"
    [ "${status}" -eq 0 ]
    run grep -cE '^ +pkgs\.herdr$' "${FLAKE}"
    [ "${output}" -eq 1 ]
    # one definition only: the minimal/python shells do not carry herdr
    run grep -cE 'herdr *=' "${FLAKE}"
    [ "${output}" -eq 1 ]
}

# =============================================================================
# Unit content
# =============================================================================

@test "unit runs 'herdr server' from the profile with the profile on PATH" {
    run herdr_unit_content
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "ExecStart=%h/.nix-profile/bin/herdr server"
    assert_contains "${output}" 'Environment="PATH=%h/.nix-profile/bin:'
}

@test "unit PATH also reaches nix and the sbin directories, as a login shell does" {
    run herdr_unit_content
    assert_contains "${output}" ":/nix/var/nix/profiles/default/bin:"
    assert_contains "${output}" ":/usr/sbin:"
}

@test "unit restarts on failure and is wanted by default.target" {
    run herdr_unit_content
    assert_contains "${output}" "Restart=on-failure"
    assert_contains "${output}" "WantedBy=default.target"
}

@test "unit survives one pane being OOM-killed (OOMPolicy=continue, not systemd's stop)" {
    run herdr_unit_content
    assert_contains "${output}" "OOMPolicy=continue"
}

@test "unit keeps herdr's default socket, so acmd and 'herdr machine add' find it" {
    run herdr_unit_content
    assert_not_contains "${output}" "sock"
    assert_not_contains "${output}" "XDG_CONFIG_HOME"
}

# =============================================================================
# Service setup
# =============================================================================

@test "setup writes the unit, reloads, then enables and starts it" {
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    [ -f "${UNIT_FILE}" ]
    run herdr_unit_content
    cmp -s - "${UNIT_FILE}" <<<"${output}"

    local reload enable
    reload="$(grep -n 'systemctl --user daemon-reload' "${STUB_LOG}" | head -1 | cut -d: -f1)"
    enable="$(grep -n 'systemctl --user enable --now herdr.service' "${STUB_LOG}" | head -1 | cut -d: -f1)"
    [ -n "${reload}" ]
    [ -n "${enable}" ]
    [ "${reload}" -lt "${enable}" ]
}

@test "setup rewrites the unit only on content drift" {
    setup_herdr_service
    : >"${STUB_LOG}"
    touch -d '2001-01-01' "${UNIT_FILE}"
    local before
    before="$(stat -c %Y "${UNIT_FILE}")"

    setup_herdr_service
    [ "$(stat -c %Y "${UNIT_FILE}")" -eq "${before}" ]
    run grep -c 'daemon-reload' "${STUB_LOG}"
    [ "${output}" -eq 0 ]

    printf '# hand edit\n' >>"${UNIT_FILE}"
    : >"${STUB_LOG}"
    setup_herdr_service
    run grep -c 'hand edit' "${UNIT_FILE}"
    [ "${output}" -eq 0 ]
    run grep -c 'daemon-reload' "${STUB_LOG}"
    [ "${output}" -eq 1 ]
}

@test "a changed unit under a running server is not restarted behind FX's back" {
    touch "${TEST_TEMP_DIR}/unit-active"
    mkdir -p "$(dirname "${UNIT_FILE}")"
    echo "[Service]" >"${UNIT_FILE}"
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    run grep -E 'restart|stop|kill' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "linger is enabled when it is off" {
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    grep -q 'loginctl enable-linger testuser' "${STUB_LOG}"
}

@test "linger is left alone when it is already on" {
    touch "${TEST_TEMP_DIR}/linger-on"
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    run grep 'enable-linger' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "without a user manager the unit is written but nothing is enabled" {
    touch "${TEST_TEMP_DIR}/no-user-manager"
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    [ -f "${UNIT_FILE}" ]
    assert_contains "${output}" "user manager"
    run grep -E 'enable|daemon-reload' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "without herdr in the profile nothing is enabled" {
    rm "${MOCK_HOME}/.nix-profile/bin/herdr"
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    assert_contains "${output}" ".nix-profile/bin/herdr"
    run grep -E 'enable' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

# =============================================================================
# A server already running outside the unit
# =============================================================================

@test "herdr_server_pids asks pgrep for this user's servers by full command line" {
    cat >"${STUB_DIR}/pgrep" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"${TEST_TEMP_DIR}/pgrep-args"
EOF
    herdr_server_pids
    [ "$(head -3 "${TEST_TEMP_DIR}/pgrep-args" | tr '\n' ' ')" = "-u $(id -u) -f " ]

    local pattern cmdline
    pattern="$(tail -1 "${TEST_TEMP_DIR}/pgrep-args")"
    for cmdline in "herdr server" "/usr/bin/herdr server" "/home/fx/.nix-profile/bin/herdr server"; do
        grep -Eq -- "${pattern}" <<<"${cmdline}"
    done
    for cmdline in "herdr" "herdr --session work" "/usr/bin/herdr-server" "vim herdr server" "bash -c herdr server"; do
        run ! grep -Eq -- "${pattern}" <<<"${cmdline}"
    done
}

@test "an outside server is left running without --restart-herdr, and the conflict is logged" {
    start_foreign_server
    run setup_herdr_service
    [ "${status}" -eq 0 ]
    foreign_alive
    assert_contains "${output}" "${FOREIGN_PID}"
    assert_contains "${output}" "--restart-herdr"
    # enabled for the next boot, but not started on top of the old server
    grep -q 'systemctl --user enable herdr.service' "${STUB_LOG}"
    run grep -- '--now' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "--restart-herdr warns that sessions end, stops the outside server, then starts the unit" {
    start_foreign_server
    mkdir -p "$(dirname "${SOCKET}")"
    touch "${SOCKET}"
    RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "ends its sessions"
    run ! foreign_alive
    # stale socket from the old server is gone, so the unit's server can bind
    [ ! -e "${SOCKET}" ]
    grep -q 'systemctl --user enable --now herdr.service' "${STUB_LOG}"
}

@test "any other RESTART_HERDR value does not stop the outside server" {
    start_foreign_server
    RESTART_HERDR=yes run setup_herdr_service
    [ "${status}" -eq 0 ]
    foreign_alive
}

@test "the server the unit itself runs is not treated as a conflict" {
    touch "${TEST_TEMP_DIR}/unit-active"
    start_foreign_server
    RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    foreign_alive
    assert_not_contains "${output}" "ends its sessions"
}

@test "no outside server means no warning and no signal" {
    RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    assert_not_contains "${output}" "ends its sessions"
}

@test "--restart-herdr escalates to SIGKILL when the server ignores SIGTERM" {
    bash -c 'trap "" TERM; while :; do sleep 1; done' &
    FOREIGN_PID=$!
    echo "${FOREIGN_PID}" >"${TEST_TEMP_DIR}/procs"
    RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "SIGKILL"
    run ! foreign_alive
    grep -q 'systemctl --user enable --now herdr.service' "${STUB_LOG}"
}

@test "--restart-herdr from inside a herdr pane refuses, and the bootstrap carries on" {
    start_foreign_server
    HERDR_ENV=1 RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    foreign_alive
    assert_contains "${output}" "refusing to stop"
    assert_contains "${output}" "outside herdr"
    assert_not_contains "${output}" "ends its sessions"
    # enabled for the next boot, but not started on top of the running server
    grep -q 'systemctl --user enable herdr.service' "${STUB_LOG}"
    run grep -- '--now' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "inside a pane of the unit's own server --restart-herdr has nothing to refuse" {
    touch "${TEST_TEMP_DIR}/unit-active"
    HERDR_ENV=1 RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -eq 0 ]
    assert_not_contains "${output}" "refusing"
}

@test "--restart-herdr fails without enabling the unit when the server cannot be stopped" {
    start_foreign_server
    stop_unmanaged_herdr() { return 1; }
    RESTART_HERDR=true run setup_herdr_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "Could not stop the herdr server"
    run grep -E 'enable' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "a failing 'enable --now' is reported and fails the setup" {
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
case "\$*" in
    "--user show-environment") exit 0 ;;
    "--user is-active --quiet herdr.service") exit 1 ;;
    *"enable --now"*) exit 1 ;;
    *) exit 0 ;;
esac
EOF
    run setup_herdr_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "journalctl --user -u herdr"
}

@test "a failing 'enable' behind an outside server is reported and fails the setup" {
    start_foreign_server
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
case "\$*" in
    "--user show-environment") exit 0 ;;
    "--user is-active --quiet herdr.service") exit 1 ;;
    "--user enable herdr.service") exit 1 ;;
    *) exit 0 ;;
esac
EOF
    run setup_herdr_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "enable herdr.service failed"
}

@test "a failing enable-linger is reported and fails the setup" {
    cat >"${STUB_DIR}/loginctl" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "show-user" ]]; then
    echo no
    exit 0
fi
exit 1
EOF
    run setup_herdr_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "enable-linger"
}

# =============================================================================
# Wiring into the bootstrap
# =============================================================================

@test "the bootstrap parses --restart-herdr and documents it in --help" {
    run grep -F -- '--restart-herdr)' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
    run grep -F -- '--restart-herdr   ' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
    run grep -E 'RESTART_HERDR="\$\{RESTART_HERDR:-false\}"' "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}

@test "main starts the herdr service once the dev profile and GITLAB_HOST exist" {
    # Panes inherit GITLAB_HOST from the server alone, and nothing restarts it.
    run bash -c "sed -n '/^main()/,\$p' '${BOOTSTRAP}' | grep -E '^ +(install_dev_profile|configure_gitlab_env|setup_herdr_service)( |\$)' | awk '{print \$1}' | tr '\n' ' '"
    [ "${output}" = "install_dev_profile configure_gitlab_env setup_herdr_service " ]
}

@test "a herdr failure does not stop the bootstrap reaching restart_ssh_final" {
    # A re-run would not reload sshd, so aborting here strands the SSH hardening.
    local call
    call="$(sed -n '/^main()/,$p' "${BOOTSTRAP}" | grep -E '^ +setup_herdr_service( |$)')"
    run bash -c "set -euo pipefail
log_warn() { echo \"WARN: \$1\"; }
setup_herdr_service() { return 1; }
${call}
echo reached-restart_ssh_final"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "reached-restart_ssh_final"
    assert_contains "${output}" "re-run"
}

@test "the herdr functions pass shellcheck" {
    command -v shellcheck &>/dev/null || skip "shellcheck not available"
    run shellcheck -s bash -S warning "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}
