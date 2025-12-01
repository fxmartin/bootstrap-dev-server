#!/usr/bin/env bash
# ABOUTME: Hetzner Cloud provisioning script for CPX11 dev server
# ABOUTME: Creates VM, configures SSH, and runs bootstrap automatically
#===============================================================================
# Hetzner Cloud CPX11 Provisioner
#
# Usage:
#   ./hcloud-provision.sh                    # Interactive mode
#   ./hcloud-provision.sh --name myserver    # With custom name
#   ./hcloud-provision.sh --delete myserver  # Delete existing server
#
# Prerequisites:
#   - hcloud CLI installed (brew install hcloud)
#   - Hetzner API token (from https://console.hetzner.cloud/)
#   - SSH key at ~/.ssh/id_devserver (or specify with --ssh-key)
#
# What this script does:
#   1. Authenticates with Hetzner Cloud API
#   2. Uploads your SSH key (if not already present)
#   3. Creates a CX11 server with Ubuntu 24.04
#   4. Waits for server to be ready
#   5. Creates your user account with sudo access
#   6. Runs the bootstrap script on the server
#   7. Prints connection instructions
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

#===============================================================================
# Configuration
#===============================================================================
SERVER_NAME="${SERVER_NAME:-cpx11-dev}"
SERVER_TYPE="${SERVER_TYPE:-cx22}"
SERVER_IMAGE="${SERVER_IMAGE:-ubuntu-24.04}"
SERVER_LOCATION="${SERVER_LOCATION:-fsn1}"  # fsn1=Falkenstein, nbg1=Nuremberg, hel1=Helsinki, ash=Ashburn, hil=Hillsboro
SSH_KEY_NAME="${SSH_KEY_NAME:-dev-server-key}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_devserver}"
SSH_USER="${SSH_USER:-fx}"
BOOTSTRAP_URL="https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh"

#===============================================================================
# Help
#===============================================================================
show_help() {
    cat << 'EOF'
Hetzner Cloud Provisioner

USAGE:
    ./hcloud-provision.sh [OPTIONS]

OPTIONS:
    --name NAME         Server name (default: cpx11-dev)
    --type TYPE         Server type (default: cx22)
    --location LOC      Datacenter location (default: fsn1)
    --user USER         Username to create (default: fx)
    --ssh-key PATH      Path to SSH private key (default: ~/.ssh/id_devserver)
    --yes, -y           Auto-confirm bootstrap (no prompt)
    --no-bootstrap      Skip bootstrap, only create server
    --delete NAME       Delete server with given name
    --rescale NAME      Rescale server to new type (use with --type)
    --list              List all servers
    --help              Show this help

LOCATIONS:
    fsn1    Falkenstein, Germany (EU)
    nbg1    Nuremberg, Germany (EU)
    hel1    Helsinki, Finland (EU)
    ash     Ashburn, Virginia (US East)
    hil     Hillsboro, Oregon (US West)

SERVER TYPES (x86 Intel - cost optimized):
    cx22    2 vCPU,  4GB RAM,  40GB SSD  (~€4.35/mo) [DEFAULT]
    cx32    4 vCPU,  8GB RAM,  80GB SSD  (~€8.39/mo)
    cx42    8 vCPU, 16GB RAM, 160GB SSD  (~€16.39/mo)

SERVER TYPES (x86 AMD - better performance):
    cpx11   2 vCPU,  2GB RAM,  40GB SSD  (~€4.35/mo)
    cpx21   3 vCPU,  4GB RAM,  80GB SSD  (~€8.39/mo)
    cpx31   4 vCPU,  8GB RAM, 160GB SSD  (~€15.59/mo)

SERVER TYPES (ARM Ampere - best value):
    cax11   2 vCPU,  4GB RAM,  40GB SSD  (~€3.85/mo)
    cax21   4 vCPU,  8GB RAM,  80GB SSD  (~€7.25/mo)
    cax31   8 vCPU, 16GB RAM, 160GB SSD  (~€13.95/mo)

EXAMPLES:
    # Create server and run bootstrap (with confirmation prompt)
    ./hcloud-provision.sh

    # Create server and run bootstrap automatically (no prompts)
    ./hcloud-provision.sh --yes

    # Create server only, skip bootstrap
    ./hcloud-provision.sh --no-bootstrap

    # Create with custom name in US
    ./hcloud-provision.sh --name my-dev --location ash --yes

    # Create larger server
    ./hcloud-provision.sh --name powerful --type cpx31

    # Create ARM server (cheaper)
    ./hcloud-provision.sh --name arm-dev --type cax11

    # Delete a server
    ./hcloud-provision.sh --delete cpx11-dev

    # Rescale a server to a new type
    ./hcloud-provision.sh --rescale cpx11-dev --type cx22

    # List all servers
    ./hcloud-provision.sh --list

ENVIRONMENT VARIABLES:
    HCLOUD_TOKEN        Hetzner API token (avoids interactive prompt)
    SERVER_NAME         Default server name
    SERVER_TYPE         Default server type
    SERVER_LOCATION     Default location
    SSH_USER            Default username
EOF
}

