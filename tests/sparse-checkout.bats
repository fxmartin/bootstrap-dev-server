#!/usr/bin/env bats
# ABOUTME: Tests for sparse-checkout convergence in the repo clone
# ABOUTME: Exercises the shipped function against real git repositories

load 'test_helper'

setup() {
    common_setup
    setup_mock_environment
    export NO_COLOR=1

    # Quiet logging stubs
    log_info() { :; }
    log_ok() { :; }
    log_warn() { :; }
    log_error() { :; }

    # Source the real function out of the shipped script
    eval "$(awk '/^converge_sparse_checkout\(\) \{/,/^\}/' \
        "${PROJECT_ROOT}/bootstrap-dev-server.sh")"

    export UPSTREAM="${TEST_TEMP_DIR}/upstream"
    export CLONE="${TEST_TEMP_DIR}/clone"

    git init -q --bare -b main "${UPSTREAM}"
    local seed="${TEST_TEMP_DIR}/seed"
    git init -q -b main "${seed}"
    (
        cd "${seed}"
        git config user.email t@t.t
        git config user.name t
        echo root > root.txt
        mkdir -p lib tests
        echo lib > lib/logging.sh
        echo test > tests/verify.sh
        git add -A
        git commit -qm "seed"
        git remote add origin "${UPSTREAM}"
        git push -q origin main
    )
}

teardown() {
    common_teardown
}

# Reproduce the shipped bug: a sparse clone scoped to "."
make_sparse_clone() {
    git clone -q --no-checkout --sparse "${UPSTREAM}" "${CLONE}"
    git -C "${CLONE}" sparse-checkout set "."
    git -C "${CLONE}" checkout -q
}

@test "sparse-checkout set . really does omit subdirectories" {
    # Guards the premise: if git ever changes this, the fix is moot.
    make_sparse_clone
    [ -f "${CLONE}/root.txt" ]
    [ ! -d "${CLONE}/lib" ]
    [ ! -d "${CLONE}/tests" ]
}

@test "converging a whole-repo checkout materialises every directory" {
    make_sparse_clone
    run converge_sparse_checkout "${CLONE}" "."
    [ "$status" -eq 0 ]
    [ -f "${CLONE}/root.txt" ]
    [ -f "${CLONE}/lib/logging.sh" ]
    [ -f "${CLONE}/tests/verify.sh" ]
}

@test "converging leaves git status clean" {
    make_sparse_clone
    converge_sparse_checkout "${CLONE}" "."
    run git -C "${CLONE}" status --porcelain
    [ -z "$output" ]
}

@test "converging is idempotent" {
    make_sparse_clone
    converge_sparse_checkout "${CLONE}" "."
    converge_sparse_checkout "${CLONE}" "."
    [ -f "${CLONE}/lib/logging.sh" ]
    run git -C "${CLONE}" status --porcelain
    [ -z "$output" ]
}

@test "converging a non-sparse clone is a no-op that does not fail" {
    git clone -q "${UPSTREAM}" "${CLONE}"
    run converge_sparse_checkout "${CLONE}" "."
    [ "$status" -eq 0 ]
    [ -f "${CLONE}/lib/logging.sh" ]
}

@test "a real subfolder scope still uses sparse checkout" {
    # The capability must survive; only the "." case changes.
    git clone -q --no-checkout --sparse "${UPSTREAM}" "${CLONE}"
    run converge_sparse_checkout "${CLONE}" "lib"
    [ "$status" -eq 0 ]
    [ -f "${CLONE}/lib/logging.sh" ]
    [ ! -d "${CLONE}/tests" ]
}

@test "converging tolerates a missing repo directory" {
    run converge_sparse_checkout "${TEST_TEMP_DIR}/nope" "."
    [ "$status" -ne 0 ]
}

# =============================================================================
# Wiring
# =============================================================================

@test "the clone path no longer hardcodes sparse-checkout set" {
    run grep -q 'git sparse-checkout set "\${BOOTSTRAP_SUBDIR}"' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
    [ "$status" -ne 0 ]
}

@test "existing clones are converged on re-run, not only fresh ones" {
    # The bug is already on disk on every server provisioned so far.
    run bash -c "grep -c 'converge_sparse_checkout' '${PROJECT_ROOT}/bootstrap-dev-server.sh'"
    [ "$output" -ge 3 ]
}
