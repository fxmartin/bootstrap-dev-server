#!/usr/bin/env bats
# ABOUTME: Tests for the acmd user service, the acm flake input and the read token for it
# ABOUTME: Runs offline and root-safe against stubbed systemctl; no real systemd or nix is touched

load 'test_helper'

bats_require_minimum_version 1.5.0

# A made-up token: any appearance of it outside nix.conf is a leak.
TOKEN="ghp_FAKEacmReadOnlyTokenForTests0123456789"

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export FLAKE="${PROJECT_ROOT}/flake.nix"
    export LOCK="${PROJECT_ROOT}/flake.lock"
    export UNIT_FILE="${MOCK_HOME}/.config/systemd/user/acmd.service"
    export STATE_DIR="${MOCK_HOME}/.local/state/acm"
    export NIX_CONF="${MOCK_HOME}/.config/nix/nix.conf"
    unset XDG_CONFIG_HOME ACM_NIX_ACCESS_TOKEN ACM_TOKEN_MISSING

    # systemctl, loginctl and sudo are the seams: each records its argv, and state
    # files steer the answers.
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export STUB_LOG="${TEST_TEMP_DIR}/stub.log"
    mkdir -p "${STUB_DIR}"
    : >"${STUB_LOG}"
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >>"${STUB_LOG}"
case "\$*" in
    "--user show-environment") [[ ! -f "${TEST_TEMP_DIR}/no-user-manager" ]] ;;
    "--user is-active --quiet acmd.service") [[ -f "${TEST_TEMP_DIR}/unit-active" ]] ;;
    "--user show -p MainPID --value acmd.service") cat "${TEST_TEMP_DIR}/main-pid" 2>/dev/null || echo 0 ;;
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

    # The profile holds acmd, as it does once install_dev_profile has run.
    mkdir -p "${MOCK_HOME}/.nix-profile/bin"
    printf '#!/usr/bin/env bash\n' >"${MOCK_HOME}/.nix-profile/bin/acmd"
    chmod +x "${MOCK_HOME}/.nix-profile/bin/acmd"

    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    local fn
    for fn in acmd_unit_content acm_token_configured configure_acm_access_token \
        remove_acm_push_install acmd_running_stale ensure_linger setup_acmd_service; do
        # shellcheck disable=SC1090
        source <(sed -n "/^${fn}()/,/^}\$/p" "${BOOTSTRAP}")
    done
}

teardown() {
    common_teardown
}

mode_of() { stat -c %a "$1"; }

# Runs a copy of bash ($1) that waits in a builtin, so /proc/<pid>/exe stays that
# copy (`-c 'sleep N'` would exec sleep over it), and returns once the exec has
# happened: until then the link is still this shell. fd 3 is closed so bats cannot
# hang on the background process.
start_exe_copy() {
    "$1" -c 'read -r -t 60 _ <>"$1"' _ "${TEST_TEMP_DIR}/hold" 3>&- &
    EXE_COPY_PID=$!
    local i wanted
    wanted="$(readlink -f "$1")"
    for ((i = 0; i < 1000; i++)); do
        [[ "$(readlink -f "/proc/${EXE_COPY_PID}/exe" 2>/dev/null)" == "${wanted}" ]] && return 0
        sleep 0.01
    done
    return 1
}