#===============================================================================
# Generate Dedicated SSH Key
#===============================================================================
generate_dedicated_key() {
    local key_path="$1"
    local key_comment="${2:-devserver-$(date +%Y%m%d)}"

    if [[ -f "$key_path" ]]; then
        log_info "SSH key already exists: $key_path"
        return 0
    fi

    log_info "Generating dedicated ED25519 SSH key for dev server access..."
    echo ""
    log_warn "SECURITY NOTE: This key is for dev server access ONLY."
    log_warn "Do NOT use this key for GitHub, GitLab, or other services."
    echo ""

    # Ensure .ssh directory exists with proper permissions
    mkdir -p "$(dirname "$key_path")"
    chmod 700 "$(dirname "$key_path")"

    # Generate ED25519 key without passphrase (for automation)
    # User should add passphrase after provisioning with: ssh-keygen -p -f ~/.ssh/id_devserver
    if ! ssh-keygen -t ed25519 -C "$key_comment" -f "$key_path" -N ""; then
        log_error "Failed to generate SSH key"
        return 1
    fi

    # Set proper permissions
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    echo ""
    log_ok "SSH key generated: $key_path"
    echo ""
    log_warn "╔════════════════════════════════════════════════════════════════════╗"
    log_warn "║  IMPORTANT: Key created WITHOUT passphrase for automation.         ║"
    log_warn "║                                                                     ║"
    log_warn "║  After provisioning, ADD a passphrase for security:                ║"
    log_warn "║    ssh-keygen -p -f $key_path"
    log_warn "║                                                                     ║"
    log_warn "║  Then add to ssh-agent with Keychain:                              ║"
    log_warn "║    ssh-add --apple-use-keychain $key_path"
    log_warn "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    return 0
}

#===============================================================================
# Parse Arguments
#===============================================================================
DELETE_SERVER=""
RESCALE_SERVER=""
LIST_SERVERS=false
AUTO_BOOTSTRAP=false
SKIP_BOOTSTRAP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            SERVER_NAME="$2"
            shift 2
            ;;
        --type)
            SERVER_TYPE="$2"
            shift 2
            ;;
        --location)
            SERVER_LOCATION="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --delete)
            DELETE_SERVER="$2"
            shift 2
            ;;
        --rescale)
            RESCALE_SERVER="$2"
            shift 2
            ;;
        --list)
            LIST_SERVERS=true
            shift
            ;;
        --yes|-y)
            AUTO_BOOTSTRAP=true
            shift
            ;;
        --no-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

#===============================================================================
# Check Prerequisites
#===============================================================================
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check hcloud CLI
    if ! command -v hcloud &>/dev/null; then
        log_error "hcloud CLI not found"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install hcloud"
        echo "  Linux:  snap install hcloud"
        echo "  Other:  https://github.com/hetznercloud/cli/releases"
        exit 1
    fi
    log_ok "hcloud CLI found: $(hcloud version)"

    # Check SSH key - only needed for provisioning (not delete/list/rescale)
    if [[ -z "$DELETE_SERVER" && -z "$RESCALE_SERVER" && "$LIST_SERVERS" != true ]]; then
        if [[ ! -f "$SSH_KEY_PATH" ]]; then
            log_info "SSH key not found: $SSH_KEY_PATH"
            echo ""
            read -r -p "Generate a new dedicated dev server SSH key? (Y/n): " response
            if [[ "$response" =~ ^[Nn]$ ]]; then
                log_error "SSH key required. Generate manually or specify with --ssh-key"
                exit 1
            fi

            if ! generate_dedicated_key "$SSH_KEY_PATH"; then
                log_error "Failed to generate SSH key"
                exit 1
            fi
        fi

        if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
            log_error "SSH public key not found: ${SSH_KEY_PATH}.pub"
            exit 1
        fi
        log_ok "SSH key found: $SSH_KEY_PATH"
    fi

    # Check jq for JSON parsing
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found, installing..."
        if command -v brew &>/dev/null; then
            brew install jq
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y jq
        else
            log_error "Please install jq manually"
            exit 1
        fi
    fi
    log_ok "jq found"
}

