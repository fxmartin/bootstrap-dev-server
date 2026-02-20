#!/usr/bin/env bash
# ABOUTME: System health check for Ubuntu dev server
# ABOUTME: Validates security, services, disk space, and dev environment
#
# Usage:
#   health-check          # Run from dev shell (alias)
#   bash scripts/health-check.sh   # Run directly
#
# Checks:
#   1. SSH Hardening - Config, root login, password auth
#   2. Firewall (UFW) - Status, SSH/Mosh ports
#   3. Fail2Ban - Service status, SSH jail
#   4. Services - Nix daemon, SSH service
#   5. Disk Space - /nix partition, home directory
#   6. Nix Store - Size, generation count
#   7. Dev Caches - uv, npm, pnpm cache sizes
#   8. Claude Code - Availability in PATH
#   9. MCP Servers - Configuration file exists
#  10. Dev Tools - gh, rg, fd, bat, fzf, lazygit

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Version
readonly HEALTH_CHECK_VERSION="1.0.0"

# Handle --version flag
if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
    echo "health-check ${HEALTH_CHECK_VERSION}"
    exit 0
fi

# Thresholds
GENERATION_WARNING_THRESHOLD=50
DISK_WARNING_GB=20
CACHE_WARNING_KB=1048576  # 1GB in KB

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# SSH hardening config location
SSH_HARDENING_FILE="/etc/ssh/sshd_config.d/99-hardening.conf"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_status() {
    local status="$1"
    local message="$2"
    case "${status}" in
        ok)     echo -e "${GREEN}✅${NC} ${message}" ;;
        warn)   echo -e "${YELLOW}⚠️${NC}  ${message}" ;;
        error)  echo -e "${RED}❌${NC} ${message}" ;;
        info)   echo -e "${BLUE}💾${NC} ${message}" ;;
    esac
}

