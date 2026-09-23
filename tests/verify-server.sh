#!/usr/bin/env bash
# ABOUTME: Verification script for dev server provisioning
# ABOUTME: Run via SSH to validate all components are correctly installed
#
# Test Coverage:
#   1. User & Environment  - Correct user, home directory, groups, shell
#   2. SSH Hardening       - Config exists, root login disabled, password auth off
#   3. Firewall (UFW)      - Active, SSH allowed, Mosh ports open
#   4. Fail2Ban            - Installed, running, SSH jail active
#   5. Nix Installation    - Installed, daemon running, flakes enabled
#   6. Dev Environment     - Flake directory, flake.nix, flake.lock
#   7. Dev Shell & Claude  - dev() function, Claude Code available, tools
#   8. GitHub CLI          - Installed, authenticated
#   9. Git Configuration   - user.name, user.email set
#  10. Repository Clone    - bootstrap-dev-server repo cloned
#  11. CLAUDE.md           - Template file created
#  12. Herdr               - Available, and no stale MCP entries remain
#  13. Tailscale           - Authenticated, node key not expiring soon
#  14. Monitoring          - node_exporter active, tailnet-only bind, /metrics served
#
# Usage:
#   ssh dev-server 'bash -s' < tests/verify-server.sh
#   EXPECTED_USER=myuser ssh dev-server 'bash -s' < tests/verify-server.sh

set -euo pipefail

#===============================================================================
# Logging Setup
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/logging.sh"

# Source the logging library for colors (test functions kept separate per design)
if [[ -f "${LIB_PATH}" ]]; then
    # shellcheck disable=SC1091  # Path is dynamically checked
    # shellcheck source=../lib/logging.sh
    source "${LIB_PATH}"
else
    # Fallback colors if library not found
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Test counters (kept separate from logging library)
PASSED=0
FAILED=0
WARNINGS=0

# Get expected username (default: fx, can override with EXPECTED_USER env var)
EXPECTED_USER="${EXPECTED_USER:-fx}"

# Test result functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++)) || true
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNINGS++)) || true
}

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

# ============================================================================
# TEST SUITE
# ============================================================================

header "1. User & Environment Tests"

# Test 1.1: Current user matches expected
# shellcheck disable=SC2312  # whoami return value acceptable here
CURRENT_USER="$(whoami)"
if [[ "${CURRENT_USER}" == "${EXPECTED_USER}" ]]; then
    pass "Running as user '${EXPECTED_USER}'"
else
    fail "Not running as user '${EXPECTED_USER}' (current: ${CURRENT_USER})"
fi

# Test 1.2: Home directory exists
if [[ -d "${HOME}" && "${HOME}" == "/home/${EXPECTED_USER}" ]]; then
    pass "Home directory is /home/${EXPECTED_USER}"
else
    fail "Home directory incorrect: ${HOME} (expected: /home/${EXPECTED_USER})"
fi

# Test 1.3: User is in correct groups
if groups | grep -q "users"; then
    pass "User is in 'users' group"
else
    warn "User not in 'users' group"
fi

# Test 1.4: Shell is bash or zsh (or nix-provided version)
if [[ "${SHELL}" == *"bash"* || "${SHELL}" == *"zsh"* ]]; then
    pass "Shell is valid: ${SHELL}"
else
    warn "Shell may not be bash or zsh: ${SHELL}"
fi

header "2. SSH Hardening Tests"

# SSH hardening config location (created by bootstrap script)
SSH_HARDENING_FILE="/etc/ssh/sshd_config.d/99-hardening.conf"

# Test 2.1: SSH config exists
if [[ -f /etc/ssh/sshd_config ]]; then
    pass "SSH config exists"
else
    fail "SSH config not found"
fi

