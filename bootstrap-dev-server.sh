#!/usr/bin/env bash
#===============================================================================
# Bootstrap Dev Server Script
#
# Usage: curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | bash
#
# Idempotent: Safe to run multiple times
# Requirements: Fresh Ubuntu 24.04 server with sudo access
# Supports: Hetzner Cloud (cx23, cx33, etc.), Parallels VM, Docker/Podman
#===============================================================================

set -euo pipefail

#===============================================================================
# Logging Setup
#===============================================================================
# Minimal inline logging for curl|bash bootstrap (before repo is cloned)
# These get upgraded to full logging library after clone_bootstrap_repo()

# Colors for output (may be overwritten by logging library)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Basic logging functions (may be overwritten by logging library)
# shellcheck disable=SC2312
log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[INFO]${NC}  ${1}"; }
# shellcheck disable=SC2312
log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[OK]${NC}    ${1}"; }
# shellcheck disable=SC2312
log_warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARN]${NC}  ${1}" >&2; }
# shellcheck disable=SC2312
log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} ${1}" >&2; }
# shellcheck disable=SC2312
log_step() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${CYAN}[STEP]${NC}  ═══ ${1} ═══"; }
log_phase() { log_step "Phase: ${1}"; }
# shellcheck disable=SC2312
log_debug() { [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo -e "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] ${1}" || true; }

# Upgrade to full logging library if available (called after repo clone)
upgrade_logging() {
    local lib_path="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/logging.sh"
    if [[ -f "${lib_path}" ]]; then
        # shellcheck disable=SC1091  # Path is dynamically built from vars
        # shellcheck source=lib/logging.sh
        source "${lib_path}"
        init_logging "bootstrap-dev-server"
        log_debug "Upgraded to full logging library"
    fi
}

#===============================================================================
# Configuration - Edit these for your setup
#===============================================================================
DEV_USER="${DEV_USER:-$(whoami)}"
SERVER_PROFILE="${SERVER_PROFILE:-dev}"  # Server profile: dev, nyx, full
SSH_PORT="${SSH_PORT:-22}"
MOSH_PORT_START="${MOSH_PORT_START:-60000}"
MOSH_PORT_END="${MOSH_PORT_END:-60010}"

# Security hardening configuration
UFW_RATE_LIMIT="${UFW_RATE_LIMIT:-true}"           # Enable UFW rate limiting for SSH
GEOIP_ENABLED="${GEOIP_ENABLED:-true}"             # Enable GeoIP country blocking
GEOIP_COUNTRIES="${GEOIP_COUNTRIES:-LU,FR,GR}"     # Whitelist: Luxembourg, France, Greece

# Tailscale configuration
# Restrict SSH and Mosh to the tailnet interface, closing them on the public
# internet. Off by default: a fresh server has no tailnet yet, and enabling
# this before Tailscale is up would lock the operator out immediately.
SSH_TAILNET_ONLY="${SSH_TAILNET_ONLY:-false}"
# Tagged nodes are owned by the tailnet, not a user, so their node keys never
# expire. An untagged `tailscale up` expires after 180 days and silently drops
# the server off the tailnet.
TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:trusted}"     # Tags to advertise on `tailscale up`

# GitLab host that glab and the sdlc controller talk to (local-ci-cd GitLab,
# reached over Tailscale split DNS). Exported for every login context below.
GITLAB_HOST="${GITLAB_HOST:-gitlab.test}"

# GitHub authentication
SKIP_GITHUB_AUTH="${SKIP_GITHUB_AUTH:-false}"      # Skip GitHub CLI authentication (for testing)

# Security hardening (for testing in containers without privileges)
SKIP_SECURITY_HARDENING="${SKIP_SECURITY_HARDENING:-false}"  # Skip security hardening phase

# herdr server hand-over: a server running outside the systemd unit is only
# stopped when asked, because stopping it ends its sessions and agent panes.
RESTART_HERDR="${RESTART_HERDR:-false}"            # Stop an outside herdr server so the unit takes over

# Internal state (set by functions)
SSH_RESTART_NEEDED=false                           # Set by harden_ssh() if restart needed
ACM_TOKEN_MISSING=false                            # Set by configure_acm_access_token() when no read token exists

# Repository configuration
GITHUB_REPO="fxmartin/bootstrap-dev-server"
REPO_CLONE_DIR="${HOME}/.local/share/bootstrap-dev-server"
BOOTSTRAP_SUBDIR="."

#===============================================================================
# Preflight Checks
#===============================================================================
preflight_checks() {
    log_info "Running preflight checks..."

    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        # shellcheck disable=SC2154  # ID and PRETTY_NAME are set by os-release
        if [[ "${ID}" != "ubuntu" ]]; then
            # shellcheck disable=SC2154
            log_error "This script is designed for Ubuntu. Detected: ${ID}"
            exit 1
        fi
        # shellcheck disable=SC2154
        log_ok "Detected ${PRETTY_NAME}"
    fi

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_warn "Script requires sudo access. You may be prompted for password."
    fi

    # Check internet connectivity
    if ! ping -c 1 github.com &>/dev/null; then
        log_error "No internet connectivity"
        exit 1
    fi
    log_ok "Internet connectivity verified"
}

#===============================================================================
# System Updates & Base Packages
#===============================================================================
install_base_packages() {
    log_info "Updating system and installing base packages..."

    export DEBIAN_FRONTEND=noninteractive

    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq

    # Minimal base packages (most tools will come from Nix)
    sudo apt-get install -y -qq \
        curl \
        wget \
        git \
        jq \
        xz-utils \
        ufw \
        fail2ban \
        zsh \
        uidmap \
        unattended-upgrades \
        mosh

    log_ok "Base packages installed"
}

#===============================================================================
# Configure Unattended Upgrades for automatic security updates
#===============================================================================
configure_unattended_upgrades() {
    log_info "Configuring automatic security updates..."

    # Check if already configured
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        if grep -q "APT::Periodic::Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades; then
            log_ok "Unattended upgrades already configured"
            return 0
        fi
    fi

    # Enable automatic updates (daily check, security updates only)
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'AUTOUPGRADEEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADEEOF

    # Configure what gets upgraded (security only, with auto-reboot if needed)
    sudo tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null <<'UNATTENDEDEOF'
// Automatically upgrade packages from these origins
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Do NOT auto-upgrade non-security packages
Unattended-Upgrade::Package-Blacklist {
};

// Auto-reboot at 4am if required (minimal disruption)
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";

// Remove unused kernel packages after upgrade
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies after upgrade
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Log to syslog
Unattended-Upgrade::SyslogEnable "true";
UNATTENDEDEOF

    # Verify the service is enabled
    sudo systemctl enable --now unattended-upgrades.service 2>/dev/null || true

    log_ok "Automatic security updates configured (daily, reboot at 4am if needed)"
}

#===============================================================================
# Refresh GitHub CLI apt key
#===============================================================================
# GitHub rotates the key signing its apt repo. install_github_cli returns early
# once gh exists, so the keyring must be refreshed on every run, before the
# first apt-get update, or that update cannot verify cli.github.com.
GH_KEYRING_FILE="${GH_KEYRING_FILE:-/etc/apt/keyrings/githubcli-archive-keyring.gpg}"
GH_SOURCE_LIST="${GH_SOURCE_LIST:-/etc/apt/sources.list.d/github-cli.list}"
GH_APT_SOURCE_REFRESHED=false

refresh_github_cli_apt_source() {
    local tmp_key tmp_list arch
    tmp_key=$(mktemp)
    tmp_list=$(mktemp)

    # A failed download must not stop the run: an installed gh still works
    if ! wget -qO "${tmp_key}" https://cli.github.com/packages/githubcli-archive-keyring.gpg || [[ ! -s "${tmp_key}" ]]; then
        log_warn "Could not download the GitHub CLI apt key; keeping the existing one"
        rm -f "${tmp_key}" "${tmp_list}"
        return 0
    fi

    arch=$(dpkg --print-architecture)
    echo "deb [arch=${arch} signed-by=${GH_KEYRING_FILE}] https://cli.github.com/packages stable main" >"${tmp_list}"

    sudo mkdir -p -m 755 "$(dirname "${GH_KEYRING_FILE}")"
    if ! cmp -s "${tmp_key}" "${GH_KEYRING_FILE}"; then
        sudo install -m 644 "${tmp_key}" "${GH_KEYRING_FILE}"
        log_ok "GitHub CLI apt key refreshed"
    fi
    if ! cmp -s "${tmp_list}" "${GH_SOURCE_LIST}"; then
        sudo install -m 644 "${tmp_list}" "${GH_SOURCE_LIST}"
    fi

    rm -f "${tmp_key}" "${tmp_list}"
    GH_APT_SOURCE_REFRESHED=true
    return 0
}

#===============================================================================
# Install GitHub CLI
#===============================================================================
install_github_cli() {
    log_info "Installing GitHub CLI..."

    if command -v gh &>/dev/null; then
        # shellcheck disable=SC2312  # gh --version is safe
        log_ok "GitHub CLI already installed: $(gh --version | head -1)"
        return 0
    fi

    if [[ "${GH_APT_SOURCE_REFRESHED}" != "true" ]]; then
        # Add GitHub CLI repository (official method for Ubuntu)
        log_info "Adding GitHub CLI apt repository..."

        # Install required packages for adding repository
        sudo apt-get install -y -qq software-properties-common

        # Add GitHub CLI GPG key
        sudo mkdir -p -m 755 /etc/apt/keyrings
        if ! wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null; then
            log_error "Failed to download GitHub CLI GPG key"
            return 1
        fi
        sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

        # Add repository
        local arch
        arch=$(dpkg --print-architecture)
        echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
            sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    fi

    # Install gh
    sudo apt-get update -qq
    sudo apt-get install -y -qq gh

    # shellcheck disable=SC2312  # gh --version is safe
    log_ok "GitHub CLI installed: $(gh --version | head -1)"
}

#===============================================================================
# Configure Git Identity
#===============================================================================
configure_git_identity() {
    log_info "Configuring Git identity..."

    # Check if git is already configured
    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "${current_name}" ]] && [[ -n "${current_email}" ]]; then
        log_ok "Git already configured: ${current_name} <${current_email}>"
        return 0
    fi

    # Check for environment variables first (allows non-interactive setup)
    local git_name="${GIT_USER_NAME:-}"
    local git_email="${GIT_USER_EMAIL:-}"

    if [[ -n "${git_name}" ]] && [[ -n "${git_email}" ]]; then
        log_info "Using Git identity from environment variables"
    else
        echo ""
        log_info "Git identity not configured. Please provide your details:"
        log_info "(Or set GIT_USER_NAME and GIT_USER_EMAIL environment variables)"
        echo ""

        # Read from /dev/tty to work even when script is piped
        # Prompt for name
        printf "  Full Name: "
        read -r git_name </dev/tty || {
            log_error "Cannot read input. Set GIT_USER_NAME and GIT_USER_EMAIL env vars instead."
            return 1
        }
        if [[ -z "${git_name}" ]]; then
            log_error "Name cannot be empty"
            return 1
        fi

        # Prompt for email
        printf "  Email: "
        read -r git_email </dev/tty || {
            log_error "Cannot read input. Set GIT_USER_NAME and GIT_USER_EMAIL env vars instead."
            return 1
        }
        if [[ -z "${git_email}" ]]; then
            log_error "Email cannot be empty"
            return 1
        fi
    fi

    # Configure git
    git config --global user.name "${git_name}"
    git config --global user.email "${git_email}"

    # Set sensible defaults
    git config --global init.defaultBranch main
    git config --global pull.rebase false

    log_ok "Git configured: ${git_name} <${git_email}>"
}

#===============================================================================
# Authenticate GitHub CLI
#===============================================================================
# gh's setup-git records its resolved /nix/store path as the Git credential
# helper; garbage collection deletes that path after an upgrade and every HTTPS
# push then fails. Name gh by PATH instead, keeping the empty reset entry gh writes.
set_github_git_credential_helpers() {
    local url key
    for url in https://github.com https://gist.github.com; do
        key="credential.${url}.helper"
        git config --global --unset-all "${key}" || true
        git config --global --add "${key}" ''
        git config --global --add "${key}" '!gh auth git-credential'
    done
}

authenticate_github_cli() {
    log_info "Checking GitHub CLI authentication..."

    # Check if already authenticated
    if gh auth status >/dev/null 2>&1; then
        local gh_user
        gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
        log_ok "GitHub CLI already authenticated as: ${gh_user}"
        set_github_git_credential_helpers
        return 0
    fi

    echo ""
    log_info "GitHub CLI authentication required"
    log_info "You'll get a one-time code to enter at: https://github.com/login/device"
    echo ""

    # Authenticate with device code flow (works on headless servers)
    # --hostname github.com: Target GitHub (not enterprise)
    # --git-protocol https: Use HTTPS for git (simpler for servers)
    # No --web flag: Uses device code flow (headless-friendly)
    if ! gh auth login --hostname github.com --git-protocol https; then
        log_error "GitHub CLI authentication failed"
        log_error ""
        log_error "Troubleshooting:"
        log_error "  1. Check internet connection"
        log_error "  2. Try manual auth: gh auth login"
        log_error "  3. Or use token: gh auth login --with-token < token.txt"
        return 1
    fi

    set_github_git_credential_helpers

    # Verify authentication
    local gh_user
    gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    log_ok "GitHub CLI authenticated as: ${gh_user}"
}

