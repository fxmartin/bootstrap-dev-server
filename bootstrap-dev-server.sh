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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Configuration - Edit these for your setup
#===============================================================================
DEV_USER="${DEV_USER:-$(whoami)}"
SSH_PORT="${SSH_PORT:-22}"
MOSH_PORT_START="${MOSH_PORT_START:-60000}"
MOSH_PORT_END="${MOSH_PORT_END:-60010}"

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
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script is designed for Ubuntu. Detected: $ID"
            exit 1
        fi
        log_ok "Detected $PRETTY_NAME"
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
        unattended-upgrades
    
    log_ok "Base packages installed"
}

#===============================================================================
# Install GitHub CLI
#===============================================================================
install_github_cli() {
    log_info "Installing GitHub CLI..."

    if command -v gh &>/dev/null; then
        log_ok "GitHub CLI already installed: $(gh --version | head -1)"
        return 0
    fi

    # Add GitHub CLI repository (official method for Ubuntu)
    log_info "Adding GitHub CLI apt repository..."

    # Install required packages for adding repository
    sudo apt-get install -y -qq software-properties-common

    # Add GitHub CLI GPG key
    sudo mkdir -p -m 755 /etc/apt/keyrings
    if ! wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null; then
        log_error "Failed to download GitHub CLI GPG key"
        return 1
    fi
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    # Install gh
    sudo apt-get update -qq
    sudo apt-get install -y -qq gh

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

    if [[ -n "$current_name" ]] && [[ -n "$current_email" ]]; then
        log_ok "Git already configured: $current_name <$current_email>"
        return 0
    fi

    # Check for environment variables first (allows non-interactive setup)
    local git_name="${GIT_USER_NAME:-}"
    local git_email="${GIT_USER_EMAIL:-}"

    if [[ -n "$git_name" ]] && [[ -n "$git_email" ]]; then
        log_info "Using Git identity from environment variables"
    else
        echo ""
        log_info "Git identity not configured. Please provide your details:"
        log_info "(Or set GIT_USER_NAME and GIT_USER_EMAIL environment variables)"
        echo ""

        # Read from /dev/tty to work even when script is piped
        # Prompt for name
        printf "  Full Name: "
        read -r git_name < /dev/tty || {
            log_error "Cannot read input. Set GIT_USER_NAME and GIT_USER_EMAIL env vars instead."
            return 1
        }
        if [[ -z "$git_name" ]]; then
            log_error "Name cannot be empty"
            return 1
        fi

        # Prompt for email
        printf "  Email: "
        read -r git_email < /dev/tty || {
            log_error "Cannot read input. Set GIT_USER_NAME and GIT_USER_EMAIL env vars instead."
            return 1
        }
        if [[ -z "$git_email" ]]; then
            log_error "Email cannot be empty"
            return 1
        fi
    fi

    # Configure git
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    # Set sensible defaults
    git config --global init.defaultBranch main
    git config --global pull.rebase false

    log_ok "Git configured: $git_name <$git_email>"
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
        log_ok "GitHub CLI already authenticated as: $gh_user"
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
    log_ok "GitHub CLI authenticated as: $gh_user"
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
    
    # Only create if doesn't exist or force update
    if [[ ! -f "$SSH_HARDENING_FILE" ]] || [[ "${FORCE_SSH_UPDATE:-}" == "true" ]]; then
        sudo tee "$SSH_HARDENING_FILE" > /dev/null << 'SSHEOF'
# SSH Hardening Configuration
# Generated by bootstrap-dev-server.sh

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
        
        # Validate SSH config before restart
        if sudo sshd -t; then
            sudo systemctl reload ssh || sudo systemctl reload sshd
            log_ok "SSH hardening applied"
        else
            log_error "SSH config validation failed! Reverting..."
            sudo rm -f "$SSH_HARDENING_FILE"
            exit 1
        fi
    else
        log_ok "SSH hardening already configured"
    fi
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
        awk '$5 >= 3071' /etc/ssh/moduli | sudo tee /etc/ssh/moduli.tmp > /dev/null
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
    sudo ufw --force reset > /dev/null
    
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # SSH
    sudo ufw allow "$SSH_PORT"/tcp comment 'SSH'
    
    # Mosh UDP ports
    sudo ufw allow "${MOSH_PORT_START}:${MOSH_PORT_END}"/udp comment 'Mosh'
    
    # Enable firewall
    sudo ufw --force enable
    
    log_ok "Firewall configured (SSH: $SSH_PORT, Mosh: $MOSH_PORT_START-$MOSH_PORT_END)"
}