# Test 2.2: SSH hardening file exists
if [[ -f "${SSH_HARDENING_FILE}" ]]; then
    pass "SSH hardening config exists: ${SSH_HARDENING_FILE}"

    # Test 2.3: Root login disabled
    if grep -q "^PermitRootLogin no" "${SSH_HARDENING_FILE}" 2>/dev/null; then
        pass "Root login disabled"
    else
        warn "Root login may not be disabled (check ${SSH_HARDENING_FILE})"
    fi

    # Test 2.4: Password auth disabled
    if grep -q "^PasswordAuthentication no" "${SSH_HARDENING_FILE}" 2>/dev/null; then
        pass "Password authentication disabled"
    else
        warn "Password authentication may be enabled"
    fi
else
    warn "SSH hardening config not found: ${SSH_HARDENING_FILE}"
    info "Bootstrap may not have run SSH hardening phase"
fi

# Test 2.5: SSH service running
if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
    pass "SSH service is running"
else
    fail "SSH service is not running"
fi

header "3. Firewall (UFW) Tests"

# Test 3.1: UFW installed
if command -v ufw &>/dev/null; then
    pass "UFW is installed"

    # Test 3.2: UFW is active
    if sudo ufw status | grep -q "Status: active"; then
        pass "UFW is active"

        # Test 3.3: SSH port allowed
        if sudo ufw status | grep -q "22"; then
            pass "SSH port 22 is allowed"
        else
            fail "SSH port 22 not in UFW rules"
        fi

        # Test 3.4: Mosh ports allowed
        if sudo ufw status | grep -q "60000:60010"; then
            pass "Mosh ports 60000-60010 are allowed"
        else
            warn "Mosh ports may not be configured"
        fi

        # Test 3.5: Mosh server binary
        if command -v mosh-server &>/dev/null; then
            pass "mosh-server binary is installed"
        else
            fail "mosh-server not found on PATH"
        fi
    else
        fail "UFW is not active"
    fi
else
    fail "UFW is not installed"
fi

header "4. Fail2Ban Tests"

# Test 4.1: Fail2Ban installed
if command -v fail2ban-client &>/dev/null; then
    pass "Fail2Ban is installed"

    # Test 4.2: Fail2Ban service running
    if systemctl is-active --quiet fail2ban; then
        pass "Fail2Ban service is running"

        # Test 4.3: SSH jail enabled
        if sudo fail2ban-client status sshd &>/dev/null; then
            pass "Fail2Ban SSH jail is active"
        else
            warn "Fail2Ban SSH jail may not be configured"
        fi
    else
        fail "Fail2Ban service is not running"
    fi
else
    fail "Fail2Ban is not installed"
fi

header "5. Nix Installation Tests"

# Test 5.1: Nix installed
if command -v nix &>/dev/null; then
    pass "Nix is installed"
    NIX_VERSION=$(nix --version 2>/dev/null || echo "unknown")
    info "Nix version: ${NIX_VERSION}"

    # Test 5.2: Nix daemon running
    if systemctl is-active --quiet nix-daemon; then
        pass "Nix daemon is running"
    else
        warn "Nix daemon may not be running (could be single-user install)"
    fi

    # Test 5.3: Flakes enabled
    if nix flake --help &>/dev/null; then
        pass "Nix flakes are enabled"
    else
        fail "Nix flakes not available"
    fi

    # Test 5.4: Nix garbage collection timer enabled
    if systemctl is-enabled --quiet nix-gc.timer 2>/dev/null; then
        pass "Nix GC timer is enabled"
    else
        fail "Nix GC timer is not enabled (Nix store will grow unbounded)"
    fi
else
    # Source nix profile and retry
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck disable=SC1091  # System path, not our file
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        if command -v nix &>/dev/null; then
            pass "Nix is installed (after sourcing profile)"
        else
            fail "Nix is not installed"
        fi
    else
        fail "Nix is not installed"
    fi
fi

header "6. Dev Environment Flake Tests"

DEV_FLAKE_PATH="${HOME}/.config/nix-dev-env"