#===============================================================================
# Clone Repository (Sparse Checkout - bootstrap-dev-server only)
#===============================================================================
clone_bootstrap_repo() {
    log_info "Cloning bootstrap-dev-server from GitHub..."

    # Check if already cloned
    if [[ -d "${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}" ]]; then
        log_ok "Repository already cloned at ${REPO_CLONE_DIR}"

        # Pull latest changes
        log_info "Pulling latest changes..."
        # Repair a truncated sparse checkout before pulling, so lib/ and
        # config/ are present for the rest of this run.
        converge_sparse_checkout "${REPO_CLONE_DIR}" "${BOOTSTRAP_SUBDIR}" || true
        if (cd "${REPO_CLONE_DIR}" && git pull --quiet); then
            log_ok "Repository updated"
            # Update submodules (Claude Code configs from nix-install)
            log_info "Updating submodules..."
            (cd "${REPO_CLONE_DIR}" && git submodule update --recursive)
            log_ok "Submodules updated"
        else
            log_warn "Failed to pull updates (continuing with existing files)"
        fi
        return 0
    fi

    # Create parent directory
    mkdir -p "$(dirname "${REPO_CLONE_DIR}")"

    if [[ "${BOOTSTRAP_SUBDIR}" == "." ]]; then
        log_info "Cloning the full repository..."
        git clone --filter=blob:none --depth 1 \
            "https://github.com/${GITHUB_REPO}.git" "${REPO_CLONE_DIR}"
    else
        log_info "Using sparse checkout for ${BOOTSTRAP_SUBDIR} folder only..."
        git clone --filter=blob:none --no-checkout --depth 1 --sparse \
            "https://github.com/${GITHUB_REPO}.git" "${REPO_CLONE_DIR}"
    fi

    converge_sparse_checkout "${REPO_CLONE_DIR}" "${BOOTSTRAP_SUBDIR}"
    cd "${REPO_CLONE_DIR}"

    # Initialize submodules (Claude Code configs from nix-install)
    log_info "Initializing Git submodules..."
    git submodule update --init --recursive
    log_ok "Submodules initialized"

    log_ok "Repository cloned at ${REPO_CLONE_DIR}"
}

#===============================================================================
# Sparse Checkout Convergence
#===============================================================================
# `git sparse-checkout set .` materialises ONLY root-level files - lib/,
# scripts/, config/, profiles/ and tests/ are silently omitted while
# `git status` still reports a clean tree. That was harmless when this project
# lived inside nix-install as a subfolder; standalone it means the bootstrap
# script cannot source lib/, and config/ and tests/ never reach the server.
#
# Converges both fresh and existing clones, so servers already carrying the
# truncated checkout are repaired on the next run.
converge_sparse_checkout() {
    local repo_dir="$1"
    local subdir="${2:-.}"

    [[ -e "${repo_dir}/.git" ]] || return 1

    if [[ "${subdir}" == "." ]]; then
        # Whole repository wanted: sparse checkout must be off entirely.
        if [[ "$(git -C "${repo_dir}" config --get core.sparseCheckout 2>/dev/null)" == "true" ]]; then
            log_info "Disabling sparse checkout (whole repository required)"
            git -C "${repo_dir}" sparse-checkout disable
        fi
    else
        git -C "${repo_dir}" sparse-checkout set "${subdir}"
    fi

    # Materialise the working tree for clones made with --no-checkout
    git -C "${repo_dir}" checkout --quiet 2>/dev/null || true
}

#===============================================================================
# SSH Hardening
#===============================================================================
harden_ssh() {
    log_info "Hardening SSH configuration..."

    local SSH_HARDENING_FILE="/etc/ssh/sshd_config.d/99-hardening.conf"

    # Check if port actually needs to change
    local current_port="22"
    if [[ -f "${SSH_HARDENING_FILE}" ]]; then
        current_port=$(grep -E "^Port " "${SSH_HARDENING_FILE}" 2>/dev/null | awk '{print $2}' || echo "22")
    fi

    # Force update if port is different from what's configured
    if [[ "${SSH_PORT}" != "${current_port}" ]]; then
        FORCE_SSH_UPDATE=true
        log_info "SSH port changing from ${current_port} to ${SSH_PORT}"
    fi

    # A file from before the NO_HERDR escape hatch gets rewritten to carry it
    if [[ -f "${SSH_HARDENING_FILE}" ]] && ! grep -qx "AcceptEnv NO_HERDR" "${SSH_HARDENING_FILE}"; then
        FORCE_SSH_UPDATE=true
        log_info "Adding AcceptEnv NO_HERDR to the SSH hardening config"
    fi

    # acm peers forward acmd's Unix socket over ssh -L; a file without the local-forward block refuses it
    if [[ -f "${SSH_HARDENING_FILE}" ]] && ! grep -qx "    AllowTcpForwarding local" "${SSH_HARDENING_FILE}"; then
        FORCE_SSH_UPDATE=true
        log_info "Adding the dev user's local-forward Match block to the SSH hardening config"
    fi

    # Only create if doesn't exist or force update
    if [[ ! -f "${SSH_HARDENING_FILE}" ]] || [[ "${FORCE_SSH_UPDATE:-}" == "true" ]]; then
        sudo tee "${SSH_HARDENING_FILE}" >/dev/null <<SSHEOF
# SSH Hardening Configuration
# Generated by bootstrap-dev-server.sh

# Custom SSH port (default: 22)
Port ${SSH_PORT}

# Disable root login
PermitRootLogin no

# Key-based authentication only
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Disable unused authentication methods
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# Session limits
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Forwarding settings
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding yes

# Strong algorithms only
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Logging
LogLevel VERBOSE
PrintLastLog yes

# Idle timeout (optional - 10 min)
ClientAliveInterval 300
ClientAliveCountMax 2

# Escape hatch from the herdr attach on login: ssh -o SetEnv=NO_HERDR=1 dev
AcceptEnv NO_HERDR

# acm peers forward acmd's Unix socket (ssh -L); this gate also covers stream-local forwards
Match User ${DEV_USER}
    AllowTcpForwarding local
Match all
SSHEOF

        # Validate SSH config (restart deferred to end of bootstrap to avoid killing connection)
        if sudo sshd -t; then
            # Mark that SSH restart is needed at end of bootstrap
            SSH_RESTART_NEEDED=true
            log_ok "SSH hardening config applied (restart deferred to end)"
        else
            log_error "SSH config validation failed! Reverting..."
            sudo rm -f "${SSH_HARDENING_FILE}"
            exit 1
        fi
    else
        log_ok "SSH hardening already configured"
    fi
}

#===============================================================================
# Apply SSH Changes (called at end of bootstrap to avoid killing connection)
#===============================================================================
restart_ssh_final() {
    if [[ "${SSH_RESTART_NEEDED}" != "true" ]]; then
        log_debug "No SSH restart needed"
        return 0
    fi

    log_info "Applying SSH configuration changes..."

    # Ubuntu 24.04 uses socket activation which overrides port config
    # Disable it when using non-standard port
    if [[ "${SSH_PORT}" != "22" ]]; then
        log_warn "Switching SSH to port ${SSH_PORT} - connection will be reset"
        sudo systemctl disable --now ssh.socket 2>/dev/null || true
        sudo systemctl restart ssh || sudo systemctl restart sshd
    else
        sudo systemctl reload ssh || sudo systemctl reload sshd
    fi

    log_ok "SSH configuration applied"
}

#===============================================================================
# Regenerate Host Keys (Optional - only on fresh install)
#===============================================================================
regenerate_host_keys() {
    if [[ "${REGEN_HOST_KEYS:-}" == "true" ]]; then
        log_info "Regenerating SSH host keys..."

        sudo rm -f /etc/ssh/ssh_host_*
        sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        sudo ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""

        # Filter weak DH moduli
        awk '$5 >= 3071' /etc/ssh/moduli | sudo tee /etc/ssh/moduli.tmp >/dev/null
        sudo mv /etc/ssh/moduli.tmp /etc/ssh/moduli

        sudo systemctl reload ssh || sudo systemctl reload sshd
        log_ok "SSH host keys regenerated"
    fi
}

#===============================================================================
# Firewall Configuration
#===============================================================================
configure_firewall() {
    log_info "Configuring UFW firewall..."

    # Reset if already enabled (idempotent)
    sudo ufw --force reset >/dev/null

    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    local tailnet_only=false

    if [[ "${SSH_TAILNET_ONLY}" == "true" ]]; then
        # Closing public SSH is only safe while the tailnet is guaranteed
        # reachable. An untagged node key expires after 180 days, and if that
        # happens once public SSH is shut, the Hetzner web console is the only
        # way back in.
        local ts_lib="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/tailscale.sh"
        if [[ -f "${ts_lib}" ]]; then
            # shellcheck disable=SC1091  # Path is dynamically built from vars
            # shellcheck source=lib/tailscale.sh
            source "${ts_lib}"
        else
            log_warn "lib/tailscale.sh not found - treating the node key as expiring"
            tailscale_key_never_expires() { return 1; }
        fi

        if tailscale_key_never_expires; then
            tailnet_only=true
            log_info "Tailnet-only access: node key never expires, SSH will be closed publicly"
        else
            log_error "SSH_TAILNET_ONLY=true but this node's Tailscale key can still expire"
            log_error "refusing to close public SSH - you would be locked out when it expires"
            log_error "Fix: sudo tailscale up --advertise-tags=${TAILSCALE_TAGS}"
            log_error "     (or disable key expiry for this machine in the admin console)"
        fi
    fi

    if [[ "${tailnet_only}" == "true" ]]; then
        # SSH and Mosh on the tailnet interface only. Mosh follows SSH because
        # a mosh session is bootstrapped over SSH.
        sudo ufw allow in on tailscale0 to any port "${SSH_PORT}" proto tcp comment 'SSH (tailnet only)'
        sudo ufw allow in on tailscale0 to any port "${MOSH_PORT_START}:${MOSH_PORT_END}" proto udp comment 'Mosh (tailnet only)'
        # node_exporter has no auth: tailnet interface only, never the public one
        sudo ufw allow in on tailscale0 to any port 9100 proto tcp comment 'node_exporter (tailnet only)'
        # ntfy serves the phones over the tailnet: never the public interface
        sudo ufw allow in on tailscale0 to any port 2586 proto tcp comment 'ntfy (tailnet only)'
        sudo ufw --force enable
        log_ok "Firewall configured - SSH/Mosh reachable on the tailnet only"
        log_warn "Public SSH is CLOSED. Break-glass access is the Hetzner web console;"
        log_warn "make sure you can log in there before you need it."
        return 0
    fi

    # SSH with optional rate limiting (blocks after 6 connections in 30 seconds from same IP)
    if [[ "${UFW_RATE_LIMIT:-true}" == "true" ]]; then
        sudo ufw limit "${SSH_PORT}"/tcp comment 'SSH with rate limiting'
        log_info "SSH rate limiting enabled (6 connections/30s threshold)"
    else
        sudo ufw allow "${SSH_PORT}"/tcp comment 'SSH'
    fi

    # Mosh UDP ports
    sudo ufw allow "${MOSH_PORT_START}:${MOSH_PORT_END}"/udp comment 'Mosh'

    # node_exporter has no auth: tailnet interface only, never the public one
    sudo ufw allow in on tailscale0 to any port 9100 proto tcp comment 'node_exporter (tailnet only)'

    # ntfy serves the phones over the tailnet: never the public interface
    sudo ufw allow in on tailscale0 to any port 2586 proto tcp comment 'ntfy (tailnet only)'

    # Enable firewall
    sudo ufw --force enable

    log_ok "Firewall configured (SSH: ${SSH_PORT}, Mosh: ${MOSH_PORT_START}-${MOSH_PORT_END})"
}

#===============================================================================
# Fail2Ban Configuration
#===============================================================================
configure_fail2ban() {
    log_info "Configuring Fail2Ban..."

    sudo tee /etc/fail2ban/jail.local >/dev/null <<F2BEOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
F2BEOF

    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban

    log_ok "Fail2Ban configured for port ${SSH_PORT}"
}

#===============================================================================
# Install and Configure GeoIP Blocking (geoip-shell)
#===============================================================================
install_geoip_shell() {
    if [[ "${GEOIP_ENABLED:-true}" != "true" ]]; then
        log_info "GeoIP blocking disabled (GEOIP_ENABLED=false)"
        return 0
    fi

    log_info "Installing geoip-shell for country-based SSH blocking..."

    # Check if already installed
    if command -v geoip-shell &>/dev/null; then
        log_ok "geoip-shell already installed"
        log_info "Updating GeoIP whitelist to: ${GEOIP_COUNTRIES}"
        # Update countries if already configured
        sudo geoip-shell configure -z -m whitelist -c "${GEOIP_COUNTRIES//,/ }" -i all -l none 2>/dev/null || true
        return 0
    fi

    # Install dependencies
    log_info "Installing geoip-shell dependencies..."
    sudo apt-get install -y -qq curl wget gawk grep sed coreutils

    # Clone geoip-shell
    local GEOIP_INSTALL_DIR="/tmp/geoip-shell-install"
    rm -rf "${GEOIP_INSTALL_DIR}"

    log_info "Downloading geoip-shell..."
    if ! git clone --depth 1 https://github.com/friendly-bits/geoip-shell.git "${GEOIP_INSTALL_DIR}"; then
        log_error "Failed to clone geoip-shell repository"
        log_warn "Continuing without GeoIP blocking - Tailscale provides backup access"
        return 1
    fi

    # Run installer in non-interactive mode
    log_info "Installing geoip-shell..."

    # Install with -z for non-interactive mode
    if ! sudo sh "${GEOIP_INSTALL_DIR}/geoip-shell-install.sh" -z; then
        log_error "geoip-shell installation failed"
        log_warn "Continuing without GeoIP blocking - Tailscale provides backup access"
        rm -rf "${GEOIP_INSTALL_DIR}"
        return 1
    fi

    rm -rf "${GEOIP_INSTALL_DIR}"

    # Verify installation
    if ! command -v geoip-shell &>/dev/null; then
        log_error "geoip-shell installation verification failed"
        log_warn "Continuing without GeoIP blocking - Tailscale provides backup access"
        return 1
    fi

    log_ok "geoip-shell installed successfully"

    # Configure whitelist mode with specified countries
    # Countries should be space-separated for geoip-shell
    local countries_spaced="${GEOIP_COUNTRIES//,/ }"
    log_info "Configuring whitelist for countries: ${countries_spaced}"

    # -i all: apply to all interfaces
    # -l none: no LAN subnets (cloud server)
    if ! sudo geoip-shell configure -z -m whitelist -c "${countries_spaced}" -i all -l none; then
        log_error "geoip-shell configuration failed"
        log_warn "Continuing without GeoIP blocking - Tailscale provides backup access"
        return 1
    fi

    # Set up automatic weekly updates
    log_info "Configuring automatic GeoIP database updates..."
    sudo geoip-shell configure -z -s "1 4 * * 0" 2>/dev/null || true

    sudo geoip-shell status 2>/dev/null || true

    log_ok "GeoIP blocking configured (whitelist: ${GEOIP_COUNTRIES})"
}

