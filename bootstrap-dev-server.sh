#!/usr/bin/env bash
#===============================================================================
# CX11 Dev Server Bootstrap Script
#
# Usage: curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | bash
#
# Idempotent: Safe to run multiple times
# Requirements: Fresh Ubuntu 24.04 server with sudo access
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
SSH_PORT="${SSH_PORT:-22}"
MOSH_PORT_START="${MOSH_PORT_START:-60000}"
MOSH_PORT_END="${MOSH_PORT_END:-60010}"

# Security hardening configuration
UFW_RATE_LIMIT="${UFW_RATE_LIMIT:-true}"           # Enable UFW rate limiting for SSH
GEOIP_ENABLED="${GEOIP_ENABLED:-true}"             # Enable GeoIP country blocking
GEOIP_COUNTRIES="${GEOIP_COUNTRIES:-LU,FR,GR}"     # Whitelist: Luxembourg, France, Greece

# Internal state (set by functions)
SSH_RESTART_NEEDED=false                           # Set by harden_ssh() if restart needed

# Repository configuration
GITHUB_REPO="fxmartin/nix-install"
REPO_CLONE_DIR="${HOME}/.local/share/nix-install"
BOOTSTRAP_SUBDIR="bootstrap-dev-server"

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
        xz-utils \
        ufw \
        fail2ban \
        mosh \
        zsh \
        unattended-upgrades

    log_ok "Base packages installed"
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
authenticate_github_cli() {
    log_info "Checking GitHub CLI authentication..."

    # Check if already authenticated
    if gh auth status >/dev/null 2>&1; then
        local gh_user
        gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
        log_ok "GitHub CLI already authenticated as: ${gh_user}"
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
        if (cd "${REPO_CLONE_DIR}" && git pull --quiet); then
            log_ok "Repository updated"
        else
            log_warn "Failed to pull updates (continuing with existing files)"
        fi
        return 0
    fi

    # Create parent directory
    mkdir -p "$(dirname "${REPO_CLONE_DIR}")"

    # Clone with sparse checkout (only bootstrap-dev-server folder)
    log_info "Using sparse checkout for ${BOOTSTRAP_SUBDIR} folder only..."

    # Initialize empty repository
    git clone --filter=blob:none --no-checkout --depth 1 --sparse \
        "https://github.com/${GITHUB_REPO}.git" "${REPO_CLONE_DIR}"

    # Configure sparse checkout
    cd "${REPO_CLONE_DIR}"
    git sparse-checkout set "${BOOTSTRAP_SUBDIR}"

    # Checkout the files
    git checkout

    log_ok "Repository cloned (sparse) at ${REPO_CLONE_DIR}"
    log_info "Only ${BOOTSTRAP_SUBDIR}/ folder downloaded"
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

    # SSH with optional rate limiting (blocks after 6 connections in 30 seconds from same IP)
    if [[ "${UFW_RATE_LIMIT:-true}" == "true" ]]; then
        sudo ufw limit "${SSH_PORT}"/tcp comment 'SSH with rate limiting'
        log_info "SSH rate limiting enabled (6 connections/30s threshold)"
    else
        sudo ufw allow "${SSH_PORT}"/tcp comment 'SSH'
    fi

    # Mosh UDP ports
    sudo ufw allow "${MOSH_PORT_START}:${MOSH_PORT_END}"/udp comment 'Mosh'

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
    log_warn "║  Run 'sudo tailscale up' after bootstrap to authenticate.          ║"
    log_warn "║  This will provide a URL to link this server to your account.      ║"
    log_warn "╚════════════════════════════════════════════════════════════════════╝"
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

# Source Nix environment for msmtp
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Get msmtp path from Nix store (installed via flake.nix)
MSMTP_BIN=$(find /nix/store -maxdepth 2 -name "msmtp" -path "*/bin/msmtp" 2>/dev/null | head -1)
if [[ -z "${MSMTP_BIN}" ]]; then
    echo "ERROR: msmtp not found in Nix store. Run 'dev' to install via Nix flake." >&2
    exit 1
fi

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
    CURRENT_BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print ${NF}}' || echo "0")
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
    ACCEPTED_DETAILS=$(grep "Accepted" /var/log/auth.log 2>/dev/null | tail -3 | awk '{print $9"@"$11}' | tr '\n' ' ' || echo "")

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

    # Check if already configured
    if grep -q "${MARKER}" "${BASHRC}" 2>/dev/null; then
        log_ok "Shell integration already configured"
        return 0
    fi

    cat >>"${BASHRC}" <<SHELLEOF

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
# - Pulls latest from nix-install repo (flake.nix is symlinked, so changes apply automatically)
# - Updates flake.lock with latest packages
dev-update() {
    echo "🔄 Updating dev environment..."
    local REPO_DIR="\${HOME}/.local/share/nix-install"
    local FLAKE_DIR="\${HOME}/.config/nix-dev-env"

    # Pull latest from repo
    if [[ -d "\${REPO_DIR}/.git" ]]; then
        echo "📥 Pulling latest from nix-install repo..."
        (cd "\${REPO_DIR}" && git pull --quiet) || echo "⚠️  Failed to pull repo (continuing anyway)"
    fi

    # Update flake.lock (flake.nix is symlinked, no copy needed)
    echo "⬆️  Updating Nix packages..."
    (cd "\${FLAKE_DIR}" && nix flake update)

    echo ""
    echo "✅ Dev environment updated!"
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
# <<< nix-dev-env <<<
SHELLEOF

    log_ok "Shell integration configured"
    log_info "Run 'source ~/.bashrc' or reconnect to activate"
}