# Test 6.1: Flake directory exists
if [[ -d "${DEV_FLAKE_PATH}" ]]; then
    pass "Dev flake directory exists: ${DEV_FLAKE_PATH}"

    # Test 6.2: flake.nix exists
    if [[ -f "${DEV_FLAKE_PATH}/flake.nix" ]]; then
        pass "flake.nix exists"

        # Test 6.3: flake.lock exists (built at least once)
        if [[ -f "${DEV_FLAKE_PATH}/flake.lock" ]]; then
            pass "flake.lock exists (environment has been built)"
        else
            warn "flake.lock missing - environment may not be built"
        fi
    else
        fail "flake.nix not found"
    fi
else
    fail "Dev flake directory not found: ${DEV_FLAKE_PATH}"
fi

# Test 6.4: Can evaluate flake
if [[ -d "${DEV_FLAKE_PATH}" ]]; then
    if nix flake metadata "${DEV_FLAKE_PATH}" &>/dev/null; then
        pass "Flake metadata is valid"
    else
        fail "Flake metadata check failed"
    fi
fi

header "7. Dev Shell & Claude Code Tests"

# Test 7.1: dev function exists in bashrc
if grep -q "^dev()" "${HOME}/.bashrc" 2>/dev/null; then
    pass "dev() function defined in .bashrc"
else
    fail "dev() function not found in .bashrc"
fi

# Test 7.2: Test entering dev shell and checking claude
info "Testing dev shell (this may take a moment)..."
if nix develop "${DEV_FLAKE_PATH}" --command which claude &>/dev/null; then
    pass "Claude Code is available in dev shell"
    CLAUDE_VERSION=$(nix develop "${DEV_FLAKE_PATH}" --command claude --version 2>/dev/null | head -1 || echo "unknown")
    info "Claude Code version: ${CLAUDE_VERSION}"
else
    fail "Claude Code not available in dev shell"
fi

# Test 7.3: Check for other tools in dev shell
# Note: ripgrep binary is 'rg', fd-find binary is 'fd'
for tool in git gh jq fzf rg fd bat; do
    if nix develop "${DEV_FLAKE_PATH}" --command which "${tool}" &>/dev/null; then
        pass "${tool} available in dev shell"
    else
        warn "${tool} not found in dev shell"
    fi
done

header "8. GitHub CLI Tests"

# Test 8.1: gh installed (system or nix)
if command -v gh &>/dev/null; then
    pass "GitHub CLI (gh) is installed"
    GH_VERSION=$(gh --version | head -1)
    info "Version: ${GH_VERSION}"

    # Test 8.2: gh authenticated
    if gh auth status &>/dev/null; then
        pass "GitHub CLI is authenticated"
        GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
        info "Authenticated as: ${GH_USER}"
    else
        fail "GitHub CLI is not authenticated"
    fi
else
    fail "GitHub CLI (gh) is not installed"
fi

header "9. Git Configuration Tests"

# Test 9.1: Git installed
if command -v git &>/dev/null; then
    pass "Git is installed"

    # Test 9.2: Git user.name configured
    GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    if [[ -n "${GIT_NAME}" ]]; then
        pass "Git user.name configured: ${GIT_NAME}"
    else
        fail "Git user.name not configured"
    fi

    # Test 9.3: Git user.email configured
    GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    if [[ -n "${GIT_EMAIL}" ]]; then
        pass "Git user.email configured: ${GIT_EMAIL}"
    else
        fail "Git user.email not configured"
    fi
else
    fail "Git is not installed"
fi

header "10. Repository Clone Tests"

REPO_PATH="${HOME}/.local/share/bootstrap-dev-server"

# Test 10.1: Repository exists
if [[ -d "${REPO_PATH}" ]]; then
    pass "Repository cloned at ${REPO_PATH}"

    # Test 10.2: flake.nix exists (core file)
    if [[ -f "${REPO_PATH}/flake.nix" ]]; then
        pass "flake.nix present"
    else
        fail "flake.nix missing"
    fi

    # Test 10.3: Is a git repo
    if git -C "${REPO_PATH}" rev-parse --git-dir &>/dev/null; then
        pass "Directory is a valid git repository"
        BRANCH=$(git -C "${REPO_PATH}" branch --show-current 2>/dev/null || echo "unknown")
        info "Current branch: ${BRANCH}"
    else
        fail "Directory is not a git repository"
    fi