# main as the script runs it, set -e included, with every step stubbed: only main is
# lifted out of the script, so each step lands in the not-found handler, which
# records it. $1 holds the definitions a test wants instead.
run_main_with_stubs() {
    run bash -c "set -euo pipefail
command_not_found_handle() { echo \"step: \$*\"; }
SERVER_PROFILE=dev SKIP_GITHUB_AUTH=false SKIP_SECURITY_HARDENING=false
ACM_TOKEN_MISSING=false BLUE= NC=
$(sed -n '/^main() {/,/^}$/p' "${BOOTSTRAP}")
${1:-}
main"
}

# =============================================================================
# Flake: the acm input, pinned, in the dev-env profile
# =============================================================================

@test "flake has an agentic-coding-monitor input on the GitHub mirror, following nixpkgs" {
    run bash -c "sed -n '/agentic-coding-monitor = {/,/};/p' '${FLAKE}'"
    assert_contains "${output}" 'url = "github:fxmartin/agentic-coding-monitor";'
    assert_contains "${output}" 'inputs.nixpkgs.follows = "nixpkgs";'
}

@test "flake.lock pins the acm input to a commit and a content hash" {
    run jq -r '.nodes["agentic-coding-monitor"].locked | "\(.type) \(.owner)/\(.repo)"' "${LOCK}"
    [ "${output}" = "github fxmartin/agentic-coding-monitor" ]
    run jq -r '.nodes["agentic-coding-monitor"].locked.rev' "${LOCK}"
    [[ "${output}" =~ ^[0-9a-f]{40}$ ]]
    run jq -r '.nodes["agentic-coding-monitor"].locked.narHash' "${LOCK}"
    [[ "${output}" == sha256-* ]]
    run jq -r '.nodes.root.inputs["agentic-coding-monitor"]' "${LOCK}"
    [ "${output}" = "agentic-coding-monitor" ]
}

@test "flake.lock makes acm follow the root nixpkgs, with no second nixpkgs locked" {
    run jq -c '.nodes["agentic-coding-monitor"].inputs.nixpkgs' "${LOCK}"
    [ "${output}" = '["nixpkgs"]' ]
}

@test "acm (acmd + acm) is in devPackages, so the dev-env profile carries it" {
    run bash -c "sed -n '/devPackages = \\[/,/^        \\];/p' '${FLAKE}'"
    assert_contains "${output}" 'agentic-coding-monitor.packages.${system}.acm'
    run grep -c 'agentic-coding-monitor.packages' "${FLAKE}"
    [ "${output}" -eq 1 ]
}

@test "outputs take the acm input as an argument" {
    run grep -E '^  outputs = \{ .*agentic-coding-monitor' "${FLAKE}"
    [ "${status}" -eq 0 ]
}

# =============================================================================
# Unit content
# =============================================================================

@test "unit runs the profile's acmd with Restart=on-failure, wanted by default.target" {
    run acmd_unit_content
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "ExecStart=%h/.nix-profile/bin/acmd"
    assert_contains "${output}" "Restart=on-failure"
    assert_contains "${output}" "RestartSec=2"
    assert_contains "${output}" "WantedBy=default.target"
}

@test "unit mirrors acm's homeManagerModules.acmd: description, ordering and stop timeout" {
    run acmd_unit_content
    assert_contains "${output}" "Description=agentic-coding-monitor daemon (acmd)"
    assert_contains "${output}" "After=graphical-session.target"
    assert_contains "${output}" "TimeoutStopSec=2"
}

@test "unit PATH starts at the profile and reaches sdlc in ~/.local/bin, nix and sbin" {
    run acmd_unit_content
    assert_contains "${output}" 'Environment="PATH=%h/.nix-profile/bin:%h/.local/bin:'
    assert_contains "${output}" ":/nix/var/nix/profiles/default/bin:"
    assert_contains "${output}" ":/usr/sbin:"
}

@test "unit sets no ACM_SDLC_BIN or socket override, so acmd looks sdlc and herdr up itself" {
    run acmd_unit_content
    assert_not_contains "${output}" "ACM_SDLC_BIN"
    assert_not_contains "${output}" "HERDR_SOCKET_PATH"
}

# =============================================================================
# Read token for the private input
# =============================================================================

@test "a token from ACM_NIX_ACCESS_TOKEN lands in nix.conf access-tokens with mode 0600" {
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" run configure_acm_access_token
    [ "${status}" -eq 0 ]
    grep -qxF "access-tokens = github.com=${TOKEN}" "${NIX_CONF}"
    [ "$(mode_of "${NIX_CONF}")" = "600" ]
}

@test "the token never appears in the output, so it stays out of the bootstrap log" {
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" run configure_acm_access_token
    assert_not_contains "${output}" "${TOKEN}"
}

@test "a token already in nix.conf is kept, and its mode is tightened to 0600" {
    mkdir -p "$(dirname "${NIX_CONF}")"
    echo "access-tokens = github.com=${TOKEN}" >"${NIX_CONF}"
    chmod 644 "${NIX_CONF}"
    run configure_acm_access_token
    [ "${status}" -eq 0 ]
    grep -qxF "access-tokens = github.com=${TOKEN}" "${NIX_CONF}"
    [ "$(mode_of "${NIX_CONF}")" = "600" ]
}

@test "a new token replaces the old github.com one and keeps other hosts and other settings" {
    mkdir -p "$(dirname "${NIX_CONF}")"
    printf '%s\n' "experimental-features = nix-command flakes" \
        "access-tokens = gitlab.com=glpat-other github.com=ghp_OLDTOKEN" >"${NIX_CONF}"
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" run configure_acm_access_token
    [ "${status}" -eq 0 ]
    run grep -c '^access-tokens' "${NIX_CONF}"
    [ "${output}" -eq 1 ]
    grep -qF "github.com=${TOKEN}" "${NIX_CONF}"
    grep -qF "gitlab.com=glpat-other" "${NIX_CONF}"
    run grep -F "ghp_OLDTOKEN" "${NIX_CONF}"
    [ "${status}" -ne 0 ]
    grep -qxF "experimental-features = nix-command flakes" "${NIX_CONF}"
}

@test "re-running with the same token leaves nix.conf byte-identical" {
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" configure_acm_access_token
    cp "${NIX_CONF}" "${TEST_TEMP_DIR}/before"
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" configure_acm_access_token
    cmp -s "${TEST_TEMP_DIR}/before" "${NIX_CONF}"
}

@test "nix.conf honours XDG_CONFIG_HOME" {
    export XDG_CONFIG_HOME="${TEST_TEMP_DIR}/xdg"
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" run configure_acm_access_token
    [ "${status}" -eq 0 ]
    grep -qF "github.com=${TOKEN}" "${XDG_CONFIG_HOME}/nix/nix.conf"
}

@test "a missing token fails the step with a message naming access-tokens and nix.conf" {
    run configure_acm_access_token
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "access-tokens"
    assert_contains "${output}" "nix.conf"
    assert_contains "${output}" "ACM_NIX_ACCESS_TOKEN"
}

@test "an access-tokens line without a github.com entry counts as missing" {
    mkdir -p "$(dirname "${NIX_CONF}")"
    echo "access-tokens = gitlab.com=glpat-other" >"${NIX_CONF}"
    run configure_acm_access_token
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "access-tokens"
}

# =============================================================================
# Service setup
# =============================================================================

@test "setup writes the unit, reloads, then enables and starts it" {
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    [ -f "${UNIT_FILE}" ]
    run acmd_unit_content
    cmp -s - "${UNIT_FILE}" <<<"${output}"

    local reload enable
    reload="$(grep -n 'systemctl --user daemon-reload' "${STUB_LOG}" | head -1 | cut -d: -f1)"
    enable="$(grep -n 'systemctl --user enable --now acmd.service' "${STUB_LOG}" | head -1 | cut -d: -f1)"
    [ -n "${reload}" ]
    [ -n "${enable}" ]
    [ "${reload}" -lt "${enable}" ]
}

@test "setup creates the state directory with mode 0700" {
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    [ -d "${STATE_DIR}" ]
    [ "$(mode_of "${STATE_DIR}")" = "700" ]
}

@test "setup tightens an existing state directory to 0700" {
    mkdir -p "${STATE_DIR}"
    chmod 755 "${STATE_DIR}"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    [ "$(mode_of "${STATE_DIR}")" = "700" ]
}

@test "setup rewrites the unit only on content drift" {
    setup_acmd_service
    : >"${STUB_LOG}"
    touch -d '2001-01-01' "${UNIT_FILE}"
    local before
    before="$(stat -c %Y "${UNIT_FILE}")"

    setup_acmd_service
    [ "$(stat -c %Y "${UNIT_FILE}")" -eq "${before}" ]
    run grep -c 'daemon-reload' "${STUB_LOG}"
    [ "${output}" -eq 0 ]

    printf '# hand edit\n' >>"${UNIT_FILE}"
    : >"${STUB_LOG}"
    setup_acmd_service
    run grep -c 'hand edit' "${UNIT_FILE}"
    [ "${output}" -eq 0 ]
    run grep -c 'daemon-reload' "${STUB_LOG}"
    [ "${output}" -eq 1 ]
}

@test "a drifted unit under a running acmd restarts it, so the new unit applies" {
    touch "${TEST_TEMP_DIR}/unit-active"
    mkdir -p "$(dirname "${UNIT_FILE}")"
    echo "[Service]" >"${UNIT_FILE}"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    grep -q 'systemctl --user restart acmd.service' "${STUB_LOG}"
}

@test "an unchanged unit under a running acmd on the profile's binary is not restarted" {
    setup_acmd_service
    touch "${TEST_TEMP_DIR}/unit-active"
    acmd_running_stale() { return 1; }
    : >"${STUB_LOG}"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    run grep -c 'restart' "${STUB_LOG}"
    [ "${output}" -eq 0 ]
}

@test "a running acmd on a stale binary (an old profile or a push install) is restarted" {
    setup_acmd_service
    touch "${TEST_TEMP_DIR}/unit-active"
    acmd_running_stale() { return 0; }
    : >"${STUB_LOG}"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    grep -q 'systemctl --user restart acmd.service' "${STUB_LOG}"
}

@test "acmd_running_stale compares the running binary with the profile's resolved acmd" {
    local real="${TEST_TEMP_DIR}/store/acm-1/bin/acmd" other="${TEST_TEMP_DIR}/store/acm-0/bin/acmd"
    mkdir -p "$(dirname "${real}")" "$(dirname "${other}")"
    # bash, not /bin/sleep: that is busybox on the job image, which refuses to run
    # under any other name. The image guarantees bash as a real ELF.
    cp "$(command -v bash)" "${real}"
    cp "$(command -v bash)" "${other}"
    ln -sf "${real}" "${MOCK_HOME}/.nix-profile/bin/acmd"
    mkfifo "${TEST_TEMP_DIR}/hold"

    start_exe_copy "${real}"
    local on_new="${EXE_COPY_PID}"
    start_exe_copy "${other}"
    local on_old="${EXE_COPY_PID}"

    echo "${on_new}" >"${TEST_TEMP_DIR}/main-pid"
    run acmd_running_stale
    local new_status="${status}"
    echo "${on_old}" >"${TEST_TEMP_DIR}/main-pid"
    run acmd_running_stale
    local old_status="${status}"
    kill -KILL "${on_new}" "${on_old}" 2>/dev/null || true
    [ "${new_status}" -ne 0 ]
    [ "${old_status}" -eq 0 ]
}

@test "linger is enabled when it is off: a herdr setup that failed early never reached it" {
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    grep -q 'loginctl enable-linger testuser' "${STUB_LOG}"
}

@test "linger is left alone when it is already on" {
    touch "${TEST_TEMP_DIR}/linger-on"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    run grep 'enable-linger' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "a failing enable-linger is reported naming acmd, and fails the setup" {
    cat >"${STUB_DIR}/loginctl" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "show-user" ]]; then
    echo no
    exit 0
fi
exit 1
EOF
    run setup_acmd_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "enable-linger"
    assert_contains "${output}" "acmd will not start at boot"
}