#===============================================================================
# Install Tailscale VPN
#===============================================================================
install_tailscale() {
    log_info "Installing Tailscale..."

    if command -v tailscale &>/dev/null; then
        # shellcheck disable=SC2312
        log_ok "Tailscale already installed: $(tailscale version | head -1)"
        return 0
    fi

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Enable and start the service
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled

    log_ok "Tailscale installed"
    log_warn "╔════════════════════════════════════════════════════════════════════╗"
    log_warn "║  Authenticate after bootstrap:                                     ║"
    log_warn "║                                                                    ║"
    log_warn "║    sudo tailscale up --advertise-tags=${TAILSCALE_TAGS} --accept-dns"
    log_warn "║                                                                    ║"
    log_warn "║  --accept-dns lets ${GITLAB_HOST} resolve (tailnet split DNS).      "
    log_warn "║                                                                    ║"
    log_warn "║  Do NOT pass --ssh: Tailscale SSH intercepts port 22 on the        ║"
    log_warn "║  tailnet and demands an interactive browser check, which breaks    ║"
    log_warn "║  headless and scripted access. Plain sshd over the tailnet IP      ║"
    log_warn "║  keeps working with your existing key.                             ║"
    log_warn "║                                                                    ║"
    log_warn "║  --advertise-tags makes the node tailnet-owned so its key never    ║"
    log_warn "║  expires. Without a tag the key expires after 180 days and the     ║"
    log_warn "║  server drops off the tailnet with no warning.                     ║"
    log_warn "║                                                                    ║"
    log_warn "║  The tag must first exist in the tailnet ACL (tagOwners). If you   ║"
    log_warn "║  authenticate untagged, disable key expiry for this machine in     ║"
    log_warn "║  the admin console instead.                                        ║"
    log_warn "╚════════════════════════════════════════════════════════════════════╝"
}

#===============================================================================
# Monitoring: node_exporter (Prometheus metrics, tailnet-only)
#===============================================================================
# Prometheus on the NAS scrapes this node over Tailscale (fxmartin/nix-install
# Epic-15 "Fleet Cockpit"). node_exporter has NO authentication: the unit binds
# to the Tailscale IP only, configure_firewall opens 9100 on tailscale0 only,
# and the Tailscale ACL decides which node may scrape. The installer lives in
# scripts/install-node-exporter.sh so it can be run and tested on its own.

# The previous agent (Beszel, inbound KEY mode on 45876) expected a hub that
# is not part of the target design and crash-looped for months. Existing
# servers still carry it: remove it entirely rather than leave it optional.
remove_beszel_agent() {
    local unit="${HOME}/.config/systemd/user/beszel-agent.service"
    local removed=false
    local leftover

    if [[ -f "${unit}" ]]; then
        systemctl --user disable --now beszel-agent 2>/dev/null || true
        rm -f "${unit}"
        systemctl --user daemon-reload 2>/dev/null || true
        removed=true
    fi

    for leftover in "${HOME}/.local/bin/beszel-agent" "${HOME}/.config/beszel-agent.env"; do
        if [[ -e "${leftover}" ]]; then
            rm -f "${leftover}"
            removed=true
        fi
    done

    if [[ "${removed}" == "true" ]]; then
        log_ok "Legacy Beszel agent removed"
    else
        log_info "No legacy Beszel agent present"
    fi
}

install_node_exporter() {
    log_info "Installing node_exporter (tailnet-only Prometheus metrics)..."

    local installer="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/scripts/install-node-exporter.sh"
    if [[ ! -f "${installer}" ]]; then
        log_warn "scripts/install-node-exporter.sh not found under ${REPO_CLONE_DIR} - skipping node_exporter"
        return 0
    fi

    # Monitoring is not worth aborting a bootstrap over: the installer is
    # idempotent, so a transient download failure is fixed by re-running it.
    if bash "${installer}"; then
        log_ok "node_exporter running on <tailscale-ip>:9100 (Prometheus on the NAS scrapes it)"
    else
        log_warn "node_exporter installation failed (non-critical) - re-run: bash ${installer}"
    fi
}

# ntfy carries acm's alerts to the phones (acm Epic-17, P2). Same security model
# as node_exporter; the installer lives in scripts/install-ntfy.sh.
install_ntfy() {
    log_info "Installing ntfy (tailnet-only push server)..."

    local installer="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/scripts/install-ntfy.sh"
    if [[ ! -f "${installer}" ]]; then
        log_warn "scripts/install-ntfy.sh not found under ${REPO_CLONE_DIR} - skipping ntfy"
        return 0
    fi

    # Not worth aborting a bootstrap over: the installer is idempotent.
    if bash "${installer}"; then
        log_ok "ntfy running on <tailscale-ip>:2586"
    else
        log_warn "ntfy installation failed (non-critical) - re-run: bash ${installer}"
    fi
}

#===============================================================================
# Install and Configure auditd (System Auditing)
#===============================================================================
install_auditd() {
    log_info "Installing and configuring auditd..."

    # Check if already installed
    if dpkg -l auditd &>/dev/null; then
        log_ok "auditd already installed"
    else
        sudo apt-get install -y -qq auditd audispd-plugins
        log_ok "auditd installed"
    fi

    # Enable and start service
    sudo systemctl enable auditd
    sudo systemctl start auditd

    # Create audit rules for security monitoring
    local AUDIT_RULES="/etc/audit/rules.d/security.rules"
    if [[ ! -f "${AUDIT_RULES}" ]]; then
        sudo tee "${AUDIT_RULES}" >/dev/null <<'AUDITEOF'
# Security audit rules - Generated by bootstrap-dev-server.sh

# Monitor identity files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Monitor sudo configuration
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d/ -p wa -k sshd

# Monitor cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# Monitor login configuration
-w /etc/login.defs -p wa -k login
-w /etc/pam.d/ -p wa -k pam
AUDITEOF

        sudo systemctl restart auditd
        log_ok "auditd rules configured"
    else
        log_ok "auditd rules already configured"
    fi
}

#===============================================================================
# Harden Kernel Parameters (sysctl)
#===============================================================================
harden_sysctl() {
    log_info "Hardening kernel parameters..."

    local SYSCTL_FILE="/etc/sysctl.d/99-security-hardening.conf"

    if [[ -f "${SYSCTL_FILE}" ]]; then
        log_ok "Sysctl hardening already configured"
        return 0
    fi

    sudo tee "${SYSCTL_FILE}" >/dev/null <<'SYSCTLEOF'
# Security hardening - Generated by bootstrap-dev-server.sh

# Disable ICMP redirects (MITM protection)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignore ICMP redirects (already set but ensuring)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Protect against SYN flood attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Log suspicious packets (martians)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Enable reverse path filtering (strict mode)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Harden BPF JIT compiler
net.core.bpf_jit_harden = 2

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Restrict dmesg access to root
kernel.dmesg_restrict = 1

# Restrict ptrace scope
kernel.yama.ptrace_scope = 1
SYSCTLEOF

    # Apply sysctl settings
    sudo sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1

    log_ok "Kernel parameters hardened"
}

#===============================================================================
# Harden PAM Configuration
#===============================================================================
harden_pam() {
    log_info "Hardening PAM configuration..."

    local PAM_AUTH="/etc/pam.d/common-auth"

    # Remove nullok option (allows empty passwords)
    if grep -q "pam_unix.so nullok" "${PAM_AUTH}" 2>/dev/null; then
        sudo sed -i 's/pam_unix.so nullok/pam_unix.so/' "${PAM_AUTH}"
        log_ok "Removed nullok from PAM (empty passwords disallowed)"
    else
        log_ok "PAM nullok already removed"
    fi
}

#===============================================================================
# Setup Daily Security Report
#===============================================================================
setup_security_report() {
    log_info "Setting up daily security report..."

    local REPORT_SCRIPT="/usr/local/bin/security-report.sh"
    local MSMTP_CONFIG="/root/.msmtprc"
    local REPORT_CONFIG="/etc/security-report.conf"
    local smtp_configured=false
    local report_email="mail@fxmartin.me"

    # Check if SMTP already configured
    if [[ -f "${MSMTP_CONFIG}" ]] && [[ -f "${REPORT_CONFIG}" ]]; then
        log_ok "SMTP configuration already exists"
        smtp_configured=true
        # Read existing report email
        report_email=$(grep "^REPORT_EMAIL=" "${REPORT_CONFIG}" 2>/dev/null | cut -d'"' -f2 || echo "mail@fxmartin.me")
    else
        # Prompt for email configuration
        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "📧 Security Report Email Configuration"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Collect email configuration with Gandi defaults
        local smtp_host smtp_port smtp_user smtp_pass

        printf "  SMTP Host [mail.gandi.net]: "
        read -r smtp_host </dev/tty || smtp_host=""
        smtp_host="${smtp_host:-mail.gandi.net}"

        printf "  SMTP Port [587]: "
        read -r smtp_port </dev/tty || smtp_port=""
        smtp_port="${smtp_port:-587}"

        printf "  From Email [dev-server@fxmartin.me]: "
        read -r smtp_user </dev/tty || smtp_user=""
        smtp_user="${smtp_user:-dev-server@fxmartin.me}"

        printf "  SMTP Password: "
        read -rs smtp_pass </dev/tty || smtp_pass=""
        echo ""

        if [[ -z "${smtp_pass}" ]]; then
            log_warn "No password provided - email sending will not work"
            log_warn "Configure later: sudo nano /root/.msmtprc"
        else
            printf "  Report recipient [mail@fxmartin.me]: "
            read -r report_email </dev/tty || report_email=""
            report_email="${report_email:-mail@fxmartin.me}"

            echo ""

            # msmtp is installed via Nix flake (pkgs.msmtp in flake.nix)
            # The security report script will use the Nix-provided msmtp

            # Create root msmtp config
            log_info "Creating SMTP configuration..."
            sudo tee "${MSMTP_CONFIG}" >/dev/null <<MSMTPEOF
# msmtp configuration for security reports
# Generated by bootstrap-dev-server.sh

defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           ${smtp_host}
port           ${smtp_port}
from           ${smtp_user}
user           ${smtp_user}
password       ${smtp_pass}
MSMTPEOF
            sudo chmod 600 "${MSMTP_CONFIG}"

            # Save report config
            sudo tee "${REPORT_CONFIG}" >/dev/null <<CONFEOF
# Security report configuration
REPORT_EMAIL="${report_email}"
CONFEOF
            sudo chmod 600 "${REPORT_CONFIG}"

            smtp_configured=true
            log_ok "SMTP configuration created"
        fi
    fi

    # Create the security report script
    log_info "Creating security report script..."
    sudo tee "${REPORT_SCRIPT}" >/dev/null <<'REPORTEOF'
#!/usr/bin/env bash
# ABOUTME: Daily security report script - sends email summary of security events
# Generated by bootstrap-dev-server.sh
# Usage: security-report.sh [--test] [--stdout]
#   --test   : Send test email only
#   --stdout : Print report to stdout instead of emailing

set -euo pipefail

# Find msmtp - try multiple methods
find_msmtp() {
    # Method 1: Check if msmtp is in PATH (works if nix profile is active)
    if command -v msmtp &>/dev/null; then
        command -v msmtp
        return 0
    fi

    # Method 2: Source Nix daemon profile and check again
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        if command -v msmtp &>/dev/null; then
            command -v msmtp
            return 0
        fi
    fi

    # Method 3: Search Nix store (deeper search)
    local found
    found=$(find /nix/store -maxdepth 3 -name "msmtp" -path "*/bin/msmtp" -type f 2>/dev/null | head -1)
    if [[ -n "${found}" ]]; then
        echo "${found}"
        return 0
    fi

    return 1
}

MSMTP_BIN=$(find_msmtp) || {
    echo "ERROR: msmtp not found. Run 'dev' to install via Nix flake." >&2
    exit 1
}

# Parse arguments
TEST_MODE=false
STDOUT_MODE=false
for arg in "$@"; do
    case "${arg}" in
        --test) TEST_MODE=true ;;
        --stdout) STDOUT_MODE=true ;;
    esac
done

# Load config
if [[ ! -f /etc/security-report.conf ]]; then
    echo "ERROR: /etc/security-report.conf not found" >&2
    exit 1
fi
source /etc/security-report.conf

if [[ -z "${REPORT_EMAIL:-}" ]]; then
    echo "ERROR: REPORT_EMAIL not set in /etc/security-report.conf" >&2
    exit 1
fi

HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d')
YESTERDAY=$(date -d 'yesterday' '+%b %d' 2>/dev/null || date -v-1d '+%b %d')

# Build report
REPORT="SECURITY REPORT - ${HOSTNAME} - ${DATE}
==========================================

"

