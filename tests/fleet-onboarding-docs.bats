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

# Text of one section: the lines after its heading, up to the next "## " heading.
section() {
    awk -v h="$1" 'index($0, h) == 1 { inside = 1; next } /^## / && inside { exit } inside { print }' "${RUNBOOK}"
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
    # gitlab.test answers on HTTP only, and glab's protocols default to HTTPS
    grep -qF "glab auth login --hostname gitlab.test --api-protocol http --git-protocol http" "${RUNBOOK}"
}

@test "runbook points Git at glab by name, with no flag the server's glab lacks" {
    grep -qF "git config --global --replace-all credential.http://gitlab.test.helper '!glab auth git-credential'" "${RUNBOOK}"
    # The nixpkgs pin ships glab 1.114.0: the flag came later, so the login would stop at "unknown flag"
    run grep -F -- "--setup-git-credential-helper" "${RUNBOOK}"
    [ "${status}" -ne 0 ]
}

@test "runbook says the bootstrap does not install codex" {
    grep -qE '^\| Codex \|.*does not install' "${RUNBOOK}"
}

@test "runbook authenticates Tailscale after the bootstrap, before the logins" {
    local bootstrap tailscale logins
    bootstrap="$(line_of "bootstrap-dev-server.sh | ACM_NIX_ACCESS_TOKEN=")"
    tailscale="$(line_of "sudo tailscale up --advertise-tags=tag:server --accept-dns")"
    logins="$(line_of "## 2. Secrets and logins")"
    [ -n "${bootstrap}" ] && [ -n "${tailscale}" ]
    [ "${bootstrap}" -lt "${tailscale}" ]
    [ "${tailscale}" -lt "${logins}" ]
    # The bootstrap is what installs Tailscale, so the tailnet cannot be a prerequisite of it
    run grep -E '^Prerequisites:.*on the tailnet' "${RUNBOOK}"
    [ "${status}" -ne 0 ]
    grep -qF "the Tailscale login" "${RUNBOOK}"
}

@test "runbook runs the first bootstrap from its URL, and re-runs from the clone" {
    local first rerun
    first="$(line_of "bootstrap-dev-server.sh | ACM_NIX_ACCESS_TOKEN=")"
    rerun="$(line_of "cd ~/.local/share/bootstrap-dev-server")"
    [ -n "${first}" ] && [ -n "${rerun}" ]
    [ "${first}" -lt "${rerun}" ]
    # A new SSH session starts in $HOME: a relative script path needs the cd right before it
    run awk '/\.\/bootstrap-dev-server\.sh/ && prev != "cd ~/.local/share/bootstrap-dev-server" { bad = 1 }
             { prev = $0 }
             END { exit bad }' "${RUNBOOK}"
    [ "${status}" -eq 0 ]
}

@test "runbook names the verify script by its clone path" {
    grep -qF "~/.local/share/bootstrap-dev-server/tests/verify-server.sh" "${RUNBOOK}"
    run grep -E '(^|[^/])tests/verify-server\.sh' "${RUNBOOK}"
    [ "${status}" -ne 0 ]
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
    grep -qE '^ssh +=' "${RUNBOOK}"
    grep -qF "systemctl --user restart acmd" "${RUNBOOK}"
}

@test "runbook checks acm peers and the herdr machine" {
    grep -qF "acm peers" "${RUNBOOK}"
    grep -qF 'connected` with install `nix`' "${RUNBOOK}"
    grep -qF "SKIPPED (nix): managed by nix: bump the acm pin in nix-install" "${RUNBOOK}"
    grep -qF "herdr --machine dev-server workspace list" "${RUNBOOK}"
}

@test "runbook smoke test runs sdlc fix in a herdr pane" {
    local smoke
    smoke="$(section "## 5. Smoke test")"
    [[ "${smoke}" == *"sdlc fix <issue-number>"* ]]
    [[ "${smoke}" == *"herdr pane"* ]]
    [[ "${smoke}" == *"overlay"* ]]
}

@test "runbook smoke test lands in the pane ssh opens, never a nested herdr" {
    local smoke
    smoke="$(section "## 5. Smoke test")"
    # 01.2-002: an interactive ssh login attaches to herdr, and herdr refuses to nest
    [[ "${smoke}" == *"ssh dev-server"*"herdr pane"* ]]
    run grep -E '\(`herdr`[,)]' <<< "${smoke}"
    [ "${status}" -ne 0 ]
    [[ "${smoke}" == *"herdr --remote dev-server"* ]]
}

@test "runbook re-runs the bootstrap without asking to leave herdr first" {
    # Inside a pane the bootstrap refuses only --restart-herdr, which the re-run does not pass
    run grep -niE 'outside herdr' "${RUNBOOK}"
    [ "${status}" -ne 0 ]
    grep -qF "../README.md#logging-in-attaching-to-herdr" "${RUNBOOK}"
}

@test "runbook warns that the smoke test merges unattended" {
    [[ "$(section "## 5. Smoke test")" == *"unattended"*"merge"* ]]
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
    local links link target anchor heading
    links="$(grep -oE '\]\((\.\./[^)]+)\)' "${RUNBOOK}" | sed -E 's|^\]\(\.\./(.*)\)$|\1|')"
    [ -n "${links}" ] || { echo "runbook has no relative links"; return 1; }
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
    done <<< "${links}"
}

@test "runbook states the equal-herdr-version requirement" {
    grep -qi "herdr versions" "${RUNBOOK}"
}
