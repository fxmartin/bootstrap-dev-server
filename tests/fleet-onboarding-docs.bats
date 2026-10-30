#!/usr/bin/env bats
# ABOUTME: Tests that docs/fleet-onboarding.md lists the onboarding steps in order and the README links it
# ABOUTME: Static checks on the docs only; nothing is executed on a live system

load 'test_helper'

setup() {
    common_setup
    export RUNBOOK="${PROJECT_ROOT}/docs/fleet-onboarding.md"
    export README="${PROJECT_ROOT}/README.md"
}

teardown() {
    common_teardown
}

# Line number of the first line matching a fixed string, or empty.
line_of() {
    grep -nF -- "$1" "${RUNBOOK}" | head -n 1 | cut -d: -f1
}

@test "runbook exists" {
    [ -f "${RUNBOOK}" ]
}

@test "runbook lists the five sections in order" {
    local prev=0 heading n
    for heading in "## 1. Bootstrap" "## 2. Secrets and logins" "## 3. Aggregator peer" "## 4. Checks" "## 5. Smoke test"; do
        n="$(line_of "${heading}")"
        [ -n "${n}" ] || { echo "missing heading: ${heading}"; return 1; }
        [ "${n}" -gt "${prev}" ] || { echo "out of order: ${heading}"; return 1; }
        prev="${n}"
    done
}

@test "runbook names every manual secret and login" {
    local item
    for item in "claude" "gh auth login" "glab auth login" "codex login" "ACM_NIX_ACCESS_TOKEN"; do
        [ -n "$(line_of "${item}")" ] || { echo "missing: ${item}"; return 1; }
    done
    grep -qF "GITLAB_HOST=gitlab.test glab auth login" "${RUNBOOK}"
}

@test "runbook lists the logins in the specified order" {
    local prev=0 item n
    for item in "| Claude Code |" "| GitHub |" "| GitLab |" "| Codex |" "| acm read token |"; do
        n="$(line_of "${item}")"
        [ -n "${n}" ] || { echo "missing: ${item}"; return 1; }
        [ "${n}" -gt "${prev}" ] || { echo "out of order: ${item}"; return 1; }
        prev="${n}"
    done
}

@test "runbook gives the peers entry and its restart" {
    grep -qF "[[peers]]" "${RUNBOOK}"
    grep -qF 'label = "dev-server"' "${RUNBOOK}"
    grep -qF "systemctl --user restart acmd" "${RUNBOOK}"
}

@test "runbook checks acm peers and the herdr machine" {
    grep -qF "acm peers" "${RUNBOOK}"
    grep -q "connected" "${RUNBOOK}"
    grep -qF "herdr --machine dev-server workspace list" "${RUNBOOK}"
}

@test "runbook smoke test runs sdlc fix in a herdr pane" {
    grep -qF "sdlc fix" "${RUNBOOK}"
    grep -qi "overlay" "${RUNBOOK}"
}

@test "runbook attaches with --remote, never a --machine with no command" {
    grep -qF "herdr --remote dev-server" "${RUNBOOK}"
    # --machine only runs an API command on a saved machine: bare, herdr exits with a usage error
    run grep -E 'herdr --machine [^ `]+(`|$)' "${RUNBOOK}"
    [ "${status}" -ne 0 ]
}

@test "runbook never contains a token-looking value" {
    run grep -E "(ghp_|github_pat_|glpat-)[A-Za-z0-9_]{8,}" "${RUNBOOK}"
    [ "${status}" -ne 0 ]
}

@test "README links the runbook from install, herdr, acmd and sdlc sections" {
    local section
    for section in "### One Command Provisioning" "### Herdr" "### acmd (agentic-coding-monitor)" "### sdlc and GitLab"; do
        run awk -v h="${section}" '
            index($0, h) == 1 { inside = 1; next }
            /^##+ / && inside { exit }
            inside && /docs\/fleet-onboarding\.md/ { found = 1 }
            END { exit found ? 0 : 1 }' "${README}"
        [ "${status}" -eq 0 ] || { echo "no runbook link under: ${section}"; return 1; }
    done
}

@test "runbook relative links point at existing files and README anchors" {
    local link target anchor heading
    while IFS= read -r link; do
        target="${link%%#*}"
        anchor=""
        [[ "${link}" == *"#"* ]] && anchor="${link#*#}"
        [ -f "${PROJECT_ROOT}/${target}" ] || { echo "broken file link: ${link}"; return 1; }
        if [ -n "${anchor}" ]; then
            # GitHub slug: lowercase, drop punctuation except hyphens, spaces to hyphens
            heading="$(grep -E '^#+ ' "${PROJECT_ROOT}/${target}" \
                | sed -E 's/^#+ //' | tr '[:upper:]' '[:lower:]' \
                | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g' | grep -Fx -- "${anchor}" || true)"
            [ -n "${heading}" ] || { echo "broken anchor: ${link}"; return 1; }
        fi
    done < <(grep -oE '\]\((\.\./[^)]+)\)' "${RUNBOOK}" | sed -E 's|^\]\(\.\./(.*)\)$|\1|')
}

@test "runbook states the equal-herdr-version requirement" {
    grep -qi "herdr versions" "${RUNBOOK}"
}