# Fail2Ban stats
if command -v fail2ban-client &>/dev/null; then
    BANNED_24H=$(grep -c "Ban " /var/log/fail2ban.log 2>/dev/null | tail -1 || echo "0")
    CURRENT_BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")
    BANNED_IPS=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | cut -d: -f2 | xargs || echo "none")

    REPORT+="FAIL2BAN
  Banned (24h): ${BANNED_24H}
  Currently banned: ${CURRENT_BANNED}
  IPs: ${BANNED_IPS}

"
fi

# SSH stats from auth.log
if [[ -f /var/log/auth.log ]]; then
    FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo "0")
    INVALID=$(grep -c "Invalid user" /var/log/auth.log 2>/dev/null || echo "0")
    ACCEPTED=$(grep -c "Accepted" /var/log/auth.log 2>/dev/null || echo "0")
    ACCEPTED_DETAILS=$(grep -E "sshd\[[0-9]+\]: Accepted (publickey|password) for" /var/log/auth.log 2>/dev/null | tail -3 | awk '{print $7"@"$9}' | tr '\n' ' ' || echo "")

    REPORT+="SSH ATTEMPTS
  Failed: ${FAILED}
  Invalid users: ${INVALID}
  Accepted: ${ACCEPTED}
  Recent: ${ACCEPTED_DETAILS:-none}

"
fi

# UFW stats
if [[ -f /var/log/ufw.log ]]; then
    BLOCKED=$(grep -c "\[UFW BLOCK\]" /var/log/ufw.log 2>/dev/null || echo "0")
    REPORT+="FIREWALL (UFW)
  Blocked connections: ${BLOCKED}

"
fi

# Audit events
if command -v ausearch &>/dev/null; then
    PAM_FAILURES=$(ausearch -m USER_ERR -ts yesterday 2>/dev/null | grep -c "res=failed" || echo "0")
    SUDO_USAGE=$(ausearch -m USER_CMD -ts yesterday 2>/dev/null | grep -c "sudo" || echo "0")
    CONFIG_CHANGES=$(ausearch -k sshd -k sudoers -ts yesterday 2>/dev/null | grep -c "type=" || echo "0")

    REPORT+="AUDIT EVENTS (24h)
  PAM failures: ${PAM_FAILURES}
  Sudo usage: ${SUDO_USAGE}
  Config changes: ${CONFIG_CHANGES}

"
fi

# System info
UPTIME=$(uptime -p)
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
DISK=$(df -h / | tail -1 | awk '{print $5 " used (" $4 " free)"}')

REPORT+="SYSTEM
  Uptime: ${UPTIME}
  Load: ${LOAD}
  Disk: ${DISK}
"

# Handle test mode - just send a simple test email
if [[ "${TEST_MODE}" == "true" ]]; then
    REPORT="TEST EMAIL from ${HOSTNAME}

This is a test message from security-report.sh
If you received this, email sending is working correctly.

Date: ${DATE}
Time: $(date '+%H:%M:%S')
"
fi

# Handle stdout mode - print instead of email
if [[ "${STDOUT_MODE}" == "true" ]]; then
    echo "${REPORT}"
    exit 0
fi

# Verify msmtp config exists
if [[ ! -f /root/.msmtprc ]]; then
    echo "ERROR: /root/.msmtprc not found" >&2
    exit 1
fi

# Send email using msmtp from Nix store
# Construct proper email with headers
FROM_ADDR=$(grep "^from" /root/.msmtprc 2>/dev/null | awk '{print $2}' || echo "security@localhost")

SUBJECT="[${HOSTNAME}] Security Report - ${DATE}"
[[ "${TEST_MODE}" == "true" ]] && SUBJECT="[${HOSTNAME}] TEST - Security Report"

{
    echo "From: Security Report <${FROM_ADDR}>"
    echo "To: ${REPORT_EMAIL}"
    echo "Subject: ${SUBJECT}"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    echo "${REPORT}"
} | "${MSMTP_BIN}" "${REPORT_EMAIL}"

echo "Security report sent to ${REPORT_EMAIL}"
REPORTEOF

    sudo chmod 755 "${REPORT_SCRIPT}"
    log_ok "Security report script created"

    # Setup cron job (7am Europe/Paris) - ALWAYS create this regardless of SMTP config
    log_info "Setting up cron job (7am Europe/Paris)..."
    local CRON_JOB="0 7 * * * TZ=Europe/Paris ${REPORT_SCRIPT} 2>&1 | logger -t security-report"

    # Add to root crontab if not already present
    if ! sudo crontab -l 2>/dev/null | grep -q "security-report.sh"; then
        if (
            sudo crontab -l 2>/dev/null || true
            echo "${CRON_JOB}"
        ) | sudo crontab -; then
            # Verify it was actually added
            if sudo crontab -l 2>/dev/null | grep -q "security-report.sh"; then
                log_ok "Cron job added successfully"
            else
                log_error "Cron job creation appeared to succeed but job not found"
                log_warn "Manually add: ${CRON_JOB}"
            fi
        else
            log_error "Failed to add cron job"
            log_warn "Manually run: (sudo crontab -l; echo '${CRON_JOB}') | sudo crontab -"
        fi
    else
        log_ok "Cron job already exists"
    fi

    # Summary
    log_ok "Security report configured"
    log_info "  Script: ${REPORT_SCRIPT}"
    log_info "  Schedule: 7am Europe/Paris daily"
    if [[ "${smtp_configured}" == true ]]; then
        log_info "  Recipient: ${report_email}"
        log_info "  Email: Configured ✓"
    else
        log_warn "  Email: NOT configured (run --stdout to view report)"
        log_warn "  Configure SMTP: sudo nano /root/.msmtprc"
    fi
    echo ""
    log_info "  Test commands:"
    log_info "    sudo ${REPORT_SCRIPT} --stdout   # Preview report"
    if [[ "${smtp_configured}" == true ]]; then
        log_info "    sudo ${REPORT_SCRIPT} --test     # Send test email"
        log_info "    sudo ${REPORT_SCRIPT}            # Send full report"
    fi
}

#===============================================================================
# Clean Old Kernels
#===============================================================================
clean_old_kernels() {
    log_info "Cleaning old kernels..."

    # Count installed kernels
    local kernel_count
    kernel_count=$(dpkg -l 'linux-image-*' 2>/dev/null | grep -c '^ii' || echo "0")

    if [[ "${kernel_count}" -gt 1 ]]; then
        sudo apt-get autoremove --purge -y -qq
        log_ok "Old kernels removed"
    else
        log_ok "No old kernels to remove"
    fi
}

#===============================================================================
# Configure Update Notifications (runs after email setup)
#===============================================================================
configure_update_notifications() {
    log_info "Configuring update email notifications..."

    local REPORT_CONFIG="/etc/security-report.conf"
    local NOTIFY_SCRIPT="/usr/local/bin/nix-update-notify.sh"

    # Check if email is configured
    if [[ ! -f "${REPORT_CONFIG}" ]]; then
        log_warn "Email not configured - skipping update notifications"
        log_info "Run bootstrap again after configuring email to enable notifications"
        return 0
    fi

    # Read email from config
    local report_email
    report_email=$(sudo grep "^REPORT_EMAIL=" "${REPORT_CONFIG}" 2>/dev/null | cut -d'"' -f2)
    if [[ -z "${report_email}" ]]; then
        log_warn "No email found in config - skipping update notifications"
        return 0
    fi

    # Update unattended-upgrades to send email on error/changes
    log_info "Adding email notification to unattended-upgrades..."
    sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-email >/dev/null <<EMAILEOF
// Email notification for unattended-upgrades
Unattended-Upgrade::Mail "${report_email}";
Unattended-Upgrade::MailReport "only-on-error";
Unattended-Upgrade::Sender "dev-server@$(hostname -f)";
EMAILEOF

    # Create Nix update notification script
    log_info "Creating Nix update notification script..."
    sudo tee "${NOTIFY_SCRIPT}" >/dev/null <<'NOTIFYEOF'
#!/bin/bash
# Nix flake update notification script
# Sends email summary after weekly Nix updates

set -euo pipefail

REPORT_CONFIG="/etc/security-report.conf"
MSMTP_CONFIG="/root/.msmtprc"
HOSTNAME=$(hostname -f)
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Read email from config
if [[ -f "${REPORT_CONFIG}" ]]; then
    REPORT_EMAIL=$(grep "^REPORT_EMAIL=" "${REPORT_CONFIG}" 2>/dev/null | cut -d'"' -f2)
fi

if [[ -z "${REPORT_EMAIL:-}" ]] || [[ ! -f "${MSMTP_CONFIG}" ]]; then
    echo "Email not configured, skipping notification"
    exit 0
fi

# Get update status from arguments
STATUS="${1:-unknown}"
DETAILS="${2:-No details available}"

# Determine subject based on status
if [[ "${STATUS}" == "success" ]]; then
    SUBJECT="[${HOSTNAME}] Nix Update: Success"
    ICON="✅"
else
    SUBJECT="[${HOSTNAME}] Nix Update: Failed"
    ICON="❌"
fi

# Send email
/nix/var/nix/profiles/default/bin/msmtp -C "${MSMTP_CONFIG}" -t <<MAILEOF
To: ${REPORT_EMAIL}
From: dev-server@${HOSTNAME}
Subject: ${SUBJECT}
Content-Type: text/plain; charset=utf-8

${ICON} Nix Flake Update Report
═══════════════════════════════════════════

Server:    ${HOSTNAME}
Date:      ${DATE}
Status:    ${STATUS}

Details:
${DETAILS}

───────────────────────────────────────────
Automated update via nix-flake-update.timer
MAILEOF

echo "Notification sent to ${REPORT_EMAIL}"
NOTIFYEOF

    sudo chmod +x "${NOTIFY_SCRIPT}"

    # Update the nix-flake-update service to include notification
    local SERVICE_FILE="/etc/systemd/system/nix-flake-update.service"
    if [[ -f "${SERVICE_FILE}" ]]; then
        log_info "Updating Nix update service with email notification..."

        local FLAKE_DIR="/home/${DEV_USER}/.config/nix-dev-env"
        local REPO_DIR="/home/${DEV_USER}/.local/share/bootstrap-dev-server"

        # Regenerate the notification-enhanced unit and rewrite it only on
        # content drift, so fixes propagate to already-provisioned servers
        # (the previous marker grep froze the first-ever version in place).
        if install_systemd_unit "${SERVICE_FILE}" <<SERVICEEOF; then
[Unit]
Description=Update Nix flake packages
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${DEV_USER}
Environment="HOME=/home/${DEV_USER}"
Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin"

# The repository is the only source of flake.lock: hard-reset the checkout to
# origin/main (logging any local diff or commits it discards), sync submodules,
# build dev-env with lock updates refused, and only on success upgrade the
# profile, then converge the sdlc controller to the pinned tag (a failure or
# refusal only warns: the profile upgrade already succeeded). A failed fetch or
# build leaves the previous profile in place and
# records status=failed so ExecStopPost's notification reports the real outcome
# instead of always "success".
ExecStart=/bin/bash -c 'cd ${REPO_DIR} || exit 1; OUTPUT=\$( (git fetch --quiet origin && git diff --stat HEAD | sed "s/^/[discarded] /" && git log --oneline origin/main..HEAD | sed "s/^/[discarded commit] /" && git reset --hard --quiet origin/main && { git submodule update --recursive || echo "[warn] submodule update failed"; } && git log -1 --oneline | sed "s/^/[applied] /" && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix build ${FLAKE_DIR}#dev-env --no-update-lock-file --no-link && nix profile upgrade dev-env && { bash ${REPO_DIR}/scripts/install-sdlc-controller.sh || echo "[warn] sdlc controller not converged to the pinned tag; re-run: bash ${REPO_DIR}/scripts/install-sdlc-controller.sh"; }) 2>&1 ); if [ \$? -eq 0 ]; then echo "\$OUTPUT" > /tmp/nix-update-output.txt; echo "success" > /tmp/nix-update-status.txt; else echo "\$OUTPUT" > /tmp/nix-update-output.txt; echo "failed" > /tmp/nix-update-status.txt; exit 1; fi'

# Send notification (runs as root to access msmtp config)
ExecStopPost=/bin/bash -c 'sudo ${NOTIFY_SCRIPT} "\$(cat /tmp/nix-update-status.txt 2>/dev/null || echo unknown)" "\$(cat /tmp/nix-update-output.txt 2>/dev/null || echo No output)"'
SERVICEEOF
            sudo systemctl daemon-reload
            log_ok "Nix update service updated with email notification"
        else
            log_ok "Nix update notification already configured"
        fi
    fi

    log_ok "Update notifications configured (email: ${report_email})"
}

#===============================================================================
# Install Nix (Determinate Systems Installer)
#===============================================================================
install_nix() {
    log_info "Installing Nix..."

    if command -v nix &>/dev/null; then
        # shellcheck disable=SC2312
        log_ok "Nix already installed: $(nix --version)"
        return 0
    fi

    # Determinate Systems installer - enables flakes by default
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
        sh -s -- install --no-confirm

    # Source Nix in current shell
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck source=/dev/null
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    # shellcheck disable=SC2312
    log_ok "Nix installed: $(nix --version)"
}