#===============================================================================
# Authenticate with Hetzner
#===============================================================================
authenticate_hcloud() {
    log_step "Authenticating with Hetzner Cloud..."

    # Check if already authenticated
    if hcloud context active &>/dev/null; then
        local active_context
        active_context=$(hcloud context active)
        log_ok "Already authenticated (context: $active_context)"
        return 0
    fi

    # Check for token in environment
    if [[ -n "${HCLOUD_TOKEN:-}" ]]; then
        log_info "Using HCLOUD_TOKEN from environment"
        hcloud context create dev-server
        return 0
    fi

    # Interactive authentication
    echo ""
    log_info "Hetzner Cloud authentication required"
    echo ""
    echo "1. Go to: https://console.hetzner.cloud/"
    echo "2. Select your project → Security → API Tokens"
    echo "3. Generate API Token (Read & Write)"
    echo "4. Copy the token"
    echo ""

    read -r -p "Paste your Hetzner API token: " token
    if [[ -z "$token" ]]; then
        log_error "Token cannot be empty"
        exit 1
    fi

    # Create context with token
    export HCLOUD_TOKEN="$token"
    hcloud context create dev-server

    log_ok "Authenticated with Hetzner Cloud"
}

#===============================================================================
# Upload SSH Key
#===============================================================================
upload_ssh_key() {
    log_step "Checking SSH key in Hetzner..."

    local pub_key
    pub_key=$(cat "${SSH_KEY_PATH}.pub")

    # Check if key already exists (by fingerprint)
    local existing_keys
    existing_keys=$(hcloud ssh-key list -o json)

    local key_fingerprint
    # Hetzner uses MD5 fingerprint format, strip the "MD5:" prefix
    key_fingerprint=$(ssh-keygen -E md5 -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}' | sed 's/^MD5://')

    if echo "$existing_keys" | jq -e ".[] | select(.fingerprint == \"$key_fingerprint\")" &>/dev/null; then
        SSH_KEY_NAME=$(echo "$existing_keys" | jq -r ".[] | select(.fingerprint == \"$key_fingerprint\") | .name")
        log_ok "SSH key already exists: $SSH_KEY_NAME"
        return 0
    fi

    # Check if a key with the same name exists (but different fingerprint)
    if echo "$existing_keys" | jq -e ".[] | select(.name == \"$SSH_KEY_NAME\")" &>/dev/null; then
        log_warn "Key name '$SSH_KEY_NAME' already exists with different fingerprint"
        # Make the name unique by adding short fingerprint suffix
        local short_fp
        short_fp=$(echo "$key_fingerprint" | tail -c 9)  # Last 8 chars of fingerprint
        SSH_KEY_NAME="${SSH_KEY_NAME}-${short_fp}"
        log_info "Using unique name: $SSH_KEY_NAME"
    fi

    # Upload new key
    log_info "Uploading SSH key: $SSH_KEY_NAME"
    if ! hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key "$pub_key"; then
        log_error "Failed to upload SSH key"
        exit 1
    fi

    log_ok "SSH key uploaded: $SSH_KEY_NAME"
}

#===============================================================================
# Create Server
#===============================================================================
create_server() {
    log_step "Creating server: $SERVER_NAME"

    # Check if server already exists
    if hcloud server describe "$SERVER_NAME" &>/dev/null; then
        log_warn "Server '$SERVER_NAME' already exists"
        echo ""
        read -r -p "Delete and recreate? (y/N): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log_info "Deleting existing server..."
            hcloud server delete "$SERVER_NAME"
            sleep 2
        else
            log_info "Using existing server"
            return 0
        fi
    fi

    echo ""
    log_info "Server configuration:"
    echo "  Name:     $SERVER_NAME"
    echo "  Type:     $SERVER_TYPE"
    echo "  Image:    $SERVER_IMAGE"
    echo "  Location: $SERVER_LOCATION"
    echo "  SSH Key:  $SSH_KEY_NAME"
    echo ""

    # Create server
    if ! hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image "$SERVER_IMAGE" \
        --location "$SERVER_LOCATION" \
        --ssh-key "$SSH_KEY_NAME"; then
        log_error "Failed to create server"
        exit 1
    fi

    log_ok "Server created: $SERVER_NAME"
}