else
    fail "Repository not found at ${REPO_PATH}"
fi

header "11. CLAUDE.md Template Tests"

# Test 11.1: CLAUDE.md exists
if [[ -f "${HOME}/CLAUDE.md" ]]; then
    pass "CLAUDE.md template created"
    CLAUDE_MD_SIZE=$(wc -c <"${HOME}/CLAUDE.md")
    info "CLAUDE.md size: ${CLAUDE_MD_SIZE} bytes"
else
    warn "CLAUDE.md template not found"
fi

header "12. Herdr Tests"

# Test 12.1: herdr is on PATH inside the dev shell
if command -v herdr &>/dev/null; then
    pass "herdr is available"
    HERDR_VERSION="$(herdr --version 2>/dev/null || echo "unknown")"
    info "herdr version: ${HERDR_VERSION}"
else
    warn "herdr not found (only present inside the dev shell)"
fi

# Test 12.2: no stale MCP entries left behind in ~/.claude.json.
# Their /nix/store paths get garbage-collected, so Claude Code would fail to
# start those servers on every launch.
CLAUDE_JSON="${HOME}/.claude.json"
if [[ -f "${CLAUDE_JSON}" ]]; then
    if grep -q '"context7"\|"sequential-thinking"' "${CLAUDE_JSON}" 2>/dev/null; then
        fail "Stale MCP entries remain in ${CLAUDE_JSON} - re-enter the dev shell to prune them"
    else
        pass "No stale MCP entries in ~/.claude.json"
    fi
else
    info "No ~/.claude.json yet"
fi

header "13. Tailscale Tests"

if command -v tailscale &>/dev/null; then
    pass "Tailscale is installed"

    # Test 13.1: Backend is actually authenticated.
    # An expired node key leaves tailscaled active and enabled but the backend
    # in NeedsLogin, so `systemctl is-active` is not evidence of connectivity.
    TS_STATE="$(tailscale status --json 2>/dev/null | grep -o '"BackendState": *"[^"]*"' | cut -d'"' -f4 || echo "unknown")"
    case "${TS_STATE}" in
        Running)
            pass "Tailscale backend is Running"
            TS_IP="$(tailscale ip -4 2>/dev/null || echo "unknown")"
            info "Tailscale IP: ${TS_IP}"
            ;;
        NeedsLogin)
            fail "Tailscale is NOT authenticated (BackendState=NeedsLogin) - run: sudo tailscale up --advertise-tags=tag:server"
            ;;
        Stopped)
            fail "Tailscale is stopped (BackendState=Stopped) - run: sudo tailscale up"
            ;;
        *)
            warn "Tailscale backend state is '${TS_STATE}'"
            ;;
    esac

    # Test 13.2: Node key expiry.
    # A tagged node reports no expiry; an untagged one expires after 180 days
    # and drops off the tailnet silently.
    # Scope to Self: peers carry their own KeyExpiry values. jq is not on the
    # server outside the dev shell, and truncating on the "Peer" key works
    # whether the JSON is pretty-printed or compact.
    TS_STATUS_JSON="$(tailscale status --json 2>/dev/null || true)"
    TS_SELF_JSON="${TS_STATUS_JSON%%\"Peer\":*}"
    TS_EXPIRY="$(echo "${TS_SELF_JSON}" | grep -o '"KeyExpiry": *"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")"
    if [[ -z "${TS_EXPIRY}" || "${TS_EXPIRY}" == "null" ]]; then
        pass "Tailscale node key does not expire (tagged node or expiry disabled)"
    else
        EXPIRY_EPOCH="$(date -d "${TS_EXPIRY}" +%s 2>/dev/null || echo 0)"
        NOW_EPOCH="$(date +%s)"
        if [[ "${EXPIRY_EPOCH}" -eq 0 ]]; then
            info "Tailscale node key expires: ${TS_EXPIRY}"
        else
            SECONDS_LEFT=$((EXPIRY_EPOCH - NOW_EPOCH))
            DAYS_LEFT=$((SECONDS_LEFT / 86400))
            if [[ "${DAYS_LEFT}" -lt 0 ]]; then
                fail "Tailscale node key EXPIRED ${DAYS_LEFT#-} days ago (${TS_EXPIRY})"
            elif [[ "${DAYS_LEFT}" -lt 30 ]]; then
                warn "Tailscale node key expires in ${DAYS_LEFT} days (${TS_EXPIRY}) - re-auth with --advertise-tags or disable key expiry"
            else
                warn "Tailscale node key expires in ${DAYS_LEFT} days (${TS_EXPIRY}) - untagged node, will drop off the tailnet"
            fi
        fi
    fi