#===============================================================================
# Create Dev Environment Flake (symlink to repo)
#===============================================================================
create_dev_flake() {
    log_info "Creating dev environment flake symlink..."

    local FLAKE_DIR="${HOME}/.config/nix-dev-env"
    local SOURCE_DIR="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}"

    # Verify source directory exists
    if [[ ! -d "${SOURCE_DIR}" ]]; then
        log_error "Source directory not found: ${SOURCE_DIR}"
        log_error "Ensure clone_bootstrap_repo() was called first"
        return 1
    fi

    # Verify flake.nix exists in source
    if [[ ! -f "${SOURCE_DIR}/flake.nix" ]]; then
        log_error "flake.nix not found in: ${SOURCE_DIR}"
        return 1
    fi

    # Remove existing directory/symlink if present
    if [[ -L "${FLAKE_DIR}" ]]; then
        log_info "Removing existing symlink..."
        rm "${FLAKE_DIR}"
    elif [[ -d "${FLAKE_DIR}" ]]; then
        log_info "Backing up existing directory to ${FLAKE_DIR}.backup..."
        local backup_suffix
        backup_suffix=$(date +%Y%m%d%H%M%S)
        mv "${FLAKE_DIR}" "${FLAKE_DIR}.backup.${backup_suffix}"
    fi

    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "${FLAKE_DIR}")"

    # Create symlink
    if ! ln -s "${SOURCE_DIR}" "${FLAKE_DIR}"; then
        log_error "Failed to create symlink: ${FLAKE_DIR} -> ${SOURCE_DIR}"
        return 1
    fi

    log_ok "Dev flake symlinked: ${FLAKE_DIR} -> ${SOURCE_DIR}"
    log_info "Updates to repo will be reflected immediately (after re-entering dev shell)"
}

#===============================================================================
# Shell Integration
#===============================================================================
setup_shell_integration() {
    log_info "Setting up shell integration..."

    local FLAKE_DIR="${HOME}/.config/nix-dev-env"
    local BASHRC="${HOME}/.bashrc"
    local MARKER="# >>> nix-dev-env >>>"
    local rc_lib="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/rc-block.sh"

    if [[ ! -f "${rc_lib}" ]]; then
        log_error "lib/rc-block.sh not found under ${REPO_CLONE_DIR}"
        return 1
    fi
    # shellcheck disable=SC1091  # Path is dynamically built from vars
    # shellcheck source=lib/rc-block.sh
    source "${rc_lib}"

    # Regenerate the block on every run and rewrite it only on content drift, so
    # dev-update fixes reach already-provisioned servers.
    if ! write_rc_block "${BASHRC}" "${MARKER}" "# <<< nix-dev-env <<<" <<SHELLEOF; then
${MARKER}
# Nix daemon
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Auto-enter dev environment
dev() {
    nix develop "${FLAKE_DIR}#\${1:-default}" -c \${SHELL}
}

# Shortcut aliases
alias d='dev'
alias dm='dev minimal'
alias dp='dev python'

# Update dev environment
# - The repository is the only source of flake.lock: hard-resets the checkout
#   to origin/main (flake.nix is symlinked, so the checkout IS the flake),
#   builds dev-env, and only then upgrades the profile
# - Never bumps the lock itself; lock updates arrive through merge requests
dev-update() {
    echo "🔄 Updating dev environment..."
    local REPO_DIR="\${HOME}/.local/share/bootstrap-dev-server"
    local FLAKE_DIR="\${HOME}/.config/nix-dev-env"

    if [[ ! -d "\${REPO_DIR}/.git" ]]; then
        echo "❌ No checkout at \${REPO_DIR}"
        return 1
    fi

    echo "📥 Fetching origin..."
    (cd "\${REPO_DIR}" && git fetch --quiet origin) || {
        echo "❌ Failed to fetch origin - nothing applied"
        return 1
    }

    # Log what the reset throws away so nothing vanishes silently
    local discarded
    discarded="\$(cd "\${REPO_DIR}" && git diff --stat HEAD)"
    if [[ -n "\${discarded}" ]]; then
        echo "⚠️  Discarding local changes:"
        echo "\${discarded}"
    fi
    discarded="\$(cd "\${REPO_DIR}" && git log --oneline origin/main..HEAD)"
    if [[ -n "\${discarded}" ]]; then
        echo "⚠️  Discarding local commits:"
        echo "\${discarded}"
    fi

    (cd "\${REPO_DIR}" && git reset --hard --quiet origin/main) || {
        echo "❌ Failed to reset to origin/main"
        return 1
    }

    # Update submodules (Claude Code configs from nix-install)
    (cd "\${REPO_DIR}" && git submodule update --recursive) || echo "⚠️  Failed to update submodules (continuing anyway)"

    # --no-update-lock-file: a flake.nix the committed lock does not cover fails
    # here instead of locking on the box
    echo "🔨 Building dev-env..."
    nix build "\${FLAKE_DIR}#dev-env" --no-update-lock-file --no-link || {
        echo "❌ Build failed - profile left unchanged"
        return 1
    }
    nix profile upgrade dev-env || {
        echo "❌ nix profile upgrade dev-env failed"
        return 1
    }

    # Converge the sdlc controller to the tag pinned in config/versions.env. The
    # profile upgrade already succeeded, so a failure or refusal only warns.
    local sdlc_installer="\${REPO_DIR}/scripts/install-sdlc-controller.sh"
    if [[ ! -f "\${sdlc_installer}" ]] || ! bash "\${sdlc_installer}"; then
        echo "⚠️  sdlc controller not converged to the pinned tag; re-run: bash \${sdlc_installer}"
    fi

    echo ""
    echo "✅ Dev environment updated to \$(git -C "\${REPO_DIR}" log -1 --oneline)"
    echo "   Exit and run 'dev' to use new packages"
}

# Quick Claude access (runs in minimal env if not in dev shell)
claude-quick() {
    if command -v claude &>/dev/null; then
        claude "\$@"
    else
        nix run "${FLAKE_DIR}#minimal" -- claude "\$@"
    fi
}

# Attach to the herdr server on an interactive ssh login
# - Lives here because bash is the login shell on a provisioned server (nothing runs
#   chsh) and ~/.profile sources this file. Same guard as the ~/.zshrc block, see there
# - The \$- check is for \`ssh -t dev <cmd>\`: it has an SSH_TTY, and sshd's bash reads this
#   file even though it is not interactive
herdr_login_attach() {
    [[ -n "\${SSH_TTY:-}" && -z "\${SSH_ORIGINAL_COMMAND:-}" ]] || return 0
    [[ -z "\${HERDR_ENV:-}" && -z "\${TMUX:-}" ]] || return 0
    [[ -z "\${NO_HERDR:-}" || "\${NO_HERDR}" == "0" ]] || return 0
    command -v herdr >/dev/null 2>&1 || return 0
    export NO_HERDR=1
    herdr
    return 0
}
case \$- in *i*) herdr_login_attach ;; esac
# <<< nix-dev-env <<<
SHELLEOF
        log_ok "Shell integration already configured"
        return 0
    fi

    log_ok "Shell integration configured"
    log_info "Run 'source ~/.bashrc' or reconnect to activate"
}