#===============================================================================
# Fail2Ban Configuration
#===============================================================================
configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    
    sudo tee /etc/fail2ban/jail.local > /dev/null << 'F2BEOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
F2BEOF

    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    
    log_ok "Fail2Ban configured"
}

#===============================================================================
# Install Tailscale VPN
#===============================================================================
install_tailscale() {
    log_info "Installing Tailscale..."

    if command -v tailscale &>/dev/null; then
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
    if [[ ! -f "$AUDIT_RULES" ]]; then
        sudo tee "$AUDIT_RULES" > /dev/null << 'AUDITEOF'
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

    if [[ -f "$SYSCTL_FILE" ]]; then
        log_ok "Sysctl hardening already configured"
        return 0
    fi

    sudo tee "$SYSCTL_FILE" > /dev/null << 'SYSCTLEOF'
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
    sudo sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1

    log_ok "Kernel parameters hardened"
}

#===============================================================================
# Harden PAM Configuration
#===============================================================================
harden_pam() {
    log_info "Hardening PAM configuration..."

    local PAM_AUTH="/etc/pam.d/common-auth"

    # Remove nullok option (allows empty passwords)
    if grep -q "pam_unix.so nullok" "$PAM_AUTH" 2>/dev/null; then
        sudo sed -i 's/pam_unix.so nullok/pam_unix.so/' "$PAM_AUTH"
        log_ok "Removed nullok from PAM (empty passwords disallowed)"
    else
        log_ok "PAM nullok already removed"
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

    if [[ "$kernel_count" -gt 1 ]]; then
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
        log_ok "Nix already installed: $(nix --version)"
        return 0
    fi
    
    # Determinate Systems installer - enables flakes by default
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
        sh -s -- install --no-confirm
    
    # Source Nix in current shell
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    
    log_ok "Nix installed: $(nix --version)"
}

#===============================================================================
# Create Dev Environment Flake
#===============================================================================
create_dev_flake() {
    log_info "Creating dev environment flake..."

    local FLAKE_DIR="$HOME/.config/nix-dev-env"
    local SOURCE_FLAKE="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/flake.nix"

    mkdir -p "$FLAKE_DIR"

    # Copy flake.nix from cloned repository
    log_info "Copying flake.nix from local repository..."

    if [[ ! -f "$SOURCE_FLAKE" ]]; then
        log_error "Source flake not found: $SOURCE_FLAKE"
        log_error "Ensure clone_bootstrap_repo() was called first"
        return 1
    fi

    if ! cp "$SOURCE_FLAKE" "$FLAKE_DIR/flake.nix"; then
        log_error "Failed to copy flake.nix"
        return 1
    fi

    # Verify copy
    if [[ ! -s "$FLAKE_DIR/flake.nix" ]]; then
        log_error "Copied flake.nix is empty"
        return 1
    fi

    # Initialize git repo for flake (required by Nix)
    cd "$FLAKE_DIR"
    if [[ ! -d .git ]]; then
        git init -q
    fi
    git add -A

    log_ok "Dev flake created at $FLAKE_DIR"
    log_info "Source: $SOURCE_FLAKE"
}

