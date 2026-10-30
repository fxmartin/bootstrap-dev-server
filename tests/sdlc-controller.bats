#!/usr/bin/env bats
# ABOUTME: Tests for the sdlc controller install, glab in the env, and the GITLAB_HOST export
# ABOUTME: Runs the installer offline against a stub uv, root-safe (no permission-based faults)

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export INSTALLER="${PROJECT_ROOT}/scripts/install-sdlc-controller.sh"
    export VERSIONS="${PROJECT_ROOT}/config/versions.env"
    export VERIFY="${PROJECT_ROOT}/tests/verify-server.sh"

    # uv is the seam: it records its argv and nothing is downloaded or installed.
    # `uv tool install` also drops an `sdlc` stub on PATH, as the real one would.
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    export UV_LOG="${TEST_TEMP_DIR}/uv.log"
    mkdir -p "${STUB_DIR}"
    : >"${UV_LOG}"
    cat >"${STUB_DIR}/uv" <<EOF2
#!/usr/bin/env bash
echo "uv \$*" >>"${UV_LOG}"
if [[ "\${1:-}" == "tool" && "\${2:-}" == "install" ]]; then
    mkdir -p "${MOCK_HOME}/.local/bin"
    printf '#!/usr/bin/env bash\necho 0.0.0\n' >"${MOCK_HOME}/.local/bin/sdlc"
    chmod +x "${MOCK_HOME}/.local/bin/sdlc"
fi
exit "\${UV_STUB_EXIT:-0}"
EOF2
    cat >"${STUB_DIR}/sudo" <<'EOF2'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
EOF2
    chmod +x "${STUB_DIR}/uv" "${STUB_DIR}/sudo"
    export PATH="${STUB_DIR}:${PATH}"

    export SDLC_STATE_FILE="${TEST_TEMP_DIR}/state/sdlc-controller.tag"
}

teardown() {
    common_teardown
}

load_bootstrap_function() {
    local fn="$1"
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    # shellcheck disable=SC1090
    source <(sed -n "/^${fn}()/,/^}\$/p" "${BOOTSTRAP}")
}

# =============================================================================
# glab in the environment
# =============================================================================