#===============================================================================
# Install the Dev Toolset as the User's Default Nix Profile
#===============================================================================
# flake.nix exposes packages.<system>.dev-env: a buildEnv of the exact package
# list devShells.default uses. Installing it as the profile puts the toolset
# on PATH in every context (login, `ssh dev '<cmd>'`, systemd user services,
# herdr panes), not only inside `dev`.
#
# The profile must hold only what the flake declares. Strays installed by hand
# (e.g. a herdr 0.9.1 package) are removed before the install - they would
# otherwise collide with dev-env's own bin/ entries and fail it. But only once
# dev-env has built: a failed build (bad token, broken input, no network) must
# leave the existing profile untouched rather than strip its tools.
install_dev_profile() {
    log_info "Installing the dev toolset as the default Nix profile..."

    local FLAKE_DIR="${HOME}/.config/nix-dev-env"

    # Source Nix if not already available
    if ! command -v nix &>/dev/null; then
        if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
            # shellcheck source=/dev/null
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
    fi

    local profile_json
    if ! profile_json="$(nix profile list --json)"; then
        log_error "Could not list the Nix profile"
        return 1
    fi

    # Build first so nothing is removed unless dev-env can actually be installed.
    if ! nix build "${FLAKE_DIR}#dev-env" --no-update-lock-file --no-link; then
        log_error "nix build ${FLAKE_DIR}#dev-env failed - the existing profile was left untouched"
        return 1
    fi

    # Element keys are names on nix >= 2.20 (indices before); either is a valid
    # `nix profile remove` argument. Anything not rooted at dev-env is a stray.
    # jq comes from the apt list: a profile that can hold a stray predates dev-env,
    # so it has no jq of its own. Installing past an unchecked stray would collide.
    if command -v jq &>/dev/null; then
        local stray_lines name origin
        stray_lines="$(jq -r '
            .elements | to_entries[]
            | select((.value.attrPath // "") | test("^packages\\.[^.]+\\.dev-env$") | not)
            | "\(.key)\t\(.value.attrPath // .value.originalUrl // (.value.storePaths // [] | first) // "unknown")"
        ' <<<"${profile_json}")"
        while IFS=$'\t' read -r name origin; do
            [[ -n "${name}" ]] || continue
            log_warn "Removing stray profile entry '${name}' (${origin})"
            nix profile remove "${name}"
        done <<<"${stray_lines}"
    elif grep -q '"attrPath"\|"storePaths"' <<<"${profile_json}"; then
        log_error "jq not found - cannot check the Nix profile for stray entries"
        return 1
    fi

    # Install the first time, upgrade after: an unchanged flake is a no-op.
    # --no-update-lock-file: a flake.nix the committed lock does not cover fails
    # here instead of locking on the box and reaching the profile unreviewed.
    if grep -Eq '"attrPath": *"packages\.[^"]+\.dev-env"' <<<"${profile_json}"; then
        nix profile upgrade dev-env --no-update-lock-file || {
            log_error "nix profile upgrade dev-env failed"
            return 1
        }
        log_ok "Dev toolset profile is up to date"
    else
        nix profile install "${FLAKE_DIR}#dev-env" --no-update-lock-file || {
            log_error "nix profile install ${FLAKE_DIR}#dev-env failed"
            return 1
        }
        log_ok "Dev toolset installed as the default Nix profile"
    fi
}

#===============================================================================
# herdr Server as a systemd User Service
#===============================================================================
# The server starts at boot (with linger) from the dev-env profile's herdr, so
# agent panes survive disconnects and reboots and every pane inherits the
# profile's toolset through PATH. The socket stays at herdr's default,
# ~/.config/herdr/herdr.sock, where acmd and `herdr machine add` look for it.
# %h is the user's home, resolved by systemd. ~/.local/bin is where uv puts sdlc;
# the default profile holds nix itself, which is not in dev-env.
herdr_unit_content() {
    cat <<'UNITEOF'
[Unit]
Description=herdr server (agent multiplexer)

[Service]
Type=simple
Environment="PATH=%h/.nix-profile/bin:%h/.local/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=%h/.nix-profile/bin/herdr server
Restart=on-failure
RestartSec=2
# systemd's default OOMPolicy=stop takes the whole service down when the kernel
# OOM-kills one pane, ending every agent; continue keeps the other panes alive.
OOMPolicy=continue

[Install]
WantedBy=default.target
UNITEOF
}

# PIDs of this user's herdr servers (one per line), whoever started them. Also
# matches the short-lived `herdr server stop`: harmless, where narrowing to a bare
# `herdr server` could miss a `herdr server live-handoff` holding the socket.
herdr_server_pids() {
    local pattern='^([^ ]*/)?herdr +server( |$)'
    pgrep -u "$(id -u)" -f "${pattern}" 2>/dev/null || true
}

# Stops the servers in $1 (newline-separated PIDs): SIGTERM, then SIGKILL after
# a bounded wait. Liveness is asked of pgrep, not kill -0, so a zombie nobody
# reaps does not count as running.
stop_unmanaged_herdr() {
    local pids="$1" i
    log_warn "Stopping herdr server PID ${pids//$'\n'/ }: this ends its sessions and every agent pane in them (--restart-herdr)"
    # shellcheck disable=SC2086  # one word per PID
    kill -TERM ${pids} 2>/dev/null || true
    for ((i = 0; i < 20; i++)); do
        [[ -z "$(herdr_server_pids)" ]] && return 0
        sleep 0.5
    done
    log_warn "herdr server ignored SIGTERM - sending SIGKILL"
    # shellcheck disable=SC2086
    kill -KILL ${pids} 2>/dev/null || true
    for ((i = 0; i < 10; i++)); do
        [[ -z "$(herdr_server_pids)" ]] && return 0
        sleep 0.5
    done
    return 1
}

# Without linger the user manager, and so the service named in $1, only lives
# while an SSH session is open.
ensure_linger() {
    local service="$1"
    if [[ "$(loginctl show-user "${DEV_USER}" --property=Linger --value 2>/dev/null || true)" != "yes" ]]; then
        sudo loginctl enable-linger "${DEV_USER}" || {
            log_error "loginctl enable-linger ${DEV_USER} failed - ${service} will not start at boot"
            return 1
        }
        log_ok "Enabled linger for ${DEV_USER}: ${service} starts at boot"
    else
        log_ok "Linger already enabled for ${DEV_USER}"
    fi
}

setup_herdr_service() {
    log_info "Setting up the herdr server user service..."

    local unit_dir="${HOME}/.config/systemd/user"
    local unit_file="${unit_dir}/herdr.service"
    local socket="${HOME}/.config/herdr/herdr.sock"
    local unit_changed=false tmp

    # Rewritten only on content drift, so unit fixes reach provisioned servers.
    mkdir -p "${unit_dir}"
    tmp="$(mktemp)"
    herdr_unit_content >"${tmp}"
    if ! cmp -s "${tmp}" "${unit_file}" 2>/dev/null; then
        install -m 644 "${tmp}" "${unit_file}"
        unit_changed=true
        log_ok "Wrote ${unit_file}"
    fi
    rm -f "${tmp}"

    if [[ ! -x "${HOME}/.nix-profile/bin/herdr" ]]; then
        log_warn "${HOME}/.nix-profile/bin/herdr not found - not enabling the herdr service (the dev-env profile step must succeed first)"
        return 0
    fi

    # No login session behind this shell (containers, sudo -u, a console
    # install): there is no user manager to talk to. The unit is on disk, so
    # re-running from an SSH login finishes the job.
    if ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user manager reachable from this shell - unit written, not enabled. Re-run the bootstrap from an SSH login."
        return 0
    fi

    # A server the unit itself runs is ours; only an outside one conflicts.
    local outside_pids="" start_now=true
    if ! systemctl --user is-active --quiet herdr.service; then
        outside_pids="$(herdr_server_pids)"
    fi
    if [[ -n "${outside_pids}" ]]; then
        if [[ "${RESTART_HERDR:-false}" == "true" && "${HERDR_ENV:-}" != "1" ]]; then
            if ! stop_unmanaged_herdr "${outside_pids}"; then
                log_error "Could not stop the herdr server (PID ${outside_pids//$'\n'/ })"
                return 1
            fi
            # The old server cannot clean up after itself once killed.
            rm -f "${socket}"
        elif [[ "${RESTART_HERDR:-false}" == "true" ]]; then
            # Stopping a server hangs up its panes, children included, so a
            # bootstrap run from one dies here (trapping SIGHUP does not save
            # it), with the unit not started and the later steps not run.
            log_error "--restart-herdr inside a herdr pane: refusing to stop the server (PID ${outside_pids//$'\n'/ }) - this bootstrap would die with its pane"
            log_error "Fix: re-run it from a shell outside herdr"
            start_now=false
        else
            log_warn "A herdr server is already running outside the unit (PID ${outside_pids//$'\n'/ }) - leaving it running."
            log_warn "Stopping it ends its sessions. Re-run with --restart-herdr (or RESTART_HERDR=true) to hand over to the unit; it starts at next boot either way."
            start_now=false
        fi
    fi

    if [[ "${unit_changed}" == "true" ]]; then
        systemctl --user daemon-reload
        if systemctl --user is-active --quiet herdr.service; then
            log_info "herdr.service changed while running - the new unit applies at the next herdr restart (that ends its sessions)"
        fi
    fi

    if [[ "${start_now}" == "true" ]]; then
        systemctl --user enable --now herdr.service || {
            log_error "systemctl --user enable --now herdr.service failed - see: journalctl --user -u herdr"
            return 1
        }
        log_ok "herdr server running as a user service"
    else
        systemctl --user enable herdr.service || {
            log_error "systemctl --user enable herdr.service failed"
            return 1
        }
        log_ok "herdr.service enabled (not started: an outside server owns the socket)"
    fi

    ensure_linger herdr
}

#===============================================================================
# acmd as a systemd User Service (acm from the agentic-coding-monitor flake)
#===============================================================================
# acm (acmd + acm) comes from the flake's pinned agentic-coding-monitor input,
# inside the dev-env profile, so the XPS aggregator sees install=nix and
# `acm peers deploy` refuses it: upgrading acm is a bump of that input by MR.
# The unit mirrors acm's homeManagerModules.acmd; PATH is herdr's, because acmd
# runs `sdlc` (in ~/.local/bin) and `herdr`, and reads herdr's default socket.
acmd_unit_content() {
    cat <<'UNITEOF'
[Unit]
Description=agentic-coding-monitor daemon (acmd)
After=graphical-session.target

[Service]
Environment="PATH=%h/.nix-profile/bin:%h/.local/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=%h/.nix-profile/bin/acmd
TimeoutStopSec=2
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
UNITEOF
}

# Whether nix.conf (arg 1) holds a github.com entry in access-tokens.
acm_token_configured() {
    grep -Eq '^[[:space:]]*access-tokens[[:space:]]*=.*(=|[[:space:]])github\.com=[^[:space:]]+' "$1" 2>/dev/null
}

# The acm input is private (GitHub mirror of root/agentic-coding-monitor): nix
# fetches it with a read-only token from the user's nix.conf `access-tokens`.
# FX supplies it as ACM_NIX_ACCESS_TOKEN at bootstrap time, or edits nix.conf by
# hand. It lives in that 0600 file and nowhere else: never logged (awk reads it
# from the environment, not argv), never written into the repo clone.
configure_acm_access_token() {
    log_info "Checking the read token for the private acm flake input..."

    local conf_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/nix"
    local conf="${conf_dir}/nix.conf"
    local token="${ACM_NIX_ACCESS_TOKEN:-}"

    if [[ -n "${token}" ]]; then
        local tmp
        mkdir -p "${conf_dir}"
        tmp="$(umask 077 && mktemp "${conf_dir}/nix.conf.XXXXXX")"
        # Replace only the github.com entry: other hosts and settings stay.
        ACM_TOKEN_ENTRY="github.com=${token}" awk '
            function emit(rest,    n, i, parts, kept) {
                n = split(rest, parts, /[ \t]+/)
                kept = ""
                for (i = 1; i <= n; i++)
                    if (parts[i] != "" && parts[i] !~ /^github\.com=/)
                        kept = kept (kept == "" ? "" : " ") parts[i]
                if (!done) {
                    kept = kept (kept == "" ? "" : " ") ENVIRON["ACM_TOKEN_ENTRY"]
                    done = 1
                }
                return kept
            }
            /^[ \t]*access-tokens[ \t]*=/ {
                rest = $0
                sub(/^[^=]*=[ \t]*/, "", rest)
                kept = emit(rest)
                if (kept != "") print "access-tokens = " kept
                next
            }
            { print }
            END { if (!done) print "access-tokens = " ENVIRON["ACM_TOKEN_ENTRY"] }
        ' "$([[ -f "${conf}" ]] && echo "${conf}" || echo /dev/null)" >"${tmp}" || {
            rm -f "${tmp}"
            log_error "Could not write the acm read token to ${conf}"
            return 1
        }
        if cmp -s "${tmp}" "${conf}" 2>/dev/null; then
            rm -f "${tmp}"
        else
            mv "${tmp}" "${conf}"
            log_ok "Stored the acm read token in ${conf} (access-tokens, mode 0600)"
        fi
    fi

    if acm_token_configured "${conf}"; then
        chmod 0600 "${conf}"
        ACM_TOKEN_MISSING=false
        return 0
    fi

    ACM_TOKEN_MISSING=true
    log_error "No acm read token: set 'access-tokens = github.com=<read-only token>' in ${conf} (mode 0600), or re-run with ACM_NIX_ACCESS_TOKEN=<token>"
    return 1
}

# A push install (`acm peers deploy`, `make install`) left binaries in
# ~/.local/bin, with .prev and .new copies from the swap. Its unit shares the
# Nix-managed unit's path, so setup_acmd_service's rewrite replaces it.
remove_acm_push_install() {
    local bin_dir="${HOME}/.local/bin" name suffix found=false
    for name in acmd acm; do
        for suffix in "" .prev .new; do
            if [[ -e "${bin_dir}/${name}${suffix}" || -L "${bin_dir}/${name}${suffix}" ]]; then
                rm -f "${bin_dir:?}/${name}${suffix}"
                found=true
            fi
        done
    done
    if [[ "${found}" == "true" ]]; then
        log_info "Removed the push install of acm from ${bin_dir}; the Nix-managed one replaces it"
    fi
}

# True when the running acmd is not the profile's current binary: a profile
# upgrade swaps the store path under a daemon that keeps running the old one.
acmd_running_stale() {
    local pid running wanted
    pid="$(systemctl --user show -p MainPID --value acmd.service 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ && "${pid}" -gt 0 ]] || return 1
    running="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    wanted="$(readlink -f "${HOME}/.nix-profile/bin/acmd" 2>/dev/null || true)"
    [[ "${running}" != "${wanted}" ]]
}

setup_acmd_service() {
    log_info "Setting up the acmd user service..."

    local unit_dir="${HOME}/.config/systemd/user"
    local unit_file="${unit_dir}/acmd.service"
    local unit_changed=false tmp

    # First: everything below replaces a push install, so without the binary that
    # replaces it the working daemon, its CLI and its unit must stay as they are.
    if [[ ! -x "${HOME}/.nix-profile/bin/acmd" ]]; then
        log_warn "${HOME}/.nix-profile/bin/acmd not found - leaving the acmd service as it is (the dev-env profile step must succeed first, which needs the acm read token: access-tokens in nix.conf)"
        return 0
    fi

    remove_acm_push_install

    # acmd keeps its socket and notification state here; it is private to the user.
    install -d -m 0700 "${HOME}/.local/state/acm"

    # Rewritten only on content drift, so unit fixes reach provisioned servers.
    mkdir -p "${unit_dir}"
    tmp="$(mktemp)"
    acmd_unit_content >"${tmp}"
    if ! cmp -s "${tmp}" "${unit_file}" 2>/dev/null; then
        install -m 644 "${tmp}" "${unit_file}"
        unit_changed=true
        log_ok "Wrote ${unit_file}"
    fi
    rm -f "${tmp}"

    # No login session behind this shell: no user manager to talk to. The unit
    # is on disk, so re-running from an SSH login finishes the job.
    if ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user manager reachable from this shell - unit written, not enabled. Re-run the bootstrap from an SSH login."
        return 0
    fi

    if [[ "${unit_changed}" == "true" ]]; then
        systemctl --user daemon-reload
    fi

    # Decided before `enable --now`: that starts a stopped acmd on the new
    # binary and unit already, so only a running one can be stale.
    local restart_needed=false
    if systemctl --user is-active --quiet acmd.service &&
        { [[ "${unit_changed}" == "true" ]] || acmd_running_stale; }; then
        restart_needed=true
    fi

    systemctl --user enable --now acmd.service || {
        log_error "systemctl --user enable --now acmd.service failed - see: journalctl --user -u acmd"
        return 1
    }

    # acmd keeps no state a restart loses (it re-reads herdr and sdlc), unlike herdr.
    if [[ "${restart_needed}" == "true" ]]; then
        systemctl --user restart acmd.service || {
            log_error "systemctl --user restart acmd.service failed - see: journalctl --user -u acmd"
            return 1
        }
        log_info "acmd restarted onto the current unit and binary"
    fi
    log_ok "acmd running as a user service"

    # herdr's setup enables this too, but returns before it when herdr fails.
    ensure_linger acmd
}

#===============================================================================
# Put ~/.nix-profile/bin on PATH for Login and Non-Interactive Shells
#===============================================================================
# ~/.bashrc is not enough: Ubuntu's returns early for non-interactive shells,
# so `ssh dev 'rg --version'` would never see it. /etc/environment is read by
# pam_env for sshd sessions and by the systemd user manager (environment.d links
# it as 99-environment.conf); ~/.profile covers login shells.
configure_profile_path() {
    log_info "Putting ~/.nix-profile/bin on PATH..."

    local env_file="${ENVIRONMENT_FILE:-/etc/environment}"
    local profile_bin="${HOME}/.nix-profile/bin"
    local profile_rc="${HOME}/.profile"
    local marker="# >>> nix-profile-path >>>"

    if grep -qF "${profile_bin}" "${env_file}" 2>/dev/null; then
        log_ok "${env_file} already puts ${profile_bin} on PATH"
    elif grep -q '^PATH=' "${env_file}" 2>/dev/null; then
        sudo sed -i "s|^PATH=\"\?|&${profile_bin}:|" "${env_file}"
        log_ok "Prepended ${profile_bin} to PATH in ${env_file}"
    else
        echo "PATH=\"${profile_bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" |
            sudo tee -a "${env_file}" >/dev/null
        log_ok "Added PATH with ${profile_bin} to ${env_file}"
    fi

    if grep -qF "${marker}" "${profile_rc}" 2>/dev/null; then
        log_ok "Login shell PATH already configured"
    else
        cat >>"${profile_rc}" <<'PROFILEEOF'

# >>> nix-profile-path >>>
export PATH="$HOME/.nix-profile/bin:$PATH"
# <<< nix-profile-path <<<
PROFILEEOF
        log_ok "Login shell PATH configured in ${profile_rc}"
    fi
}

#===============================================================================
# Export GITLAB_HOST and Put ~/.local/bin on PATH for Every Login Context
#===============================================================================
# glab and the sdlc controller read GITLAB_HOST; uv puts the `sdlc` entry point
# in ~/.local/bin. Same two routes as configure_profile_path: /etc/environment
# (sshd sessions, `ssh dev '<cmd>'`, systemd user services) and ~/.profile.
configure_gitlab_env() {
    log_info "Exporting GITLAB_HOST=${GITLAB_HOST} and ~/.local/bin on PATH..."

    local env_file="${ENVIRONMENT_FILE:-/etc/environment}"
    local local_bin="${HOME}/.local/bin"
    local profile_rc="${HOME}/.profile"
    local marker="# >>> gitlab-env >>>"

    if grep -qxF "GITLAB_HOST=${GITLAB_HOST}" "${env_file}" 2>/dev/null; then
        log_ok "${env_file} already exports GITLAB_HOST"
    else
        # Drop a stale value first so a changed host replaces, not duplicates
        if grep -q '^GITLAB_HOST=' "${env_file}" 2>/dev/null; then
            sudo sed -i '/^GITLAB_HOST=/d' "${env_file}"
        fi
        echo "GITLAB_HOST=${GITLAB_HOST}" | sudo tee -a "${env_file}" >/dev/null
        log_ok "Exported GITLAB_HOST=${GITLAB_HOST} in ${env_file}"
    fi

    if grep -qF "${local_bin}" "${env_file}" 2>/dev/null; then
        log_ok "${env_file} already puts ${local_bin} on PATH"
    elif grep -q '^PATH="' "${env_file}" 2>/dev/null; then
        sudo sed -i "/^PATH=\"/ s|\"\$|:${local_bin}\"|" "${env_file}"
        log_ok "Appended ${local_bin} to PATH in ${env_file}"
    else
        log_warn "No quoted PATH in ${env_file} - add ${local_bin} to it by hand"
    fi

    if grep -qxF "export GITLAB_HOST=${GITLAB_HOST}" "${profile_rc}" 2>/dev/null; then
        log_ok "Login shell GITLAB_HOST already configured"
    else
        # Drop a stale block first so a changed host replaces, not duplicates
        if grep -qF "${marker}" "${profile_rc}" 2>/dev/null; then
            sed -i "/^${marker}\$/,/^# <<< gitlab-env <<<\$/d" "${profile_rc}"
        fi
        cat >>"${profile_rc}" <<PROFILEEOF

${marker}
export GITLAB_HOST=${GITLAB_HOST}
case ":\$PATH:" in
    *":\$HOME/.local/bin:"*) ;;
    *) export PATH="\$PATH:\$HOME/.local/bin" ;;