@test "without acmd in the profile nothing is written and nothing is enabled" {
    rm "${MOCK_HOME}/.nix-profile/bin/acmd"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    [ ! -e "${UNIT_FILE}" ]
    assert_contains "${output}" ".nix-profile/bin/acmd"
    assert_contains "${output}" "access-tokens"
    [ ! -s "${STUB_LOG}" ]
}

@test "without a user manager the unit is written but nothing is enabled" {
    touch "${TEST_TEMP_DIR}/no-user-manager"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    [ -f "${UNIT_FILE}" ]
    assert_contains "${output}" "user manager"
    run grep -E 'enable|daemon-reload' "${STUB_LOG}"
    [ "${status}" -ne 0 ]
}

@test "a failing 'enable --now' is reported and fails the setup" {
    cat >"${STUB_DIR}/systemctl" <<EOF
#!/usr/bin/env bash
case "\$*" in
    "--user show-environment") exit 0 ;;
    "--user is-active --quiet acmd.service") exit 1 ;;
    *"enable --now"*) exit 1 ;;
    *) exit 0 ;;
esac
EOF
    run setup_acmd_service
    [ "${status}" -ne 0 ]
    assert_contains "${output}" "journalctl --user -u acmd"
}

# =============================================================================
# A previous push install
# =============================================================================