#===============================================================================
# Wait for Server
#===============================================================================
wait_for_server() {
    log_step "Waiting for server to be ready..."

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local status
        status=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.status')

        if [[ "$status" == "running" ]]; then
            log_ok "Server is running"
            break
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    if [[ $attempt -ge $max_attempts ]]; then
        log_error "Server failed to start within timeout"
        exit 1
    fi

    # Get server IP
    SERVER_IP=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')
    log_ok "Server IP: $SERVER_IP"

    # Wait for SSH to be available
    log_info "Waiting for SSH to be available..."
    attempt=0
    while [[ $attempt -lt 30 ]]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes \
            -i "$SSH_KEY_PATH" "root@$SERVER_IP" "echo ok" &>/dev/null; then
            log_ok "SSH is available"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done

    log_error "SSH connection timeout"
    exit 1
}

#===============================================================================
# Setup User Account
#===============================================================================
setup_user_account() {
    log_step "Setting up user account: $SSH_USER"

    # Commands to run on server as root
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "root@$SERVER_IP" << REMOTE_SCRIPT
set -e

# Create user if not exists
if ! id "$SSH_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$SSH_USER"
    echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$SSH_USER
    chmod 440 /etc/sudoers.d/$SSH_USER
fi

# Setup SSH for user
mkdir -p /home/$SSH_USER/.ssh
cp /root/.ssh/authorized_keys /home/$SSH_USER/.ssh/
chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh
chmod 700 /home/$SSH_USER/.ssh
chmod 600 /home/$SSH_USER/.ssh/authorized_keys

echo "User $SSH_USER created with SSH access"
REMOTE_SCRIPT

    log_ok "User account created: $SSH_USER"
}

#===============================================================================
# Run Bootstrap Script
#===============================================================================
run_bootstrap() {
    # Skip bootstrap if requested
    if [[ "$SKIP_BOOTSTRAP" == true ]]; then
        log_info "Skipping bootstrap (--no-bootstrap). Run manually with:"
        echo "  ssh $SERVER_NAME"
        echo "  curl -fsSL $BOOTSTRAP_URL | bash"
        return 0
    fi

    log_step "Running bootstrap script on server..."

    echo ""
    log_warn "This will take 5-15 minutes. The script will:"
    echo "  1. Update system and install base packages"
    echo "  2. Install GitHub CLI (requires OAuth)"
    echo "  3. Harden SSH and configure firewall"
    echo "  4. Install Nix with flakes"
    echo "  5. Create dev environment with Claude Code"
    echo ""

    # Auto-confirm if --yes flag was passed
    if [[ "$AUTO_BOOTSTRAP" != true ]]; then
        read -r -p "Continue with bootstrap? (Y/n): " response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            log_info "Skipping bootstrap. Run manually with:"
            echo "  ssh $SERVER_NAME"
            echo "  curl -fsSL $BOOTSTRAP_URL | bash"
            return 0
        fi
    fi

    # Run bootstrap as the user (not root)
    log_info "Connecting to server and running bootstrap..."
    echo ""

    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -t "$SSH_USER@$SERVER_IP" \
        "curl -fsSL '$BOOTSTRAP_URL' | bash"

    log_ok "Bootstrap complete!"
}