esac
# <<< gitlab-env <<<
PROFILEEOF
        log_ok "Login shell GITLAB_HOST configured in ${profile_rc}"
    fi
}

#===============================================================================
# XDG_STATE_HOME (one sdlc run registry for sdlc and acmd)
#===============================================================================
# sdlc falls back to ~/.sdlc/registry.json without XDG_STATE_HOME; acmd falls back
# to ~/.local/state/sdlc/registry.json and pins it for every sdlc it runs. Setting
# the variable everywhere makes both use the second path.
configure_xdg_state() {
    log_info "Setting XDG_STATE_HOME=\$HOME/.local/state for sdlc and acmd..."

    local env_dir="${HOME}/.config/environment.d"
    local env_file="${env_dir}/10-xdg-state.conf"
    local state_dir="${HOME}/.local/state/sdlc"
    local begin="# >>> xdg-state >>>"
    local end="# <<< xdg-state <<<"
    local changed=false

    # environment.d (not a literal path) so systemd expands the user's own HOME
    # shellcheck disable=SC2016  # systemd expands ${HOME}, not this shell
    local want='XDG_STATE_HOME=${HOME}/.local/state'
    mkdir -p "${env_dir}" "${state_dir}"
    if [[ "$(cat "${env_file}" 2>/dev/null || true)" != "${want}" ]]; then
        printf '%s\n' "${want}" >"${env_file}"
        changed=true
        log_ok "Wrote ${env_file}"
    fi

    if ! declare -F write_rc_block >/dev/null; then
        # shellcheck disable=SC1091  # Path is dynamically built from vars
        # shellcheck source=lib/rc-block.sh
        source "${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/rc-block.sh"
    fi
    if write_rc_block "${HOME}/.profile" "${begin}" "${end}" <<PROFILEEOF
${begin}
export XDG_STATE_HOME="\${XDG_STATE_HOME:-\$HOME/.local/state}"
${end}
PROFILEEOF
    then
        log_ok "Login shell XDG_STATE_HOME configured in ${HOME}/.profile"
    fi

    local legacy="${HOME}/.sdlc/registry.json"
    local current="${state_dir}/registry.json"
    if [[ -f "${legacy}" ]]; then
        if [[ -e "${current}" ]]; then
            log_warn "Both ${legacy} and ${current} exist - leaving both; merge or remove the legacy one by hand"
        else
            mv "${legacy}" "${current}"
            [[ -e "${legacy}.lock" ]] && mv "${legacy}.lock" "${current}.lock"
            changed=true
            log_ok "Moved ${legacy} (and its .lock) to ${current}"
        fi
    fi

    if ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user manager reachable - herdr and acmd pick XDG_STATE_HOME up after a re-login and restart"
        return 0
    fi

    if [[ "${changed}" == "true" ]] ||
        ! systemctl --user show-environment | grep -q '^XDG_STATE_HOME='; then
        systemctl --user daemon-reexec || log_warn "systemctl --user daemon-reexec failed"
        changed=true
    fi
    log_info "herdr and acmd pick up XDG_STATE_HOME at their next restart (herdr is not restarted here: that ends its sessions)"
    # acmd keeps no state a restart loses, unlike herdr
    if [[ "${changed}" == "true" ]] && systemctl --user is-active --quiet acmd.service; then
        systemctl --user restart acmd.service || log_warn "acmd restart failed - restart it by hand"
        log_info "acmd restarted onto the new registry path"
    fi
}

#===============================================================================
# Install the sdlc Controller (pinned tag, uv-managed Python)
#===============================================================================
install_sdlc_controller() {
    log_info "Installing the sdlc controller..."

    local installer="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/scripts/install-sdlc-controller.sh"
    if [[ ! -f "${installer}" ]]; then
        log_warn "scripts/install-sdlc-controller.sh not found under ${REPO_CLONE_DIR} - skipping sdlc"
        return 0
    fi

    # Not worth aborting a bootstrap over: the installer is idempotent, so a
    # transient network failure is fixed by re-running it.
    if bash "${installer}"; then
        log_ok "sdlc controller ready (GITLAB_HOST=${GITLAB_HOST})"
    else
        log_warn "sdlc controller installation failed (non-critical) - re-run: bash ${installer}"
    fi
}

#===============================================================================
# acm Fleet Aggregator Role (peers, peer SSH key, phone keys)
#===============================================================================
setup_acm_fleet() {
    log_info "Setting up the acm fleet aggregator role..."

    local setup_script="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/scripts/setup-acm-fleet.sh"
    if [[ ! -f "${setup_script}" ]]; then
        log_warn "scripts/setup-acm-fleet.sh not found under ${REPO_CLONE_DIR} - skipping the acm fleet role"
        return 0
    fi

    # Not worth aborting a bootstrap over: a refused peer or phone line is fixed
    # in the file, and the script is idempotent.
    if bash "${setup_script}"; then
        log_ok "acm fleet aggregator role configured"
    else
        log_warn "acm fleet setup reported a problem (non-critical) - fix it, then re-run: bash ${setup_script}"
    fi
}

#===============================================================================
# Per-user Setup Formerly Done by the Dev Shell's shellHook
#===============================================================================
# Claude config symlinks, stale MCP pruning, zshrc and msmtprc templates.
setup_dev_env() {
    log_info "Applying per-user dev environment setup..."

    local setup_script="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/scripts/setup-dev-env.sh"
    if [[ ! -f "${setup_script}" ]]; then
        log_error "scripts/setup-dev-env.sh not found under ${REPO_CLONE_DIR}"
        return 1
    fi

    bash "${setup_script}"
    log_ok "Per-user dev environment setup applied"
}

#===============================================================================
# Install a systemd unit from stdin only when its content differs from disk
# Returns 0 when the unit was (re)written, 1 when it was already up to date
#===============================================================================
install_systemd_unit() {
    local dest="$1"
    local tmp
    tmp="$(mktemp)"
    cat >"${tmp}"

    if cmp -s "${tmp}" "${dest}" 2>/dev/null; then
        rm -f "${tmp}"
        return 1
    fi

    sudo install -m 644 "${tmp}" "${dest}"
    rm -f "${tmp}"
    return 0
}

#===============================================================================
# Setup systemd timer for weekly Nix flake updates
#===============================================================================
setup_nix_update_timer() {
    log_info "Setting up weekly Nix update timer..."

    local TIMER_NAME="nix-flake-update"
    local SERVICE_FILE="/etc/systemd/system/${TIMER_NAME}.service"
    local TIMER_FILE="/etc/systemd/system/${TIMER_NAME}.timer"
    local FLAKE_DIR="${HOME}/.config/nix-dev-env"
    local REPO_DIR="${HOME}/.local/share/bootstrap-dev-server"
    local UNITS_CHANGED=0

    # Regenerate the units on every run and rewrite them only on content
    # drift, so unit-file fixes reach already-provisioned servers instead of
    # being skipped forever once the timer is enabled. The notification-
    # enhanced service written by configure_update_notifications takes
    # precedence: never clobber it with the plain unit - unless it still runs
    # `nix flake update`, which only happens when that step was skipped on this
    # run. Losing email until the next full run beats mutating flake.lock.
    # Service unit runs as the dev user, not root.
    if ! sudo grep -q "nix-update-notify" "${SERVICE_FILE}" 2>/dev/null ||
        sudo grep -q "nix flake update" "${SERVICE_FILE}" 2>/dev/null; then
        if install_systemd_unit "${SERVICE_FILE}" <<SERVICEEOF; then
[Unit]
Description=Update Nix flake packages
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${DEV_USER}
Environment="HOME=/home/${DEV_USER}"
Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin"

# The repository is the only source of flake.lock: hard-reset the checkout to
# origin/main (logging any local diff or commits it discards), sync submodules,
# build dev-env with lock updates refused, and only on success upgrade the
# profile. Any failure stops the unit with the previous profile still in place.
ExecStart=/bin/bash -c 'set -e; cd ${REPO_DIR}; git fetch --quiet origin; git diff --stat HEAD | sed "s/^/[discarded] /"; git log --oneline origin/main..HEAD | sed "s/^/[discarded commit] /"; git reset --hard --quiet origin/main; git submodule update --recursive || echo "[warn] submodule update failed"; git log -1 --oneline | sed "s/^/[applied] /"; . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; nix build ${FLAKE_DIR}#dev-env --no-update-lock-file --no-link; nix profile upgrade dev-env; { bash ${REPO_DIR}/scripts/install-sdlc-controller.sh || echo "[warn] sdlc controller not converged to the pinned tag; re-run: bash ${REPO_DIR}/scripts/install-sdlc-controller.sh"; }'
SERVICEEOF
            UNITS_CHANGED=1
        fi
    fi

    # Timer unit (weekly on Sunday at 3am)
    if install_systemd_unit "${TIMER_FILE}" <<TIMEREOF; then
[Unit]
Description=Weekly Nix flake update

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
TIMEREOF
        UNITS_CHANGED=1
    fi

    if [[ ${UNITS_CHANGED} -eq 0 ]] && systemctl is-enabled "${TIMER_NAME}.timer" &>/dev/null; then
        log_ok "Nix update timer already configured"
        return 0
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable "${TIMER_NAME}.timer"
    sudo systemctl start "${TIMER_NAME}.timer"

    log_ok "Weekly Nix update timer configured (Sundays at 3am)"
    log_info "Check status: systemctl status ${TIMER_NAME}.timer"
    log_info "View next run: systemctl list-timers ${TIMER_NAME}.timer"
}

#===============================================================================
# Setup systemd timer for weekly Nix garbage collection
#===============================================================================
setup_nix_gc_timer() {
    log_info "Setting up weekly Nix garbage collection timer..."

    local TIMER_NAME="nix-gc"
    local SERVICE_FILE="/etc/systemd/system/${TIMER_NAME}.service"
    local TIMER_FILE="/etc/systemd/system/${TIMER_NAME}.timer"
    local UNITS_CHANGED=0

    # Regenerate the units on every run and rewrite them only on content
    # drift, so unit-file fixes reach already-provisioned servers instead of
    # being skipped forever once the timer is enabled.
    # Service unit runs as root to delete other users' generations too.
    if install_systemd_unit "${SERVICE_FILE}" <<SERVICEEOF; then
[Unit]
Description=Garbage collect old Nix store paths
After=network-online.target

[Service]
Type=oneshot
Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
ExecStart=/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d
SERVICEEOF
        UNITS_CHANGED=1
    fi

    # Timer unit (weekly on Sunday at 4am, after the flake update timer)
    if install_systemd_unit "${TIMER_FILE}" <<TIMEREOF; then
[Unit]
Description=Weekly Nix garbage collection

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
TIMEREOF
        UNITS_CHANGED=1
    fi

    if [[ ${UNITS_CHANGED} -eq 0 ]] && systemctl is-enabled "${TIMER_NAME}.timer" &>/dev/null; then
        log_ok "Nix GC timer already configured"
        return 0
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable "${TIMER_NAME}.timer"
    sudo systemctl start "${TIMER_NAME}.timer"

    log_ok "Weekly Nix GC timer configured (Sundays at 4am, deletes generations older than 30 days)"
    log_info "Check status: systemctl status ${TIMER_NAME}.timer"
    log_info "View next run: systemctl list-timers ${TIMER_NAME}.timer"
}

#===============================================================================
# Remove the tmux configuration
#===============================================================================
# An ssh login attaches to herdr now (see herdr_login_attach in setup-dev-env.sh).
# Earlier runs wrote a marked block to ~/.tmux.conf; take that block out and
# leave everything around it alone. The old tmux auto-launch lived inside the
# zshrc block that setup_dev_env rewrites on drift, so it goes with that rewrite.
remove_tmux_config() {
    local tmux_conf="${HOME}/.tmux.conf"
    local begin="# >>> nix-dev-env tmux >>>"
    local end="# <<< nix-dev-env tmux <<<"
    local first last tmp

    [[ -f "${tmux_conf}" ]] || return 0
    first="$(grep -nxF -- "${begin}" "${tmux_conf}" | head -n 1 | cut -d: -f1 || true)"
    [[ -n "${first}" ]] || return 0
    last="$(grep -nxF -- "${end}" "${tmux_conf}" | tail -n 1 | cut -d: -f1 || true)"

    # Deleting up to a closing marker that is not there would eat the rest of the file.
    if [[ -z "${last}" || "${last}" -lt "${first}" ]]; then
        log_warn "${tmux_conf}: '${begin}' has no closing marker - leaving the file as it is"
        return 0
    fi

    tmp="$(mktemp)"
    sed "${first},${last}d" "${tmux_conf}" >"${tmp}"
    cat "${tmp}" >"${tmux_conf}"
    rm -f "${tmp}"
    log_ok "Removed the nix-dev-env block from ${tmux_conf}"
}

