#!/usr/bin/env bats
# ABOUTME: Tests that authenticate_github_cli names gh by path-free name as the Git credential helper
# ABOUTME: Offline, temp HOME with a real `git config --global`, stubbed gh; nothing real is touched

load 'test_helper'

setup() {
    common_setup
    export HOME="${TEST_TEMP_DIR}/home"
    export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
    export XDG_CONFIG_HOME="${HOME}/.config"
    mkdir -p "${HOME}"
    export STUB_DIR="${TEST_TEMP_DIR}/stubs"
    mkdir -p "${STUB_DIR}"
    export STORE_HELPER='!/nix/store/xf3rb2kmk19092b1pf50ag0fsj2f6hpa-gh-2.86.0/bin/gh auth git-credential'
    log_info() { :; }
    log_ok() { :; }
    log_error() { :; }
    # shellcheck disable=SC1090
    source <(sed -n '/^set_github_git_credential_helpers() {/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")
    # shellcheck disable=SC1090
    source <(sed -n '/^authenticate_github_cli() {/,/^}$/p' "${PROJECT_ROOT}/bootstrap-dev-server.sh")
}

teardown() {
    common_teardown
}

seed_store_helpers() {
    local url
    for url in https://github.com https://gist.github.com; do
        git config --global --add "credential.${url}.helper" ''
        git config --global --add "credential.${url}.helper" "${STORE_HELPER}"
    done
}

# gh stub: $GH_AUTHED=yes makes `auth status` succeed; `auth login` seeds the store-path helpers.
stub_gh() {
    cat >"${STUB_DIR}/gh" <<'EOF2'
#!/usr/bin/env bash
case "$1 $2" in
    "auth status") [[ "${GH_AUTHED}" == "yes" ]] ;;
    "auth login")
        [[ "${GH_LOGIN_FAILS:-no}" == "yes" ]] && exit 1
        for url in https://github.com https://gist.github.com; do
            git config --global --add "credential.${url}.helper" ''
            git config --global --add "credential.${url}.helper" "${STORE_HELPER}"
        done ;;
    "api user") echo tester ;;
esac
EOF2
    chmod +x "${STUB_DIR}/gh"
    export PATH="${STUB_DIR}:${PATH}"
}

assert_named_helpers() {
    local url
    for url in https://github.com https://gist.github.com; do
        run git config --global --get-all "credential.${url}.helper"
        [ "${status}" -eq 0 ]
        [ "${output}" = $'\n!gh auth git-credential' ]
    done
    ! grep -q '/nix/store/' "${GIT_CONFIG_GLOBAL}"
}

@test "already-authenticated path replaces the store-path helper with the named one" {
    stub_gh
    export GH_AUTHED=yes
    seed_store_helpers
    run authenticate_github_cli
    [ "${status}" -eq 0 ]
    assert_named_helpers
}

@test "fresh-login path replaces the store-path helper written by gh auth login" {
    stub_gh
    export GH_AUTHED=no
    run authenticate_github_cli
    [ "${status}" -eq 0 ]
    assert_named_helpers
}

@test "running twice leaves the gitconfig unchanged" {
    stub_gh
    export GH_AUTHED=yes
    seed_store_helpers
    authenticate_github_cli
    cp "${GIT_CONFIG_GLOBAL}" "${TEST_TEMP_DIR}/first"
    authenticate_github_cli
    diff "${TEST_TEMP_DIR}/first" "${GIT_CONFIG_GLOBAL}"
}

@test "an empty gitconfig gets the named helpers" {
    stub_gh
    export GH_AUTHED=yes
    run authenticate_github_cli
    [ "${status}" -eq 0 ]
    assert_named_helpers
}

@test "unrelated credential helpers are left alone" {
    stub_gh
    export GH_AUTHED=yes
    git config --global credential.http://gitlab.test.helper '!glab auth git-credential'
    seed_store_helpers
    authenticate_github_cli
    run git config --global --get credential.http://gitlab.test.helper
    [ "${output}" = '!glab auth git-credential' ]
}

@test "failed login returns non-zero and does not touch git config" {
    stub_gh
    export GH_AUTHED=no GH_LOGIN_FAILS=yes
    run authenticate_github_cli
    [ "${status}" -eq 1 ]
    [ ! -s "${GIT_CONFIG_GLOBAL}" ]
}
