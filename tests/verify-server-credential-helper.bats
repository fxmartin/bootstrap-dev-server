#!/usr/bin/env bats
# ABOUTME: Tests the verify-server.sh check that no Git credential helper pins a /nix/store path
# ABOUTME: Offline, temp HOME with a real `git config --global`

load 'test_helper'

setup() {
    common_setup
    export HOME="${TEST_TEMP_DIR}/home"
    export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
    mkdir -p "${HOME}"
    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; }
    # shellcheck disable=SC1090
    source <(sed -n '/^check_credential_helpers() {/,/^}$/p' "${PROJECT_ROOT}/tests/verify-server.sh")
}

teardown() {
    common_teardown
}

@test "store-path helper fails, naming the key and the fix" {
    git config --global --add credential.https://github.com.helper ''
    git config --global --add credential.https://github.com.helper '!/nix/store/abc-gh-2.86.0/bin/gh auth git-credential'
    run check_credential_helpers
    [[ "${output}" == *FAIL* ]]
    [[ "${output}" == *"credential.https://github.com.helper"* ]]
    [[ "${output}" == *"re-run the bootstrap"* ]]
}

@test "named helper passes" {
    git config --global --add credential.https://github.com.helper ''
    git config --global --add credential.https://github.com.helper '!gh auth git-credential'
    run check_credential_helpers
    [[ "${output}" == *PASS* ]]
    [[ "${output}" != *FAIL* ]]
}

@test "missing gitconfig passes" {
    run check_credential_helpers
    [[ "${output}" == *PASS* ]]
    [[ "${output}" != *FAIL* ]]
}

@test "a store-path helper on another host also fails" {
    git config --global credential.http://gitlab.test.helper '!/nix/store/x-glab/bin/glab auth git-credential'
    run check_credential_helpers
    [[ "${output}" == *FAIL* ]]
    [[ "${output}" == *"credential.http://gitlab.test.helper"* ]]
}
