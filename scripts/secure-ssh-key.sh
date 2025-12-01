#!/usr/bin/env bash
# ABOUTME: Helper script to add passphrase to dev server SSH key
# ABOUTME: Run this after provisioning to secure your key at rest

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================
DEFAULT_KEY_PATH="$HOME/.ssh/id_devserver"
KEY_PATH="${1:-$DEFAULT_KEY_PATH}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# Main
#===============================================================================
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Secure SSH Key - Add Passphrase Protection                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check key exists
if [[ ! -f "$KEY_PATH" ]]; then
    echo -e "${RED}[ERROR]${NC} SSH key not found: $KEY_PATH"
    echo ""
    echo "Generate a key first with:"
    echo "  ssh-keygen -t ed25519 -C \"devserver-\$(date +%Y%m%d)\" -f $KEY_PATH"
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Checking key: $KEY_PATH"
echo ""

# Check if key already has a passphrase
if ssh-keygen -y -P "" -f "$KEY_PATH" &>/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} Key currently has NO passphrase."
    echo ""
    echo "A passphrase encrypts your private key at rest (AES-256-CTR)."
    echo "Even if someone gets your key file, they can't use it without the passphrase."
    echo ""
    echo -e "${BLUE}Passphrase requirements:${NC}"
    echo "  - 12+ characters recommended"
    echo "  - Mix of uppercase, lowercase, numbers, symbols"
    echo "  - Use a password manager to generate/store it"
    echo ""
    echo -e "${YELLOW}Adding passphrase now...${NC}"
    echo ""

    # Add passphrase
    if ssh-keygen -p -f "$KEY_PATH"; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ Passphrase added successfully!                                 ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Next step:${NC} Add key to ssh-agent with Keychain storage:"
        echo ""
        echo -e "  ${YELLOW}ssh-add --apple-use-keychain $KEY_PATH${NC}"
        echo ""
        echo "This stores your passphrase in macOS Keychain so you only enter it once."
        echo ""
    else
        echo -e "${RED}[ERROR]${NC} Failed to add passphrase"
        exit 1
    fi
else
    echo -e "${GREEN}[OK]${NC} Key already has a passphrase."
    echo ""
    echo "To change the passphrase:"
    echo "  ssh-keygen -p -f $KEY_PATH"
    echo ""
    echo "To add to ssh-agent with Keychain:"
    echo "  ssh-add --apple-use-keychain $KEY_PATH"
    echo ""
fi