#===============================================================================
# Create CLAUDE.md Template
#===============================================================================
create_claude_md() {
    log_info "Creating CLAUDE.md template..."

    local CLAUDE_MD="${HOME}/CLAUDE.md"
    # shellcheck disable=SC2016  # Literal backticks, nothing to expand
    local stale_dev_update='- `dev-update` - Update Nix flake dependencies'

    if [[ -f "${CLAUDE_MD}" ]]; then
        # The file is the user's from here on: migrate only the stock line that
        # no longer describes dev-update, and only if it is still there verbatim.
        if grep -qxF -- "${stale_dev_update}" "${CLAUDE_MD}"; then
            sed -i "s|^${stale_dev_update}\$|- \`dev-update\` - Apply origin/main (reset checkout, build dev-env, upgrade profile)|" "${CLAUDE_MD}"
            log_ok "CLAUDE.md dev-update description updated"
        fi
        log_ok "CLAUDE.md already exists"
        return 0
    fi

    cat >"${CLAUDE_MD}" <<'CLAUDEEOF'
# CLAUDE.md - Project Instructions

## Environment
- OS: Ubuntu 24.04 LTS
- Shell: Bash with Nix dev environment
- Editor: Neovim preferred

## Development Workflow
1. The toolset is already on PATH; `dev` or `nix develop` enters the optional dev shell
2. Use `lazygit` for git operations
3. Use `gh` for GitHub CLI operations

## Code Standards
- Python: Use `ruff` for linting, `uv` for package management
- Follow conventional commits
- Write tests for new features

## Project Structure
```
~/projects/
├── project-name/
│   ├── CLAUDE.md      # Project-specific instructions
│   ├── flake.nix      # Optional project-specific flake
│   └── ...
```

## Commands Reference
- `dev` - Enter full dev environment
- `dm` - Enter minimal environment  
- `dp` - Enter Python environment
- `dev-update` - Apply origin/main (reset checkout, build dev-env, upgrade profile)
- `claude` - Start Claude Code session
CLAUDEEOF

    log_ok "CLAUDE.md template created at ${CLAUDE_MD}"
}

#===============================================================================
# Configure Podman for rootless containers (Nix-provided Podman needs config)
#===============================================================================
configure_podman() {
    log_info "Configuring Podman for rootless containers..."

    local CONTAINERS_DIR="${HOME}/.config/containers"

    # Check if already configured
    if [[ -f "${CONTAINERS_DIR}/policy.json" ]] && [[ -f "${CONTAINERS_DIR}/registries.conf" ]]; then
        log_ok "Podman already configured"
        return 0
    fi

    mkdir -p "${CONTAINERS_DIR}"

    # Create image signature policy (required for pulling images)
    cat > "${CONTAINERS_DIR}/policy.json" << 'EOF'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ]
}
EOF

    # Create registry configuration (enables short names like "alpine")
    cat > "${CONTAINERS_DIR}/registries.conf" << 'EOF'
unqualified-search-registries = ["docker.io"]
EOF

    log_ok "Podman configured for rootless containers"
}

#===============================================================================
# Build Initial Nix Environment (warm cache)
#===============================================================================
warm_nix_cache() {
    log_info "Building Nix environment (this may take a few minutes on first run)..."

    local FLAKE_DIR="${HOME}/.config/nix-dev-env"

    # Source Nix if not already available
    if ! command -v nix &>/dev/null; then
        if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
            # shellcheck source=/dev/null
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
    fi

    # Build the default shell (downloads and caches all dependencies)
    cd "${FLAKE_DIR}"
    local current_system
    current_system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    nix build ".#devShells.${current_system}.default" --no-link

    log_ok "Nix environment built and cached"
}

#===============================================================================
# Print Summary
#===============================================================================
print_summary() {
    local IP_ADDR
    IP_ADDR=$(hostname -I | awk '{print $1}')

    # Build connection strings based on SSH port
    local ssh_cmd="ssh ${DEV_USER}@${IP_ADDR}"
    local mosh_cmd="mosh ${DEV_USER}@${IP_ADDR}"
    if [[ "${SSH_PORT}" != "22" ]]; then
        ssh_cmd="ssh -p ${SSH_PORT} ${DEV_USER}@${IP_ADDR}"
        mosh_cmd="mosh --ssh=\"ssh -p ${SSH_PORT}\" ${DEV_USER}@${IP_ADDR}"
    fi

    # Profile-aware completion message
    local completion_msg
    case "${SERVER_PROFILE}" in
        dev)
            completion_msg="Dev Server Bootstrap Complete!"
            ;;
        nyx)
            completion_msg="Nyx Server Bootstrap Complete! (Dev + Clawdbot)"
            ;;
        full)
            completion_msg="Full Server Bootstrap Complete! (Dev + Nyx)"
            ;;
        *)
            completion_msg="Server Bootstrap Complete! (${SERVER_PROFILE})"
            ;;
    esac

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ ${completion_msg}${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}Connection:${NC}"
    echo -e "    SSH:  ${YELLOW}${ssh_cmd}${NC}"
    echo -e "    Mosh: ${YELLOW}${mosh_cmd}${NC}"
    echo ""
    echo -e "  ${BLUE}Quick Start:${NC}"
    echo -e "    1. Reconnect or run: ${YELLOW}source ~/.bashrc${NC}"
    echo -e "    2. Start Claude: ${YELLOW}claude${NC}"
    echo ""
    echo -e "  ${BLUE}Available Environments:${NC}"
    echo -e "    ${YELLOW}dev${NC}        - Full dev environment"
    echo -e "    ${YELLOW}dev minimal${NC} - Just Claude + basics"
    echo -e "    ${YELLOW}dev python${NC}  - Python-focused environment"
    echo ""
    echo -e "  ${BLUE}Maintenance:${NC}"
    echo -e "    ${YELLOW}dev-update${NC}  - Apply origin/main and upgrade the Nix profile"
    echo ""
    echo -e "  ${BLUE}Repository:${NC}"
    echo -e "    ${YELLOW}${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

    # Prominent warning if SSH port changed
    if [[ "${SSH_PORT}" != "22" ]]; then
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  ⚠️  SSH PORT CHANGED TO ${SSH_PORT}${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "  Your connection will be reset. Reconnect with:"
        echo -e "    ${YELLOW}${ssh_cmd}${NC}"
        echo ""
        echo -e "  Or add to your ~/.ssh/config:"
        echo -e "    ${CYAN}Host dev-server${NC}"
        echo -e "    ${CYAN}    Port ${SSH_PORT}${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    fi
}

#===============================================================================
# Self-update: run the freshest script, not the one already in memory
#===============================================================================
# Phase 1 and the GitHub auth step run before clone_bootstrap_repo pulls, so a
# fix to them would otherwise need two runs. Pull first and re-exec once.
reexec_from_updated_clone() {
    local clone_script="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/bootstrap-dev-server.sh"
    local running="${BASH_SOURCE[0]:-}"

    [[ -z "${BOOTSTRAP_REEXECED:-}" ]] || return 0
    [[ -d "${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}" ]] || return 0

    local old_rev new_rev
    old_rev="$(git -C "${REPO_CLONE_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if ! git -C "${REPO_CLONE_DIR}" pull --ff-only --quiet; then
        log_warn "Could not pull ${REPO_CLONE_DIR} - continuing with the running script"
        return 0
    fi
    [[ -f "${clone_script}" ]] || return 0
    new_rev="$(git -C "${REPO_CLONE_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

    # A pull that moved HEAD always re-execs: run from the clone itself, the
    # running path now holds the new file, so comparing contents would match.
    # A script piped from curl has no readable file to compare: treat as different
    if [[ "${old_rev}" == "${new_rev}" ]] \
        && [[ -n "${running}" && -f "${running}" && "${running}" != /dev/* ]] \
        && cmp -s "${running}" "${clone_script}"; then
        return 0
    fi

    log_info "Bootstrap updated (${old_rev}..${new_rev}); restarting from the clone"
    export BOOTSTRAP_REEXECED=1
    exec bash "${clone_script}" "$@"
}

#===============================================================================
# Main
#===============================================================================
main() {
    # Parse command line arguments
    for arg in "$@"; do
        case "${arg}" in
            --yes|-y)
                # Non-interactive mode (kept for compatibility, not used yet)
                ;;
            --skip-github-auth)
                SKIP_GITHUB_AUTH=true
                ;;
            --skip-security-hardening)
                SKIP_SECURITY_HARDENING=true
                ;;
            --restart-herdr)
                RESTART_HERDR=true
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --yes, -y                   Run in non-interactive mode (future use)"
                echo "  --skip-github-auth          Skip GitHub CLI authentication (for testing)"
                echo "  --skip-security-hardening   Skip security hardening phase (for containers)"
                echo "  --restart-herdr             Stop a herdr server running outside the systemd unit (ends its sessions)"
                echo "  --help, -h                  Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: ${arg}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    reexec_from_updated_clone "$@"

    # Profile-aware title
    local profile_title
    case "${SERVER_PROFILE}" in
        dev)
            profile_title="Dev Server Bootstrap"
            ;;
        nyx)
            profile_title="Nyx Server Bootstrap (Dev + Clawdbot)"
            ;;
        full)
            profile_title="Full Server Bootstrap (Dev + Nyx)"
            ;;
        *)
            profile_title="Server Bootstrap (${SERVER_PROFILE})"
            ;;
    esac

    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${BLUE}║  %-60s║${NC}\n" "${profile_title}"
    echo -e "${BLUE}║  Ubuntu 24.04 + Nix Flakes + Claude Code                      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_phase "1: Preflight and Base Packages"
    preflight_checks
    refresh_github_cli_apt_source
    install_base_packages
    configure_unattended_upgrades

    log_phase "2: Git and GitHub Setup"
    install_github_cli
    configure_git_identity
    if [[ "${SKIP_GITHUB_AUTH}" != "true" ]]; then
        authenticate_github_cli
    else
        log_warn "Skipping GitHub CLI authentication (--skip-github-auth)"
    fi
    clone_bootstrap_repo

    # Upgrade to full logging library now that repo is cloned
    upgrade_logging

    if [[ "${SKIP_SECURITY_HARDENING}" != "true" ]]; then
        log_phase "3: Security Hardening"
        # Warn about potential SSH disconnection during security hardening
        echo ""
        log_warn "╔════════════════════════════════════════════════════════════════════╗"
        log_warn "║  SSH connection may drop during security hardening.                 ║"
        log_warn "║  If disconnected, wait 30 seconds then reconnect and re-run:        ║"
        log_warn "║                                                                     ║"
        log_warn "║    ssh ${DEV_USER}@\$(hostname -I | awk '{print \$1}')                          ║"
        log_warn "║    cd ~/.local/share/bootstrap-dev-server                           ║"
        log_warn "║    ./bootstrap-dev-server.sh                                        ║"
        log_warn "║                                                                     ║"
        log_warn "║  The script is idempotent - it will resume where it left off.       ║"
        log_warn "╚════════════════════════════════════════════════════════════════════╝"
        echo ""
        log_timer_start "security_hardening" 2>/dev/null || true
        harden_ssh
        regenerate_host_keys
        configure_firewall
        configure_fail2ban
        install_geoip_shell || true  # Optional: Tailscale provides backup access
        install_tailscale
        install_auditd
        harden_sysctl
        harden_pam
        setup_security_report
        configure_update_notifications
        clean_old_kernels
        log_timer_end "security_hardening" 2>/dev/null || true
    else
        log_warn "Skipping Phase 3: Security Hardening (--skip-security-hardening)"
    fi

    log_phase "4: Nix Installation and Configuration"
    log_timer_start "nix_setup" 2>/dev/null || true
    install_nix
    create_dev_flake
    setup_shell_integration
    # The dev-env profile carries acm, a private flake input: its read token goes
    # into nix.conf first. Without it the profile cannot be fetched or upgraded;
    # that is tolerated so the rest of the bootstrap (SSH hardening included) runs.
    configure_acm_access_token || log_warn "acm read token missing (access-tokens in nix.conf) - add it, then re-run the bootstrap"
    install_dev_profile || {
        [[ "${ACM_TOKEN_MISSING}" == "true" ]] || exit 1
        log_warn "dev-env profile not installed or upgraded without the acm read token - add it, then re-run the bootstrap"
    }
    configure_profile_path
    configure_gitlab_env
    configure_xdg_state || log_warn "XDG_STATE_HOME setup failed (non-critical) - fix it, then re-run the bootstrap"
    # After the env: panes get GITLAB_HOST from the server alone, whose reload hands
    # /etc/environment to a user manager that started before it had the variable.
    # Not worth aborting over: a re-run would not reach restart_ssh_final's reload.
    setup_herdr_service || log_warn "herdr service setup failed (non-critical) - fix it, then re-run the bootstrap"
    setup_acmd_service || log_warn "acmd service setup failed (non-critical) - fix it, then re-run the bootstrap"
    setup_acm_fleet
    install_sdlc_controller
    setup_dev_env
    setup_nix_update_timer
    setup_nix_gc_timer
    remove_tmux_config
    create_claude_md
    configure_podman
    log_timer_start "nix_cache_warmup" 2>/dev/null || true
    # The default shell carries acm too, so without the token this build cannot fetch
    # it, and dying here would strand the SSH reload below: a re-run does not redo it.
    # Skipped rather than `warm_nix_cache || ...`, which would switch set -e off inside.
    if [[ "${ACM_TOKEN_MISSING}" == "true" ]]; then
        log_warn "Nix cache not warmed without the acm read token - add it, then re-run the bootstrap"
    else
        warm_nix_cache
    fi
    log_timer_end "nix_cache_warmup" 2>/dev/null || true
    log_timer_end "nix_setup" 2>/dev/null || true

    log_phase "5: Monitoring and Alerts (node_exporter, ntfy)"
    remove_beszel_agent
    install_node_exporter
    install_ntfy

    log_phase "6: Final SSH Configuration"
    restart_ssh_final

    log_phase "Complete"
    print_summary
}

# Run main function
main "$@"