@test "dev-env package list includes glab" {
    run grep -E '^\s+pkgs\.glab\b' "${PROJECT_ROOT}/flake.nix"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Pinned tag
# =============================================================================

@test "config/versions.env pins the controller to a release tag" {
    run grep -E '^SDLC_CONTROLLER_TAG=v[0-9]+\.[0-9]+\.[0-9]+$' "${VERSIONS}"
    [ "$status" -eq 0 ]
}

@test "the tag is pinned only in versions.env, never in a script" {
    tag="$(. "${VERSIONS}"; echo "${SDLC_CONTROLLER_TAG}")"
    run grep -F "${tag}" "${INSTALLER}"
    [ "$status" -ne 0 ]
    run grep -En 'claude-code-config@v[0-9]' "${BOOTSTRAP}"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Install command
# =============================================================================

@test "installer runs uv tool install from the pinned tag and subdirectory" {
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC1090
    tag="$(. "${VERSIONS}"; echo "${SDLC_CONTROLLER_TAG}")"
    grep -qF "git+https://github.com/fxmartin/claude-code-config@${tag}#subdirectory=controller" "${UV_LOG}"
    grep -q '^uv tool install ' "${UV_LOG}"
}

@test "installer uses a uv-managed interpreter, never a system or nix one" {
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    grep -q '^uv python install 3\.12$' "${UV_LOG}"
    grep -q '^uv tool install .*--python-preference only-managed' "${UV_LOG}"
    grep -q '^uv tool install .*--python 3\.12' "${UV_LOG}"
}

@test "re-running with the same tag changes nothing" {
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    : >"${UV_LOG}"
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    [ ! -s "${UV_LOG}" ]
}

@test "a new tag upgrades the installed controller" {
    cp "${VERSIONS}" "${TEST_TEMP_DIR}/versions.env"
    export SDLC_VERSIONS_FILE="${TEST_TEMP_DIR}/versions.env"
    sed -i 's/^SDLC_CONTROLLER_TAG=.*/SDLC_CONTROLLER_TAG=v1.0.0/' "${SDLC_VERSIONS_FILE}"
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    sed -i 's/^SDLC_CONTROLLER_TAG=.*/SDLC_CONTROLLER_TAG=v1.1.0/' "${SDLC_VERSIONS_FILE}"
    : >"${UV_LOG}"
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    grep -qF '@v1.1.0#subdirectory=controller' "${UV_LOG}"
    grep -q -- '--force' "${UV_LOG}"
    [ "$(cat "${SDLC_STATE_FILE}")" = "v1.1.0" ]
}

@test "a failed uv install leaves no state, so the next run retries" {
    UV_STUB_EXIT=1 run bash "${INSTALLER}"
    [ "$status" -ne 0 ]
    [ ! -f "${SDLC_STATE_FILE}" ]
}

@test "installer rejects a tag that is not a plain release tag" {
    cp "${VERSIONS}" "${TEST_TEMP_DIR}/versions.env"
    export SDLC_VERSIONS_FILE="${TEST_TEMP_DIR}/versions.env"
    sed -i 's|^SDLC_CONTROLLER_TAG=.*|SDLC_CONTROLLER_TAG=main;rm|' "${SDLC_VERSIONS_FILE}"
    run bash "${INSTALLER}"
    [ "$status" -ne 0 ]
    [ ! -s "${UV_LOG}" ]
}

@test "installer fails clearly when uv is missing" {
    # A PATH holding only the basics, so a real uv on the host cannot leak in
    local bare="${TEST_TEMP_DIR}/bare"
    mkdir -p "${bare}"
    for tool in bash dirname date cat mkdir basename tput; do
        ln -s "$(command -v "${tool}")" "${bare}/${tool}"
    done
    run env PATH="${bare}" HOME="${MOCK_HOME}" bash "${INSTALLER}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"uv not found"* ]]
}

@test "bootstrap runs the sdlc installer after the profile steps" {
    run bash -c "sed -n '/^main()/,\$p' '${BOOTSTRAP}' | grep -E '^ +(install_dev_profile|configure_profile_path|configure_gitlab_env|install_sdlc_controller|setup_dev_env)\$' | tr -d ' ' | tr '\n' ' '"
    [ "$output" = "install_dev_profile configure_profile_path configure_gitlab_env install_sdlc_controller setup_dev_env " ]
}

# =============================================================================
# GITLAB_HOST export
# =============================================================================

@test "configure_gitlab_env exports GITLAB_HOST=gitlab.test in /etc/environment once" {
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    echo 'PATH="/usr/local/bin:/usr/bin:/bin"' >"${ENVIRONMENT_FILE}"
    GITLAB_HOST=gitlab.test
    load_bootstrap_function configure_gitlab_env
    run configure_gitlab_env
    [ "$status" -eq 0 ]
    run configure_gitlab_env
    [ "$status" -eq 0 ]
    [ "$(grep -cx 'GITLAB_HOST=gitlab.test' "${ENVIRONMENT_FILE}")" -eq 1 ]
    grep -qF "PATH=\"/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin\"" "${ENVIRONMENT_FILE}"
    [ "$(grep -cF "${HOME}/.local/bin" "${ENVIRONMENT_FILE}")" -eq 1 ]
}

@test "configure_gitlab_env replaces a stale GITLAB_HOST instead of duplicating it" {
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    printf 'PATH="/usr/bin"\nGITLAB_HOST=home-lab:8080\n' >"${ENVIRONMENT_FILE}"
    GITLAB_HOST=gitlab.test
    load_bootstrap_function configure_gitlab_env
    run configure_gitlab_env
    [ "$status" -eq 0 ]
    [ "$(grep -c '^GITLAB_HOST=' "${ENVIRONMENT_FILE}")" -eq 1 ]
    grep -qx 'GITLAB_HOST=gitlab.test' "${ENVIRONMENT_FILE}"
}

@test "configure_gitlab_env exports GITLAB_HOST for login shells, once" {
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    : >"${ENVIRONMENT_FILE}"
    GITLAB_HOST=gitlab.test
    load_bootstrap_function configure_gitlab_env
    run configure_gitlab_env
    run configure_gitlab_env
    [ "$status" -eq 0 ]
    [ "$(grep -cF '>>> gitlab-env >>>' "${HOME}/.profile")" -eq 1 ]
    run bash -c "HOME='${HOME}' sh -c '. \"\$HOME/.profile\"; echo \"\$GITLAB_HOST\"'"
    [ "$output" = "gitlab.test" ]
}

@test "bootstrap defaults GITLAB_HOST to gitlab.test" {
    run grep -F 'GITLAB_HOST="${GITLAB_HOST:-gitlab.test}"' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

@test "tailscale guidance includes --accept-dns so gitlab.test resolves" {
    run grep -F 'tailscale up --advertise-tags=${TAILSCALE_TAGS} --accept-dns' "${BOOTSTRAP}"
    [ "$status" -eq 0 ]
}

# =============================================================================
# verify-server.sh
# =============================================================================

@test "verify-server.sh checks sdlc, glab, gitlab.test resolution and HTTP" {
    run grep -F 'sdlc --version' "${VERIFY}"
    [ "$status" -eq 0 ]
    run grep -F 'glab --version' "${VERIFY}"
    [ "$status" -eq 0 ]
    run grep -F 'getent hosts "${GITLAB_HOST_EXPECTED}"' "${VERIFY}"
    [ "$status" -eq 0 ]
    run grep -F 'http://${GITLAB_HOST_EXPECTED}' "${VERIFY}"
    [ "$status" -eq 0 ]
}

@test "verify-server.sh names the fix when gitlab.test is unreachable" {
    run grep -F 'accept-dns' "${VERIFY}"
    [ "$status" -eq 0 ]
    run grep -F 'ACL' "${VERIFY}"
    [ "$status" -eq 0 ]
}

# =============================================================================
# README
# =============================================================================

@test "README recommends 1-2 concurrent workers or --sequential and says why" {
    run grep -E '1.2 concurrent workers' "${PROJECT_ROOT}/README.md"
    [ "$status" -eq 0 ]
    run grep -F -- '--sequential' "${PROJECT_ROOT}/README.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Coverage gaps: installer edge cases and install_sdlc_controller
# =============================================================================

@test "installer rejects a malformed Python pin" {
    cp "${VERSIONS}" "${TEST_TEMP_DIR}/versions.env"
    export SDLC_VERSIONS_FILE="${TEST_TEMP_DIR}/versions.env"
    sed -i 's|^SDLC_CONTROLLER_PYTHON=.*|SDLC_CONTROLLER_PYTHON=/nix/store/python3|' "${SDLC_VERSIONS_FILE}"
    run bash "${INSTALLER}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SDLC_CONTROLLER_PYTHON"* ]]
    [ ! -s "${UV_LOG}" ]
}

@test "installer fails clearly when the versions file is missing" {
    export SDLC_VERSIONS_FILE="${TEST_TEMP_DIR}/absent.env"
    run bash "${INSTALLER}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    [ ! -s "${UV_LOG}" ]
}

@test "installer reinstalls when the tag is recorded but sdlc is gone" {
    run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    rm -f "${MOCK_HOME}/.local/bin/sdlc"
    : >"${UV_LOG}"
    # Drop any host-installed sdlc from PATH so only the removed stub counted
    local clean="" dir
    while IFS= read -r dir; do
        [[ -x "${dir}/sdlc" ]] || clean="${clean:+${clean}:}${dir}"
    done < <(tr ':' '\n' <<<"${PATH}")
    PATH="${clean}" run bash "${INSTALLER}"
    [ "$status" -eq 0 ]
    grep -q '^uv tool install ' "${UV_LOG}"
}

@test "configure_gitlab_env warns when /etc/environment has no quoted PATH" {
    export ENVIRONMENT_FILE="${TEST_TEMP_DIR}/environment"
    : >"${ENVIRONMENT_FILE}"
    GITLAB_HOST=gitlab.test
    load_bootstrap_function configure_gitlab_env
    run configure_gitlab_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"No quoted PATH"* ]]
    grep -qx 'GITLAB_HOST=gitlab.test' "${ENVIRONMENT_FILE}"
}