#===============================================================================
# Update SSH Config
#===============================================================================
update_ssh_config() {
    log_step "Updating SSH config..."

    local ssh_config="$HOME/.ssh/config"
    # Security-hardened SSH config entry:
    # - IdentitiesOnly: Only use the specified key, don't try others
    # - AddKeysToAgent: Auto-add key to ssh-agent on first use
    # - UseKeychain: Store passphrase in macOS Keychain (ignored on Linux)
    # - ForwardAgent: Disabled for security (don't forward agent to server)
    # - StrictHostKeyChecking: accept-new accepts new hosts, warns on changes
    local entry="# Dev Server: $SERVER_NAME (provisioned $(date +%Y-%m-%d))
Host $SERVER_NAME
    HostName $SERVER_IP
    User $SSH_USER
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
    ForwardAgent no
    StrictHostKeyChecking accept-new"

    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Check if entry already exists
    if [[ -f "$ssh_config" ]] && grep -q "^Host $SERVER_NAME\$" "$ssh_config"; then
        log_info "SSH config entry for '$SERVER_NAME' already exists, updating..."
        # Remove old entry (from "Host $SERVER_NAME" to next "Host " or end of file)
        sed -i.bak "/^Host $SERVER_NAME\$/,/^Host /{/^Host $SERVER_NAME\$/d;/^Host /!d;}" "$ssh_config"
        # If the sed left the file empty or just whitespace, remove it
        if [[ ! -s "$ssh_config" ]] || ! grep -q '[^[:space:]]' "$ssh_config"; then
            rm -f "$ssh_config"
        fi
    fi

    # Append new entry
    if [[ -f "$ssh_config" ]]; then
        # Add newline before entry if file doesn't end with one
        [[ -s "$ssh_config" && $(tail -c1 "$ssh_config" | wc -l) -eq 0 ]] && echo "" >> "$ssh_config"
        echo "" >> "$ssh_config"
    fi
    echo "$entry" >> "$ssh_config"
    chmod 600 "$ssh_config"

    log_ok "SSH config updated: ssh $SERVER_NAME"
}

#===============================================================================
# Print Summary
#===============================================================================
print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Hetzner Cloud Server Provisioned Successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}Server Details:${NC}"
    echo -e "    Name:     ${YELLOW}$SERVER_NAME${NC}"
    echo -e "    Type:     ${YELLOW}$SERVER_TYPE${NC}"
    echo -e "    IP:       ${YELLOW}$SERVER_IP${NC}"
    echo -e "    Location: ${YELLOW}$SERVER_LOCATION${NC}"
    echo ""
    echo -e "  ${BLUE}Connect:${NC}"
    echo -e "    SSH:  ${YELLOW}ssh $SERVER_NAME${NC}  (or ssh $SSH_USER@$SERVER_IP)"
    echo -e "    Mosh: ${YELLOW}mosh $SERVER_NAME${NC}"
    echo ""
    echo -e "  ${BLUE}Quick Start:${NC}"
    echo -e "    ${YELLOW}ssh $SERVER_NAME${NC}"
    echo -e "    ${YELLOW}dev${NC}       # Enter dev environment"
    echo -e "    ${YELLOW}claude${NC}    # Start Claude Code"
    echo ""
    echo -e "  ${BLUE}SSH Config:${NC} ~/.ssh/config updated automatically"
    echo ""
    echo -e "  ${BLUE}Monthly Cost:${NC} Check https://www.hetzner.com/cloud for current pricing"
    echo ""
    echo -e "  ${BLUE}Management:${NC}"
    echo -e "    Delete:   ${YELLOW}hcloud server delete $SERVER_NAME${NC}"
    echo -e "    Snapshot: ${YELLOW}hcloud server create-image $SERVER_NAME${NC}"
    echo -e "    Console:  ${YELLOW}https://console.hetzner.cloud/${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
}

#===============================================================================
# Delete Server
#===============================================================================
delete_server() {
    local name="$1"
    log_step "Deleting server: $name"

    if ! hcloud server describe "$name" &>/dev/null; then
        log_error "Server '$name' not found"
        exit 1
    fi

    echo ""
    log_warn "This will permanently delete the server and all its data!"
    read -r -p "Are you sure? Type server name to confirm: " confirm

    if [[ "$confirm" != "$name" ]]; then
        log_info "Deletion cancelled"
        exit 0
    fi

    hcloud server delete "$name"
    log_ok "Server '$name' deleted"

    # Remove SSH config entry
    local ssh_config="$HOME/.ssh/config"
    if [[ -f "$ssh_config" ]] && grep -q "^Host $name\$" "$ssh_config"; then
        log_info "Removing SSH config entry for '$name'..."
        # Create backup and remove the entry block
        sed -i.bak "/^Host $name\$/,/^Host /{/^Host $name\$/d;/^Host /!d;}" "$ssh_config"
        # Clean up empty lines at end of file
        sed -i.bak -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$ssh_config" 2>/dev/null || true
        rm -f "${ssh_config}.bak"
        log_ok "SSH config entry removed"
    fi
}

#===============================================================================
# List Servers
#===============================================================================
list_servers() {
    log_step "Listing servers..."
    echo ""
    hcloud server list
}