#===============================================================================
# Configure tmux
#===============================================================================
configure_tmux() {
    log_info "Configuring tmux..."

    local TMUX_CONF="${HOME}/.tmux.conf"
    local MARKER="# >>> nix-dev-env tmux >>>"

    # Check if already configured
    if grep -q "${MARKER}" "${TMUX_CONF}" 2>/dev/null; then
        log_ok "tmux already configured"
        return 0
    fi

    cat >>"${TMUX_CONF}" <<'TMUXEOF'

# >>> nix-dev-env tmux >>>
# Use zsh as default shell (installed via apt in base packages)
set-option -g default-shell /usr/bin/zsh

# Enable mouse support (scrolling, pane selection)
set -g mouse on

# Increase scrollback buffer
set -g history-limit 50000

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Faster key repetition
set -s escape-time 0

# Better colors
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# Status bar styling
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
set -g status-left '[#S] '
set -g status-right '%H:%M '

# Easy reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Split panes with | and -
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
# <<< nix-dev-env tmux <<<
TMUXEOF

    log_ok "tmux configured with zsh as default shell"
}

#===============================================================================
# Create CLAUDE.md Template
#===============================================================================
create_claude_md() {
    log_info "Creating CLAUDE.md template..."

    local CLAUDE_MD="${HOME}/CLAUDE.md"

    if [[ -f "${CLAUDE_MD}" ]]; then
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
1. Enter dev environment: `dev` or `nix develop`
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
- `dev-update` - Update Nix flake dependencies
- `claude` - Start Claude Code session
CLAUDEEOF

    log_ok "CLAUDE.md template created at ${CLAUDE_MD}"
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

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Dev Server Bootstrap Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}Connection:${NC}"
    echo -e "    SSH:  ${YELLOW}${ssh_cmd}${NC}"
    echo -e "    Mosh: ${YELLOW}${mosh_cmd}${NC}"
    echo ""
    echo -e "  ${BLUE}Quick Start:${NC}"
    echo -e "    1. Reconnect or run: ${YELLOW}source ~/.bashrc${NC}"
    echo -e "    2. Enter dev environment: ${YELLOW}dev${NC}"
    echo -e "    3. Start Claude: ${YELLOW}claude${NC}"
    echo ""
    echo -e "  ${BLUE}Available Environments:${NC}"
    echo -e "    ${YELLOW}dev${NC}        - Full dev environment"
    echo -e "    ${YELLOW}dev minimal${NC} - Just Claude + basics"
    echo -e "    ${YELLOW}dev python${NC}  - Python-focused environment"
    echo ""
    echo -e "  ${BLUE}Maintenance:${NC}"
    echo -e "    ${YELLOW}dev-update${NC}  - Update all Nix packages"
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
# Main
#===============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       CX11 Dev Server Bootstrap Script                        ║${NC}"
    echo -e "${BLUE}║       Ubuntu 24.04 + Nix Flakes + Claude Code                 ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_phase "1: Preflight and Base Packages"
    preflight_checks
    install_base_packages

    log_phase "2: Git and GitHub Setup"
    install_github_cli
    configure_git_identity
    authenticate_github_cli
    clone_bootstrap_repo

    # Upgrade to full logging library now that repo is cloned
    upgrade_logging

    log_phase "3: Security Hardening"
    log_timer_start "security_hardening" 2>/dev/null || true
    harden_ssh
    regenerate_host_keys
    configure_firewall
    configure_fail2ban
    install_geoip_shell
    install_tailscale
    install_auditd
    harden_sysctl
    harden_pam
    setup_security_report
    clean_old_kernels
    log_timer_end "security_hardening" 2>/dev/null || true

    log_phase "4: Nix Installation and Configuration"
    log_timer_start "nix_setup" 2>/dev/null || true
    install_nix
    create_dev_flake
    setup_shell_integration
    configure_tmux
    create_claude_md
    log_timer_start "nix_cache_warmup" 2>/dev/null || true
    warm_nix_cache
    log_timer_end "nix_cache_warmup" 2>/dev/null || true
    log_timer_end "nix_setup" 2>/dev/null || true

    log_phase "5: Final SSH Configuration"
    restart_ssh_final

    log_phase "Complete"
    print_summary
}

# Run main function
main "$@"