#===============================================================================
# Shell Integration
#===============================================================================
setup_shell_integration() {
    log_info "Setting up shell integration..."
    
    local FLAKE_DIR="$HOME/.config/nix-dev-env"
    local BASHRC="$HOME/.bashrc"
    local MARKER="# >>> nix-dev-env >>>"
    
    # Check if already configured
    if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
        log_ok "Shell integration already configured"
        return 0
    fi
    
    cat >> "$BASHRC" << SHELLEOF

$MARKER
# Nix daemon
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Auto-enter dev environment
dev() {
    nix develop "$FLAKE_DIR#\${1:-default}" -c \$SHELL
}

# Shortcut aliases
alias d='dev'
alias dm='dev minimal'
alias dp='dev python'

# Update dev environment
# - Pulls latest from nix-install repo
# - Syncs flake.nix to ~/.config/nix-dev-env
# - Updates flake.lock with latest packages
dev-update() {
    echo "🔄 Updating dev environment..."
    local REPO_DIR="\$HOME/.local/share/nix-install"

    # Pull latest from repo
    if [[ -d "\$REPO_DIR/.git" ]]; then
        echo "📥 Pulling latest from nix-install repo..."
        (cd "\$REPO_DIR" && git pull --quiet) || echo "⚠️  Failed to pull repo (continuing anyway)"
    fi

    # Sync flake.nix from repo to config
    local SOURCE_FLAKE="\$REPO_DIR/bootstrap-dev-server/flake.nix"
    if [[ -f "\$SOURCE_FLAKE" ]]; then
        echo "📋 Syncing flake.nix..."
        cp "\$SOURCE_FLAKE" "$FLAKE_DIR/flake.nix"
        (cd "$FLAKE_DIR" && git add -A)
    fi

    # Update flake.lock
    echo "⬆️  Updating Nix packages..."
    (cd "$FLAKE_DIR" && nix flake update)

    echo ""
    echo "✅ Dev environment updated!"
    echo "   Exit and run 'dev' to use new packages"
}

# Quick Claude access (runs in minimal env if not in dev shell)
claude-quick() {
    if command -v claude &>/dev/null; then
        claude "\$@"
    else
        nix run "$FLAKE_DIR#minimal" -- claude "\$@"
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

    local TMUX_CONF="$HOME/.tmux.conf"
    local MARKER="# >>> nix-dev-env tmux >>>"

    # Create symlink for zsh so tmux can find it
    # Nix zsh is only available in dev shell, so we symlink to /usr/local/bin
    local NIX_ZSH
    NIX_ZSH=$(find /nix/store -maxdepth 2 -name "zsh" -path "*/bin/zsh" 2>/dev/null | head -1)
    if [[ -n "$NIX_ZSH" ]] && [[ ! -e /usr/local/bin/zsh ]]; then
        log_info "Creating zsh symlink at /usr/local/bin/zsh..."
        sudo ln -sf "$NIX_ZSH" /usr/local/bin/zsh
        log_ok "Symlinked zsh to /usr/local/bin/zsh"
    fi

    # Check if already configured
    if grep -q "$MARKER" "$TMUX_CONF" 2>/dev/null; then
        log_ok "tmux already configured"
        return 0
    fi

    cat >> "$TMUX_CONF" << 'TMUXEOF'

# >>> nix-dev-env tmux >>>
# Use zsh as default shell (avoids bash completion errors)
set-option -g default-shell /usr/local/bin/zsh

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
    
    local CLAUDE_MD="$HOME/CLAUDE.md"
    
    if [[ -f "$CLAUDE_MD" ]]; then
        log_ok "CLAUDE.md already exists"
        return 0
    fi
    
    cat > "$CLAUDE_MD" << 'CLAUDEEOF'
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

    log_ok "CLAUDE.md template created at $CLAUDE_MD"
}

#===============================================================================
# Build Initial Nix Environment (warm cache)
#===============================================================================
warm_nix_cache() {
    log_info "Building Nix environment (this may take a few minutes on first run)..."
    
    local FLAKE_DIR="$HOME/.config/nix-dev-env"
    
    # Source Nix if not already available
    if ! command -v nix &>/dev/null; then
        if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
    fi
    
    # Build the default shell (downloads and caches all dependencies)
    cd "$FLAKE_DIR"
    nix build .#devShells.$(nix eval --impure --raw --expr 'builtins.currentSystem').default --no-link
    
    log_ok "Nix environment built and cached"
}

#===============================================================================
# Print Summary
#===============================================================================
print_summary() {
    local IP_ADDR
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Dev Server Bootstrap Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BLUE}Connection:${NC}"
    echo -e "    SSH:  ${YELLOW}ssh $DEV_USER@$IP_ADDR${NC}"
    echo -e "    Mosh: ${YELLOW}mosh $DEV_USER@$IP_ADDR${NC}"
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

    # Phase 1: Preflight and base packages
    preflight_checks
    install_base_packages

    # Phase 2: Git and GitHub setup
    install_github_cli
    configure_git_identity
    authenticate_github_cli
    clone_bootstrap_repo

    # Phase 3: Security hardening
    harden_ssh
    regenerate_host_keys
    configure_firewall
    configure_fail2ban
    install_tailscale
    install_auditd
    harden_sysctl
    harden_pam
    clean_old_kernels

    # Phase 4: Nix installation and configuration
    install_nix
    create_dev_flake
    setup_shell_integration
    configure_tmux
    create_claude_md
    warm_nix_cache

    # Done
    print_summary
}

# Run main function
main "$@"