@test "a push install's binaries are removed, with their .prev and .new copies" {
    mkdir -p "${MOCK_HOME}/.local/bin"
    local f
    for f in acmd acm acmd.prev acm.prev acmd.new acm.new; do
        echo x >"${MOCK_HOME}/.local/bin/${f}"
    done
    echo keep >"${MOCK_HOME}/.local/bin/sdlc"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    for f in acmd acm acmd.prev acm.prev acmd.new acm.new; do
        [ ! -e "${MOCK_HOME}/.local/bin/${f}" ]
    done
    [ -f "${MOCK_HOME}/.local/bin/sdlc" ]
}

@test "a push install's unit is replaced by the Nix-managed one" {
    mkdir -p "$(dirname "${UNIT_FILE}")" "${MOCK_HOME}/.local/bin"
    echo x >"${MOCK_HOME}/.local/bin/acmd"
    printf '[Service]\nExecStart=%%h/.local/bin/acmd\n' >"${UNIT_FILE}"
    run setup_acmd_service
    [ "${status}" -eq 0 ]
    run grep -F '.local/bin/acmd' "${UNIT_FILE}"
    [ "${status}" -ne 0 ]
    grep -qF 'ExecStart=%h/.nix-profile/bin/acmd' "${UNIT_FILE}"
}