else
    warn "Tailscale is not installed"
fi

header "14. Monitoring (node_exporter) Tests"

NODE_EXPORTER_UNIT="/etc/systemd/system/node-exporter.service"

if [[ -f "${NODE_EXPORTER_UNIT}" ]]; then
    pass "node-exporter unit is installed"

    # Test 14.1: enabled and actually running.
    # A crash-looping unit reports 'activating' (auto-restart), which is
    # neither 'active' nor 'failed' - so `is-active` alone would miss it.
    if systemctl is-enabled --quiet node-exporter 2>/dev/null; then
        pass "node-exporter is enabled at boot"
    else
        fail "node-exporter is not enabled - it will not survive a reboot"
    fi

    NE_STATE="$(systemctl is-active node-exporter 2>/dev/null || true)"
    case "${NE_STATE}" in
        active)
            pass "node-exporter is running"
            ;;
        activating)
            fail "node-exporter is crash-looping (state=activating) - check: journalctl -u node-exporter"
            ;;
        *)
            fail "node-exporter is not running (state=${NE_STATE:-unknown}) - check: journalctl -u node-exporter"
            ;;
    esac

    # Test 14.2: /metrics is served on the Tailscale IP.
    # The body is captured first: piping curl into `grep -q` closes the pipe
    # on the first match, curl then fails with a write error, and under
    # pipefail a healthy exporter reads as broken (it also logs a
    # "connection reset by peer" for every check).
    NE_TS_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
    NE_METRICS=""
    if [[ -n "${NE_TS_IP}" ]]; then
        NE_METRICS="$(curl -fsS --max-time 5 "http://${NE_TS_IP}:9100/metrics" 2>/dev/null || true)"
    fi
    if [[ -z "${NE_TS_IP}" ]]; then
        fail "Cannot resolve the Tailscale IP - node_exporter has nothing safe to bind to"
    elif grep -q 'node_exporter_build_info' <<< "${NE_METRICS}"; then
        pass "node_exporter serves /metrics on ${NE_TS_IP}:9100"
    else
        fail "No node_exporter_build_info from http://${NE_TS_IP}:9100/metrics"
    fi

    # Test 14.3: nothing listens on 9100 publicly. node_exporter has no auth;
    # a 0.0.0.0 or [::] bind on a public Hetzner box exposes every metric.
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '^(0\.0\.0\.0|\*|\[::\]):9100$'; then
        fail "Port 9100 is bound on all interfaces (0.0.0.0:9100) - node_exporter must bind to the Tailscale IP only"
    else
        pass "Port 9100 is not bound on 0.0.0.0"
    fi

    # Test 14.4: firewall rule is scoped to tailscale0
    if sudo ufw status 2>/dev/null | grep -E '9100' | grep -q 'tailscale0'; then
        pass "UFW allows 9100 on tailscale0 only"
    else
        warn "No tailscale0-scoped UFW rule for 9100 - Prometheus on the NAS cannot scrape"
    fi
else
    warn "node_exporter is not installed"
fi

# ============================================================================
# SUMMARY
# ============================================================================

header "Test Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
echo ""
echo -e "  ${GREEN}Passed:${NC}   ${PASSED}"
echo -e "  ${RED}Failed:${NC}   ${FAILED}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARNINGS}"
echo -e "  Total:    ${TOTAL}"
echo ""

if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ All critical tests passed!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ❌ ${FAILED} test(s) failed - review output above${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    exit 1
fi