#===============================================================================
# Rescale Server
#===============================================================================
rescale_server() {
    local name="$1"
    local new_type="$2"

    log_step "Rescaling server: $name → $new_type"

    # Check server exists
    if ! hcloud server describe "$name" &>/dev/null; then
        log_error "Server '$name' not found"
        exit 1
    fi

    # Get current server info
    local current_type
    current_type=$(hcloud server describe "$name" -o format='{{.ServerType.Name}}')
    local current_status
    current_status=$(hcloud server describe "$name" -o format='{{.Status}}')

    echo ""
    log_info "Current type: $current_type"
    log_info "New type: $new_type"
    log_info "Current status: $current_status"
    echo ""

    if [[ "$current_type" == "$new_type" ]]; then
        log_warn "Server is already type '$new_type'"
        exit 0
    fi

    # Check architecture compatibility (can't switch x86 <-> ARM)
    local current_arch new_arch
    if [[ "$current_type" == cax* ]]; then
        current_arch="arm"
    else
        current_arch="x86"
    fi
    if [[ "$new_type" == cax* ]]; then
        new_arch="arm"
    else
        new_arch="x86"
    fi

    if [[ "$current_arch" != "$new_arch" ]]; then
        log_error "Cannot rescale between architectures ($current_arch → $new_arch)"
        log_error "x86 (cx*, cpx*) and ARM (cax*) are not compatible"
        exit 1
    fi

    log_warn "╔════════════════════════════════════════════════════════════════════╗"
    log_warn "║  WARNING: Rescaling requires server shutdown!                      ║"
    log_warn "║  The server will be unavailable for 1-2 minutes.                   ║"
    log_warn "║  Data, IP address, and configuration will be preserved.            ║"
    log_warn "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    read -r -p "Continue with rescale? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Rescale cancelled"
        exit 0
    fi

    # Power off if running
    if [[ "$current_status" == "running" ]]; then
        log_info "Powering off server..."
        hcloud server poweroff "$name"

        # Wait for poweroff
        local attempts=0
        while [[ $attempts -lt 30 ]]; do
            current_status=$(hcloud server describe "$name" -o format='{{.Status}}')
            if [[ "$current_status" == "off" ]]; then
                break
            fi
            echo -n "."
            sleep 2
            ((attempts++))
        done
        echo ""

        if [[ "$current_status" != "off" ]]; then
            log_error "Failed to power off server"
            exit 1
        fi
        log_ok "Server powered off"
    fi

    # Perform rescale
    log_info "Changing server type to $new_type..."
    if ! hcloud server change-type "$name" "$new_type"; then
        log_error "Failed to rescale server"
        log_warn "Attempting to power server back on..."
        hcloud server poweron "$name"
        exit 1
    fi
    log_ok "Server type changed to $new_type"

    # Power back on
    log_info "Powering on server..."
    hcloud server poweron "$name"

    # Wait for server to be running
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        current_status=$(hcloud server describe "$name" -o format='{{.Status}}')
        if [[ "$current_status" == "running" ]]; then
            break
        fi
        echo -n "."
        sleep 2
        ((attempts++))
    done
    echo ""

    if [[ "$current_status" != "running" ]]; then
        log_error "Server failed to start"
        exit 1
    fi

    log_ok "Server '$name' successfully rescaled to $new_type"

    # Show new server info
    echo ""
    hcloud server describe "$name"
}

#===============================================================================
# Main
#===============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Hetzner Cloud Provisioner                                   ║${NC}"
    echo -e "${BLUE}║       Automated Ubuntu 24.04 + Nix + Claude Code Setup            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Handle special commands
    if [[ "$LIST_SERVERS" == true ]]; then
        check_prerequisites
        authenticate_hcloud
        list_servers
        exit 0
    fi

    if [[ -n "$DELETE_SERVER" ]]; then
        check_prerequisites
        authenticate_hcloud
        delete_server "$DELETE_SERVER"
        exit 0
    fi

    if [[ -n "$RESCALE_SERVER" ]]; then
        check_prerequisites
        authenticate_hcloud
        rescale_server "$RESCALE_SERVER" "$SERVER_TYPE"
        exit 0
    fi

    # Normal provisioning flow
    check_prerequisites
    authenticate_hcloud
    upload_ssh_key
    create_server
    wait_for_server
    setup_user_account
    update_ssh_config
    run_bootstrap
    print_summary
}

main "$@"
