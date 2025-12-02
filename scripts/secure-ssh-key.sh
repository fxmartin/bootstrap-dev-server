#!/usr/bin/env bash
# ABOUTME: Helper script to add passphrase to dev server SSH key
# ABOUTME: Run this after provisioning to secure your key at rest

set -euo pipefail

#===============================================================================
# Logging Setup
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/logging.sh"

# Source the logging library
if [[ -f "${LIB_PATH}" ]]; then
    # shellcheck disable=SC1091  # Path is dynamically checked
    # shellcheck source=../lib/logging.sh
    source "${LIB_PATH}"
else
    # Fallback if library not found
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    # shellcheck disable=SC2312
    log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[INFO]${NC}  ${1}"; }
    # shellcheck disable=SC2312
    log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[OK]${NC}    ${1}"; }
    # shellcheck disable=SC2312
    log_warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARN]${NC}  ${1}" >&2; }
    # shellcheck disable=SC2312
    log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} ${1}" >&2; }
fi

#===============================================================================
# Configuration
#===============================================================================
DEFAULT_KEY_PATH="${HOME}/.ssh/id_devserver"
KEY_PATH="${1:-${DEFAULT_KEY_PATH}}"

#===============================================================================
# Main
#===============================================================================
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Secure SSH Key - Add Passphrase Protection                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check key exists
if [[ ! -f "${KEY_PATH}" ]]; then
    log_error "SSH key not found: ${KEY_PATH}"
    echo ""
    echo "Generate a key first with:"
    echo "  ssh-keygen -t ed25519 -C \"devserver-\$(date +%Y%m%d)\" -f ${KEY_PATH}"
    exit 1
fi

log_info "Checking key: ${KEY_PATH}"
echo ""

# Check if key already has a passphrase
# ssh-keygen -y extracts public key; -P "" tries empty passphrase
# If this succeeds, the key has NO passphrase (we can read it with empty password)
# If it fails, the key IS protected by a passphrase
if ssh-keygen -y -P "" -f "${KEY_PATH}" &>/dev/null; then
    log_warn "Key currently has NO passphrase."
    echo ""
    echo "A passphrase encrypts your private key at rest (AES-256-CTR)."
    echo "Even if someone gets your key file, they can't use it without the passphrase."
    echo ""
    echo -e "${BLUE}Passphrase requirements:${NC}"
    echo "  - 12+ characters recommended"
    echo "  - Mix of uppercase, lowercase, numbers, symbols"
    echo "  - Use a password manager to generate/store it"
    echo ""
    log_warn "Adding passphrase now..."
    echo ""

    # Add passphrase
    if ssh-keygen -p -f "${KEY_PATH}"; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Passphrase added successfully!                                    ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Next step:${NC} Add key to ssh-agent with Keychain storage:"
        echo ""
        echo -e "  ${YELLOW}ssh-add --apple-use-keychain ${KEY_PATH}${NC}"
        echo ""
        echo "This stores your passphrase in macOS Keychain so you only enter it once."
        echo ""
    else
        log_error "Failed to add passphrase"
        exit 1
    fi
else
    log_ok "Key already has a passphrase."
    echo ""
    echo "To change the passphrase:"
    echo "  ssh-keygen -p -f ${KEY_PATH}"
    echo ""
    echo "To add to ssh-agent with Keychain:"
    echo "  ssh-add --apple-use-keychain ${KEY_PATH}"
    echo ""
fi