@test "without acmd in the profile a push install, its unit and its daemon are left alone" {
    rm "${MOCK_HOME}/.nix-profile/bin/acmd"
    mkdir -p "$(dirname "${UNIT_FILE}")" "${MOCK_HOME}/.local/bin"
    local f
    for f in acmd acm acmd.prev acm.prev; do
        echo x >"${MOCK_HOME}/.local/bin/${f}"
    done
    printf '[Service]\nExecStart=%%h/.local/bin/acmd\n' >"${UNIT_FILE}"
    cp "${UNIT_FILE}" "${TEST_TEMP_DIR}/unit-before"

    run setup_acmd_service
    [ "${status}" -eq 0 ]
    for f in acmd acm acmd.prev acm.prev; do
        [ -f "${MOCK_HOME}/.local/bin/${f}" ]
    done
    cmp -s "${TEST_TEMP_DIR}/unit-before" "${UNIT_FILE}"
    [ ! -s "${STUB_LOG}" ]
}

@test "the removal is logged only when something was there" {
    log_info() { echo "INFO: $1"; }
    run remove_acm_push_install
    [ "${status}" -eq 0 ]
    assert_not_contains "${output}" "push install"
    mkdir -p "${MOCK_HOME}/.local/bin"
    echo x >"${MOCK_HOME}/.local/bin/acmd"
    run remove_acm_push_install
    assert_contains "${output}" "push install"
}

# =============================================================================
# No token value in any generated file
# =============================================================================

@test "no generated file carries the token: unit, state dir, stub log, bootstrap script" {
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" configure_acm_access_token
    ACM_NIX_ACCESS_TOKEN="${TOKEN}" setup_acmd_service
    local hits
    hits="$(grep -rlF "${TOKEN}" "${MOCK_HOME}" "${STUB_LOG}" "${BOOTSTRAP}" "${FLAKE}" "${LOCK}" || true)"
    # nix.conf is the one sanctioned home for it
    [ "${hits}" = "${NIX_CONF}" ]
}

@test "nothing in the repo ties a token to git: nix.conf is outside the clone" {
    run grep -rIlE 'ghp_[A-Za-z0-9]{20,}|github_pat_|glpat-[A-Za-z0-9]{10,}' \
        "${PROJECT_ROOT}/bootstrap-dev-server.sh" "${PROJECT_ROOT}/flake.nix" "${PROJECT_ROOT}/flake.lock" \
        "${PROJECT_ROOT}/lib" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config"
    [ "${status}" -ne 0 ]
}

# =============================================================================
# Wiring into the bootstrap
# =============================================================================

@test "main configures the token before the profile, and starts acmd after herdr's service" {
    run bash -c "sed -n '/^main()/,\$p' '${BOOTSTRAP}' | grep -E '^ +(configure_acm_access_token|install_dev_profile|setup_herdr_service|setup_acmd_service)( |\$)' | awk '{print \$1}' | tr '\n' ' '"
    [ "${output}" = "configure_acm_access_token install_dev_profile setup_herdr_service setup_acmd_service " ]
}

