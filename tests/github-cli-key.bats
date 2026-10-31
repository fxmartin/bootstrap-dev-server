#!/usr/bin/env bats
# ABOUTME: Tests for refresh_github_cli_apt_source (rotated GitHub CLI apt key)
# ABOUTME: wget/sudo/dpkg are stubbed; no network and no root needed

load 'test_helper'

setup() {
    common_setup
    export NO_COLOR=1
    export BOOTSTRAP="${PROJECT_ROOT}/bootstrap-dev-server.sh"
    export GH_KEYRING_FILE="${TEST_TEMP_DIR}/keyrings/gh.gpg"
    export GH_SOURCE_LIST="${TEST_TEMP_DIR}/github-cli.list"
    export SUDO_LOG="${TEST_TEMP_DIR}/sudo.log"
    export WGET_FAIL=0
    : >"${SUDO_LOG}"
    log_info() { :; }
    log_ok() { :; }
    log_warn() { echo "WARN: $1"; }
    dpkg() { echo arm64; }
    wget() {
        [[ "${WGET_FAIL}" == 1 ]] && return 4
        printf 'NEWKEY' >"$2"
    }
    sudo() { echo "$*" >>"${SUDO_LOG}"; "$@"; }
    source <(sed -n '/^GH_KEYRING_FILE=/,/^GH_APT_SOURCE_REFRESHED=/p;/^refresh_github_cli_apt_source()/,/^}$/p' "${BOOTSTRAP}")
}

teardown() {
    common_teardown
}

@test "stale keyring is rewritten" {
    mkdir -p "$(dirname "${GH_KEYRING_FILE}")"
    printf 'OLDKEY' >"${GH_KEYRING_FILE}"
    run refresh_github_cli_apt_source
    [ "$status" -eq 0 ]
    [ "$(cat "${GH_KEYRING_FILE}")" = "NEWKEY" ]
    grep -q "^deb \[arch=arm64 signed-by=${GH_KEYRING_FILE}\]" "${GH_SOURCE_LIST}"
}

@test "current keyring is not written again" {
    mkdir -p "$(dirname "${GH_KEYRING_FILE}")"
    printf 'NEWKEY' >"${GH_KEYRING_FILE}"
    refresh_github_cli_apt_source
    count="$(grep -c "install .*${GH_KEYRING_FILE}" "${SUDO_LOG}" || true)"
    [ "${count}" -eq 0 ]
}

@test "failed download warns, returns 0 and leaves the keyring alone" {
    mkdir -p "$(dirname "${GH_KEYRING_FILE}")"
    printf 'OLDKEY' >"${GH_KEYRING_FILE}"
    WGET_FAIL=1
    run refresh_github_cli_apt_source
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Could not download"* ]]
    [ "$(cat "${GH_KEYRING_FILE}")" = "OLDKEY" ]
}

@test "refresh runs before install_base_packages (Phase 1 apt-get update)" {
    run bash -c "sed -n '/^main()/,\$p' '${BOOTSTRAP}' | grep -E '^ +(refresh_github_cli_apt_source|install_base_packages)( |\$)' | awk '{print \$1}' | tr '\n' ' '"
    [ "$output" = "refresh_github_cli_apt_source install_base_packages " ]
}