# Get cache size in KB (returns 0 if directory doesn't exist)
get_cache_kb() {
    local path="${1}"
    if [[ -d "${path}" ]]; then
        du -sk "${path}" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Get human-readable cache size
get_cache_human() {
    local path="${1}"
    if [[ -d "${path}" ]]; then
        du -sh "${path}" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

# =============================================================================
# HEADER
# =============================================================================

echo ""
echo "=== System Health Check ==="
echo "Host: $(hostname)"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# =============================================================================
# CHECK 1: SSH Hardening
# =============================================================================

echo "Checking SSH hardening..."

# Check if SSH hardening config exists
if [[ -f "${SSH_HARDENING_FILE}" ]]; then
    print_status "ok" "SSH hardening config exists"

    # Check root login disabled
    if grep -q "^PermitRootLogin no" "${SSH_HARDENING_FILE}" 2>/dev/null; then
        print_status "ok" "Root login disabled"
    else
        print_status "warn" "Root login may not be disabled"
        echo "    → Check: grep PermitRootLogin ${SSH_HARDENING_FILE}"
    fi

    # Check password authentication disabled
    if grep -q "^PasswordAuthentication no" "${SSH_HARDENING_FILE}" 2>/dev/null; then
        print_status "ok" "Password authentication disabled"
    else
        print_status "warn" "Password authentication may be enabled"
        echo "    → Check: grep PasswordAuthentication ${SSH_HARDENING_FILE}"
    fi
else
    print_status "warn" "SSH hardening config not found: ${SSH_HARDENING_FILE}"
    echo "    → Bootstrap may not have completed SSH hardening phase"
fi

# =============================================================================
# CHECK 2: Firewall (UFW)
# =============================================================================

echo ""
echo "Checking firewall..."

if command -v ufw &>/dev/null; then
    # Check if UFW is active (requires sudo for status)
    if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        print_status "ok" "UFW is active"

        # Check SSH port
        if sudo ufw status | grep -q "22"; then
            print_status "ok" "SSH port 22 allowed"
        else
            print_status "warn" "SSH port 22 not found in UFW rules"
        fi

        # Check Mosh ports
        if sudo ufw status | grep -q "60000:60010"; then
            print_status "ok" "Mosh ports 60000-60010 allowed"
        else
            print_status "warn" "Mosh ports may not be configured"
            echo "    → Run: sudo ufw allow 60000:60010/udp"
        fi

        # Check mosh-server binary
        if command -v mosh-server &>/dev/null; then
            print_status "ok" "mosh-server binary available"
        else
            print_status "warn" "mosh-server not installed"
            echo "    → Run: sudo apt-get install mosh"
        fi
    else
        print_status "error" "UFW is not active"
        echo "    → Run: sudo ufw enable"
    fi
else
    print_status "error" "UFW is not installed"
    echo "    → Run: sudo apt install ufw"
fi

# =============================================================================
# CHECK 3: Fail2Ban
# =============================================================================

echo ""
echo "Checking Fail2Ban..."

if command -v fail2ban-client &>/dev/null; then
    print_status "ok" "Fail2Ban is installed"

    # Check if service is running
    if systemctl is-active --quiet fail2ban; then
        print_status "ok" "Fail2Ban service is running"

        # Check SSH jail
        if sudo fail2ban-client status sshd &>/dev/null; then
            print_status "ok" "Fail2Ban SSH jail is active"
            # Get ban count
            BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
            if [[ -n "${BANNED}" && "${BANNED}" != "0" ]]; then
                print_status "info" "Currently banned IPs: ${BANNED}"
            fi
        else
            print_status "warn" "Fail2Ban SSH jail may not be configured"
        fi
    else
        print_status "error" "Fail2Ban service is not running"
        echo "    → Run: sudo systemctl start fail2ban"
    fi
else
    print_status "error" "Fail2Ban is not installed"
    echo "    → Run: sudo apt install fail2ban"
fi

# =============================================================================
# CHECK 4: Services
# =============================================================================

echo ""
echo "Checking services..."

# Nix daemon
if systemctl is-active --quiet nix-daemon; then
    print_status "ok" "Nix daemon running"
else
    print_status "error" "Nix daemon not running"
    echo "    → Run: sudo systemctl start nix-daemon"
fi

# SSH service (could be sshd or ssh depending on distro)
if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    print_status "ok" "SSH service running"
else
    print_status "error" "SSH service not running"
fi

# =============================================================================
# CHECK 5: Disk Space
# =============================================================================

echo ""
echo "Checking disk space..."

# Check /nix partition
if [[ -d /nix ]]; then
    DISK_FREE_KB=$(df -k /nix | tail -1 | awk '{print $4}')
    DISK_FREE_GB=$((DISK_FREE_KB / 1024 / 1024))
    DISK_FREE_HUMAN=$(df -h /nix | tail -1 | awk '{print $4}')

    if [[ ${DISK_FREE_GB} -lt ${DISK_WARNING_GB} ]]; then
        print_status "warn" "Disk free on /nix: ${DISK_FREE_HUMAN} (low space!)"
        echo "    → Run: nix-collect-garbage -d"
    else
        print_status "info" "Disk free on /nix: ${DISK_FREE_HUMAN}"
    fi
else
    print_status "error" "/nix directory not found"
fi

# Home directory space
HOME_FREE=$(df -h ~ | tail -1 | awk '{print $4}')
print_status "info" "Disk free on ~: ${HOME_FREE}"

# =============================================================================
# CHECK 6: Nix Store
# =============================================================================

echo ""
echo "Checking Nix store..."

# Store size
if [[ -d /nix/store ]]; then
    STORE_SIZE=$(du -sh /nix/store 2>/dev/null | cut -f1)
    print_status "info" "Nix store size: ${STORE_SIZE}"
fi

# Generation count (user profiles)
if [[ -d /nix/var/nix/profiles/per-user ]]; then
    GENERATIONS=$(find /nix/var/nix/profiles/per-user -name "*-link" 2>/dev/null | wc -l | tr -d ' ')

    if [[ ${GENERATIONS} -gt ${GENERATION_WARNING_THRESHOLD} ]]; then
        print_status "warn" "User generations: ${GENERATIONS} (many generations!)"
        echo "    → Run: nix-collect-garbage -d"
    else
        print_status "ok" "User generations: ${GENERATIONS}"
    fi
else
    print_status "info" "No user generations found"
fi

# =============================================================================
# CHECK 7: Dev Caches
# =============================================================================

echo ""
echo "Checking development caches..."

# uv cache
UV_CACHE_KB=$(get_cache_kb ~/.cache/uv)
UV_CACHE_SIZE=$(get_cache_human ~/.cache/uv)
if [[ ${UV_CACHE_KB} -gt ${CACHE_WARNING_KB} ]]; then
    print_status "warn" "uv cache: ${UV_CACHE_SIZE} (large!)"
    echo "    → Run: uv cache clean"
else
    print_status "info" "uv cache: ${UV_CACHE_SIZE}"
fi

# npm cache
NPM_CACHE_KB=$(get_cache_kb ~/.npm)
NPM_CACHE_SIZE=$(get_cache_human ~/.npm)
if [[ ${NPM_CACHE_KB} -gt ${CACHE_WARNING_KB} ]]; then
    print_status "warn" "npm cache: ${NPM_CACHE_SIZE} (large!)"
    echo "    → Run: npm cache clean --force"
else
    print_status "info" "npm cache: ${NPM_CACHE_SIZE}"
fi

# pnpm cache
PNPM_CACHE_KB=$(get_cache_kb ~/.local/share/pnpm)
PNPM_CACHE_SIZE=$(get_cache_human ~/.local/share/pnpm)
if [[ ${PNPM_CACHE_KB} -gt ${CACHE_WARNING_KB} ]]; then
    print_status "warn" "pnpm cache: ${PNPM_CACHE_SIZE} (large!)"
    echo "    → Run: pnpm store prune"
else
    print_status "info" "pnpm cache: ${PNPM_CACHE_SIZE}"
fi

# Total cache estimate
TOTAL_CACHE_KB=$((UV_CACHE_KB + NPM_CACHE_KB + PNPM_CACHE_KB))
TOTAL_CACHE_GB=$((TOTAL_CACHE_KB / 1024 / 1024))
if [[ ${TOTAL_CACHE_GB} -gt 3 ]]; then
    print_status "warn" "Total dev caches: ~${TOTAL_CACHE_GB}GB"
fi

# =============================================================================
# CHECK 8: Claude Code
# =============================================================================

echo ""
echo "Checking Claude Code..."

if command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    print_status "ok" "Claude Code available: ${CLAUDE_VERSION}"
else
    print_status "error" "Claude Code not found in PATH"
    echo "    → Enter dev shell: dev"
fi

# =============================================================================
# CHECK 9: MCP Servers
# =============================================================================

echo ""
echo "Checking MCP servers..."

MCP_CONFIG="$HOME/.config/claude/config.json"

if [[ -f "${MCP_CONFIG}" ]]; then
    print_status "ok" "MCP config exists: ${MCP_CONFIG}"

    # Check for specific servers in config
    if grep -q "context7" "${MCP_CONFIG}" 2>/dev/null; then
        print_status "ok" "Context7 MCP server configured"
    else
        print_status "warn" "Context7 MCP server not found in config"
    fi

    if grep -q "github" "${MCP_CONFIG}" 2>/dev/null; then
        print_status "ok" "GitHub MCP server configured"
    else
        print_status "warn" "GitHub MCP server not found in config"
    fi

    if grep -q "sequential-thinking" "${MCP_CONFIG}" 2>/dev/null; then
        print_status "ok" "Sequential Thinking MCP server configured"
    else
        print_status "warn" "Sequential Thinking MCP server not found in config"
    fi
else
    print_status "warn" "MCP config not found: ${MCP_CONFIG}"
    echo "    → Enter dev shell to generate: dev"
fi

# =============================================================================
# CHECK 10: Dev Tools
# =============================================================================

echo ""
echo "Checking dev tools..."

# List of essential dev tools
TOOLS="gh rg fd bat fzf lazygit"
MISSING_TOOLS=()

for tool in ${TOOLS}; do
    if command -v "${tool}" &>/dev/null; then
        print_status "ok" "${tool} available"
    else
        print_status "warn" "${tool} not found"
        MISSING_TOOLS+=("${tool}")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "    → Enter dev shell for all tools: dev"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "=== Health Check Complete ==="
echo ""
echo "Quick commands:"
echo "  nix-collect-garbage -d   - Remove old generations"
echo "  nix store optimise       - Optimize Nix store"
echo "  ncdu ~/.cache            - Analyze cache usage"
echo "  btop                     - Interactive system monitor"
echo "  sudo fail2ban-client status sshd - View banned IPs"
echo ""
