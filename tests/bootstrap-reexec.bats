#!/usr/bin/env bats
# ABOUTME: Tests for the self-update re-exec at the start of main()
# ABOUTME: Real git repos (local bare origin), stubbed target script, offline

load 'test_helper'

setup() {
    common_setup
    export NO_COLOR=1
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "${HOME}"
    export UPSTREAM="${TEST_TEMP_DIR}/upstream.git"
    export CLONE="${TEST_TEMP_DIR}/clone"
    export RECORD="${TEST_TEMP_DIR}/record"
    export SEED="${TEST_TEMP_DIR}/seed"

    git init -q --bare -b main "${UPSTREAM}"
    git init -q -b main "${SEED}"
    git -C "${SEED}" config user.email t@t.t
    git -C "${SEED}" config user.name t
    git -C "${SEED}" remote add origin "${UPSTREAM}"
    write_stub v1
    git -C "${SEED}" add -A && git -C "${SEED}" commit -qm v1
    git -C "${SEED}" push -q origin main

    # The "running script": the real function plus a call, as main() makes it
    {
        echo 'log_info() { echo "INFO: $*"; }'
        echo 'log_warn() { echo "WARN: $*"; }'
        echo "REPO_CLONE_DIR='${CLONE}'"
        echo 'BOOTSTRAP_SUBDIR="."'
        awk '/^reexec_from_updated_clone\(\) \{/,/^\}/' "${PROJECT_ROOT}/bootstrap-dev-server.sh"
        echo 'reexec_from_updated_clone "$@"'
        echo 'echo "CONTINUED"'
    } >"${TEST_TEMP_DIR}/running.sh"
}

teardown() {
    common_teardown
}

# Stub target: records args and env, then stops
write_stub() {
    cat >"${SEED}/bootstrap-dev-server.sh" <<EOF
#!/usr/bin/env bash
# ${1}
echo "ARGS=\$*" >"${RECORD}"
echo "GUARD=\${BOOTSTRAP_REEXECED:-}" >>"${RECORD}"
echo "TOKEN=\${ACM_NIX_ACCESS_TOKEN:-}" >>"${RECORD}"
echo "REEXECED"
EOF
}

publish_v2() {
    write_stub v2
    git -C "${SEED}" commit -qam v2
    git -C "${SEED}" push -q origin main
}

clone_it() { git clone -q "${UPSTREAM}" "${CLONE}"; }

@test "clone behind origin: pulls then execs the clone once with same args" {
    clone_it
    publish_v2
    export ACM_NIX_ACCESS_TOKEN=secret
    run bash "${TEST_TEMP_DIR}/running.sh" --yes --skip-github-auth
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Bootstrap updated ("*"); restarting from the clone"* ]]
    [[ "${output}" == *"REEXECED"* ]]
    [[ "${output}" != *"CONTINUED"* ]]
    grep -q 'ARGS=--yes --skip-github-auth' "${RECORD}"
    grep -q 'GUARD=1' "${RECORD}"
    grep -q 'v2' "${CLONE}/bootstrap-dev-server.sh"
}

@test "ACM_NIX_ACCESS_TOKEN reaches the re-exec'd script" {
    clone_it
    publish_v2
    export ACM_NIX_ACCESS_TOKEN=tok-123
    run bash "${TEST_TEMP_DIR}/running.sh"
    grep -q 'TOKEN=tok-123' "${RECORD}"
}

@test "up to date and identical to running script: no exec" {
    # Publish the running script itself as the clone's script
    cp "${TEST_TEMP_DIR}/running.sh" "${SEED}/bootstrap-dev-server.sh"
    git -C "${SEED}" commit -qam same
    git -C "${SEED}" push -q origin main
    clone_it
    cp "${CLONE}/bootstrap-dev-server.sh" "${TEST_TEMP_DIR}/running.sh"
    run bash "${CLONE}/bootstrap-dev-server.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"CONTINUED"* ]]
    [[ "${output}" != *"restarting"* ]]
}

@test "guard set: no pull and no exec" {
    clone_it
    publish_v2
    BOOTSTRAP_REEXECED=1 run bash "${TEST_TEMP_DIR}/running.sh"
    [[ "${output}" == *"CONTINUED"* ]]
    [ ! -f "${RECORD}" ]
    grep -q 'v1' "${CLONE}/bootstrap-dev-server.sh"
}

@test "failed pull: warns, no exec, run continues" {
    clone_it
    git -C "${CLONE}" remote set-url origin "${TEST_TEMP_DIR}/missing.git"
    run bash "${TEST_TEMP_DIR}/running.sh"
    [[ "${output}" == *"WARN: Could not pull"* ]]
    [[ "${output}" == *"CONTINUED"* ]]
    [ ! -f "${RECORD}" ]
}

@test "no clone: no pull and no exec" {
    run bash "${TEST_TEMP_DIR}/running.sh"
    [[ "${output}" == *"CONTINUED"* ]]
    [ ! -f "${RECORD}" ]
    [ ! -d "${CLONE}" ]
}

@test "piped script (no file): execs the clone's copy under the guard" {
    clone_it
    run bash -c "bash -s < '${TEST_TEMP_DIR}/running.sh'"
    [[ "${output}" == *"REEXECED"* ]]
    grep -q 'GUARD=1' "${RECORD}"
}

@test "pulled clone lacks the script: no exec, run continues" {
    clone_it
    git -C "${SEED}" rm -q bootstrap-dev-server.sh
    echo keep >"${SEED}/keep.txt"
    git -C "${SEED}" add keep.txt
    git -C "${SEED}" commit -qm "drop script"
    git -C "${SEED}" push -q origin main
    run bash "${TEST_TEMP_DIR}/running.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"CONTINUED"* ]]
    [ ! -f "${RECORD}" ]
}

@test "running from the clone itself: a pull that moves HEAD still re-execs" {
    # The documented re-run: ./bootstrap-dev-server.sh from inside the clone.
    # After the pull, running and clone script are the same (new) file, so a
    # content compare alone would wrongly skip the re-exec.
    cp "${TEST_TEMP_DIR}/running.sh" "${SEED}/bootstrap-dev-server.sh"
    git -C "${SEED}" commit -qam same
    git -C "${SEED}" push -q origin main
    clone_it
    publish_v2
    run bash "${CLONE}/bootstrap-dev-server.sh" --yes
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"REEXECED"* ]]
    [[ "${output}" != *"CONTINUED"* ]]
    grep -q 'ARGS=--yes' "${RECORD}"
}