@test "install_sdlc_controller skips quietly when the installer is absent" {
    REPO_CLONE_DIR="${TEST_TEMP_DIR}/no-clone"
    BOOTSTRAP_SUBDIR="."
    load_bootstrap_function install_sdlc_controller
    run install_sdlc_controller
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping sdlc"* ]]
}

@test "install_sdlc_controller treats an installer failure as non-critical" {
    REPO_CLONE_DIR="${TEST_TEMP_DIR}/clone"
    BOOTSTRAP_SUBDIR="."
    GITLAB_HOST=gitlab.test
    mkdir -p "${REPO_CLONE_DIR}/scripts"
    printf '#!/usr/bin/env bash\nexit 1\n' >"${REPO_CLONE_DIR}/scripts/install-sdlc-controller.sh"
    load_bootstrap_function install_sdlc_controller
    run install_sdlc_controller
    [ "$status" -eq 0 ]
    [[ "$output" == *"non-critical"* ]]
}

@test "install_sdlc_controller runs the installer when present" {
    REPO_CLONE_DIR="${TEST_TEMP_DIR}/clone"
    BOOTSTRAP_SUBDIR="."
    GITLAB_HOST=gitlab.test
    mkdir -p "${REPO_CLONE_DIR}/scripts"
    printf '#!/usr/bin/env bash\ntouch "%s/ran"\n' "${TEST_TEMP_DIR}" >"${REPO_CLONE_DIR}/scripts/install-sdlc-controller.sh"
    load_bootstrap_function install_sdlc_controller
    run install_sdlc_controller
    [ "$status" -eq 0 ]
    [ -f "${TEST_TEMP_DIR}/ran" ]
}