@test "a missing token does not stop the bootstrap, and the warning names the remedy" {
    local call
    call="$(sed -n '/^main()/,$p' "${BOOTSTRAP}" | grep -E '^ +configure_acm_access_token( |$)')"
    run bash -c "set -euo pipefail
log_warn() { echo \"WARN: \$1\"; }
configure_acm_access_token() { return 1; }
${call}
echo reached-next-step"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "reached-next-step"
    assert_contains "${output}" "access-tokens"
}

@test "a profile failure with the token missing is tolerated; any other profile failure still aborts" {
    local block
    block="$(sed -n '/^main()/,$p' "${BOOTSTRAP}" | sed -n '/^    install_dev_profile/,/^    }$/p')"
    [ -n "${block}" ]
    run bash -c "set -euo pipefail
log_warn() { echo \"WARN: \$1\"; }
install_dev_profile() { return 1; }
ACM_TOKEN_MISSING=true
${block}
echo reached-next-step"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "reached-next-step"

    run bash -c "set -euo pipefail
log_warn() { echo \"WARN: \$1\"; }
install_dev_profile() { return 1; }
ACM_TOKEN_MISSING=false
${block}
echo reached-next-step"
    [ "${status}" -ne 0 ]
    assert_not_contains "${output}" "reached-next-step"
}

@test "an acmd failure does not stop the bootstrap reaching restart_ssh_final" {
    local call
    call="$(sed -n '/^main()/,$p' "${BOOTSTRAP}" | grep -E '^ +setup_acmd_service( |$)')"
    run bash -c "set -euo pipefail
log_warn() { echo \"WARN: \$1\"; }
setup_acmd_service() { return 1; }
${call}
echo reached-restart_ssh_final"
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "reached-restart_ssh_final"
    assert_contains "${output}" "re-run"
}

@test "a missing token walks main through the monitoring phase to the final SSH reload" {
    run_main_with_stubs '
configure_acm_access_token() { ACM_TOKEN_MISSING=true; return 1; }
install_dev_profile() { return 1; }
warm_nix_cache() { return 1; }'
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "step: install_node_exporter"
    assert_contains "${output}" "step: restart_ssh_final"
    assert_contains "${output}" "step: print_summary"
    assert_contains "${output}" "Nix cache not warmed without the acm read token"
}

@test "with a token a failed cache build still aborts main, set -e reaching inside warm_nix_cache" {
    mkdir -p "${MOCK_HOME}/.config/nix-dev-env"
    run_main_with_stubs "$(sed -n '/^warm_nix_cache()/,/^}$/p' "${BOOTSTRAP}")
nix() { [[ \"\$1\" != build ]]; }"
    [ "${status}" -ne 0 ]
    assert_not_contains "${output}" "Nix environment built and cached"
    assert_not_contains "${output}" "step: restart_ssh_final"
}

@test "with a token main warms the cache and reaches the final SSH reload" {
    run_main_with_stubs
    [ "${status}" -eq 0 ]
    assert_contains "${output}" "step: warm_nix_cache"
    assert_contains "${output}" "step: restart_ssh_final"
    assert_not_contains "${output}" "Nix cache not warmed"
}

# =============================================================================
# Beyond the bootstrap: verification, e2e and the docs
# =============================================================================

@test "verify-server.sh checks acmd is on PATH and its user service is active" {
    local verify="${PROJECT_ROOT}/tests/verify-server.sh"
    grep -q 'command -v acmd' "${verify}"
    grep -q 'systemctl --user is-active --quiet acmd.service' "${verify}"
    grep -q 'acmd.service is not active.*access-tokens' "${verify}"
}

@test "the e2e runner forwards the token by name, so its value stays off the command line" {
    local runner="${PROJECT_ROOT}/tests/e2e/e2e-runner.sh"
    grep -qF '${ACM_NIX_ACCESS_TOKEN:+-e ACM_NIX_ACCESS_TOKEN}' "${runner}"
    grep -qF 'sudo --preserve-env=ACM_NIX_ACCESS_TOKEN -u fx ./bootstrap-dev-server.sh' "${runner}"
    run grep -F 'ACM_NIX_ACCESS_TOKEN=' "${runner}"
    [ "${status}" -ne 0 ]
}

@test "README says what else needs the token, and how to provision with it" {
    local readme="${PROJECT_ROOT}/README.md"
    grep -q 'the weekly timer.*fail without the token' "${readme}"
    grep -q 'hcloud-provision.sh.*does not forward the token' "${readme}"
    grep -qF 'ACM_NIX_ACCESS_TOKEN=<token> bash' "${readme}"
    grep -q 'just update-lock.*moves the `agentic-coding-monitor` pin' "${readme}"
}

@test "the acmd functions pass shellcheck" {
    command -v shellcheck &>/dev/null || skip "shellcheck not available"
    run shellcheck -s bash -S warning "${BOOTSTRAP}"
    [ "${status}" -eq 0 ]
}
