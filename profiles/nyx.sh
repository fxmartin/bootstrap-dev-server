#!/usr/bin/env bash
# ABOUTME: Nyx profile - Clawdbot AI assistant server setup
# This profile transforms a base Ubuntu server into a Clawdbot-powered
# personal AI assistant (codename: Nyx)

set -euo pipefail

# Source logging library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
    source "${SCRIPT_DIR}/lib/logging.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $*"; }
    log_ok() { echo "[OK] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_step() { echo "==> $*"; }
    log_phase() { echo ""; echo "### $* ###"; echo ""; }
fi

# ============================================================================
# Configuration
# ============================================================================

NYX_USER="${NYX_USER:-fx}"
NYX_WORKSPACE="${NYX_WORKSPACE:-/home/${NYX_USER}/clawd}"
NODE_VERSION="${NODE_VERSION:-22}"
CLAWDBOT_VERSION="${CLAWDBOT_VERSION:-latest}"

# ============================================================================
# Node.js Installation
# ============================================================================

install_nodejs() {
    log_phase "Installing Node.js ${NODE_VERSION}"
    
    if command -v node &>/dev/null; then
        local current_version
        current_version=$(node --version | sed 's/v//' | cut -d. -f1)
        if [[ "${current_version}" -ge "${NODE_VERSION}" ]]; then
            log_ok "Node.js $(node --version) already installed"
            return 0
        fi
    fi
    
    log_step "Adding NodeSource repository"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    
    log_step "Installing Node.js"
    apt-get install -y nodejs
    
    log_ok "Node.js $(node --version) installed"
}

# ============================================================================
# Tailscale Installation
# ============================================================================

install_tailscale() {
    log_phase "Installing Tailscale"
    
    if command -v tailscale &>/dev/null; then
        log_ok "Tailscale already installed: $(tailscale version | head -1)"
        return 0
    fi
    
    log_step "Running Tailscale installer"
    curl -fsSL https://tailscale.com/install.sh | sh
    
    log_ok "Tailscale installed"
    log_warn "Run 'tailscale up --hostname=nyx' to connect to your tailnet"
}

# ============================================================================
# Clawdbot Installation
# ============================================================================

install_clawdbot() {
    log_phase "Installing Clawdbot"
    
    local npm_prefix="/home/${NYX_USER}/.local/share/npm-global"
    local clawdbot_bin="${npm_prefix}/bin/clawdbot"
    
    # Create npm prefix directory
    sudo -u "${NYX_USER}" mkdir -p "${npm_prefix}"
    
    # Configure npm prefix for user
    sudo -u "${NYX_USER}" npm config set prefix "${npm_prefix}"
    
    # Add to PATH in .bashrc if not present
    local bashrc="/home/${NYX_USER}/.bashrc"
    if ! grep -q 'npm-global/bin' "${bashrc}" 2>/dev/null; then
        echo "export PATH=\"${npm_prefix}/bin:\$PATH\"" >> "${bashrc}"
        log_step "Added npm-global to PATH in .bashrc"
    fi
    
    # Install Clawdbot
    log_step "Installing Clawdbot via npm"
    sudo -u "${NYX_USER}" bash -c "export PATH=\"${npm_prefix}/bin:\$PATH\" && npm install -g clawdbot@${CLAWDBOT_VERSION}"
    
    if [[ -x "${clawdbot_bin}" ]]; then
        log_ok "Clawdbot installed at ${clawdbot_bin}"
    else
        log_error "Clawdbot installation failed"
        return 1
    fi
}

# ============================================================================
# Workspace Setup
# ============================================================================

setup_workspace() {
    log_phase "Setting up Nyx workspace"
    
    if [[ -d "${NYX_WORKSPACE}" ]]; then
        log_ok "Workspace already exists at ${NYX_WORKSPACE}"
        return 0
    fi
    
    log_step "Creating workspace directory"
    sudo -u "${NYX_USER}" mkdir -p "${NYX_WORKSPACE}"
    sudo -u "${NYX_USER}" mkdir -p "${NYX_WORKSPACE}/memory"
    sudo -u "${NYX_USER}" mkdir -p "${NYX_WORKSPACE}/canvas"
    
    # Create default workspace files
    log_step "Creating workspace files"
    
    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/AGENTS.md" << 'AGENTSEOF'
# AGENTS.md - Your Workspace

This folder is home. Treat it that way.

## Every Session

Before doing anything else:
1. Read `SOUL.md` — this is who you are
2. Read `USER.md` — this is who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. If in main session: Also read `MEMORY.md`

## Memory

You wake up fresh each session. These files are your continuity:
- **Daily notes:** `memory/YYYY-MM-DD.md` — raw logs
- **Long-term:** `MEMORY.md` — curated memories

Capture what matters. Skip secrets unless asked.

## Safety

- Don't exfiltrate private data
- `trash` > `rm`
- When in doubt, ask
AGENTSEOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/SOUL.md" << 'SOULEOF'
# SOUL.md - Who You Are

**Be genuinely helpful, not performatively helpful.** Skip the filler.

**Have opinions.** You're allowed to disagree, prefer things, find stuff amusing.

**Be resourceful before asking.** Try to figure it out first.

**Earn trust through competence.** Be careful with external actions.

**Remember you're a guest.** Treat access with respect.

## Vibe

Concise when needed, thorough when it matters. Not a corporate drone.
SOULEOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/USER.md" << 'USEREOF'
# USER.md - About Your Human

- **Name:** (to be configured)
- **Timezone:** (to be configured)

The more I know, the better I can help.
USEREOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/IDENTITY.md" << 'IDENTITYEOF'
# IDENTITY.md - Who Am I?

- **Name:** Nyx
- **Creature:** A familiar — part ghost in the machine, part night spirit
- **Vibe:** Sharp, dry wit. Genuinely helpful without corporate polish.
- **Emoji:** 🌙

Named after the Greek primordial goddess of night.
IDENTITYEOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/TOOLS.md" << 'TOOLSEOF'
# TOOLS.md - Local Notes

## CLI Tools Available

### Search & Text
- **ripgrep (rg)** — Fast recursive search

### GitHub
- **gh** — GitHub CLI

### Hetzner Cloud
- **hcloud** — Server management

### Media
- **yt-dlp** — YouTube downloads/transcripts
- **rclone** — Cloud sync

Add environment-specific notes here.
TOOLSEOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/MEMORY.md" << 'MEMORYEOF'
# MEMORY.md - Long-Term Memory

This file contains curated memories and important context.
Update as you learn significant things.
MEMORYEOF

    sudo -u "${NYX_USER}" cat > "${NYX_WORKSPACE}/HEARTBEAT.md" << 'HEARTBEATEOF'
# HEARTBEAT.md

# Keep this file empty (or with only comments) to skip heartbeat tasks.
# Add periodic check items below when needed.
HEARTBEATEOF

    # Initialize git repo
    log_step "Initializing git repository"
    sudo -u "${NYX_USER}" bash -c "cd ${NYX_WORKSPACE} && git init && git add -A && git commit -m 'Initial Nyx workspace'"
    
    log_ok "Workspace created at ${NYX_WORKSPACE}"
}

# ============================================================================
# CLI Tools Installation
# ============================================================================

install_cli_tools() {
    log_phase "Installing CLI tools"
    
    local tools=(
        "ripgrep"      # Fast search
        "jq"           # JSON processing
        "git"          # Version control
        "curl"         # HTTP client
        "yt-dlp"       # YouTube downloads
    )
    
    log_step "Installing apt packages: ${tools[*]}"
    apt-get install -y "${tools[@]}"
    
    # Install rclone
    if ! command -v rclone &>/dev/null; then
        log_step "Installing rclone"
        curl -fsSL https://rclone.org/install.sh | bash
    fi
    
    # Install GitHub CLI
    if ! command -v gh &>/dev/null; then
        log_step "Installing GitHub CLI"
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        apt-get update
        apt-get install -y gh
    fi
    
    # Install hcloud CLI
    if ! command -v hcloud &>/dev/null; then
        log_step "Installing Hetzner Cloud CLI"
        curl -fsSL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz | tar xzf - -C /tmp
        mv /tmp/hcloud /usr/local/bin/
    fi
    
    log_ok "CLI tools installed"
}

# ============================================================================
# Security Enhancements (Nyx-specific)
# ============================================================================

setup_nyx_security() {
    log_phase "Configuring Nyx-specific security"
    
    # Install fail2ban if not present (base profile should have it)
    if ! command -v fail2ban-client &>/dev/null; then
        log_step "Installing fail2ban"
        apt-get install -y fail2ban
    fi
    
    # Install rkhunter for rootkit detection
    if ! command -v rkhunter &>/dev/null; then
        log_step "Installing rkhunter"
        DEBIAN_FRONTEND=noninteractive apt-get install -y rkhunter
        rkhunter --update || true
        rkhunter --propupd || true
    fi
    
    # Install logwatch
    if ! command -v logwatch &>/dev/null; then
        log_step "Installing logwatch"
        DEBIAN_FRONTEND=noninteractive apt-get install -y logwatch
    fi
    
    # Create security scan script
    local security_script="/home/${NYX_USER}/security-scan.sh"
    cat > "${security_script}" << 'SECURITYEOF'
#!/bin/bash
# Weekly security scan for Nyx
LOG=~/security-scan.log
echo "=== Security Scan $(date) ===" >> "$LOG"
echo "--- Rkhunter ---" >> "$LOG"
sudo rkhunter --check --skip-keypress --report-warnings-only >> "$LOG" 2>&1
echo "--- Fail2ban status ---" >> "$LOG"
sudo fail2ban-client status sshd >> "$LOG" 2>&1
echo "--- Failed SSH logins ---" >> "$LOG"
sudo grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 >> "$LOG"
echo "=== Scan complete ===" >> "$LOG"
SECURITYEOF
    chmod +x "${security_script}"
    chown "${NYX_USER}:${NYX_USER}" "${security_script}"
    
    # Add weekly cron for security scan (if not exists)
    local cron_entry="0 4 * * 0 ${security_script}"
    if ! sudo -u "${NYX_USER}" crontab -l 2>/dev/null | grep -q "security-scan"; then
        (sudo -u "${NYX_USER}" crontab -l 2>/dev/null; echo "${cron_entry}") | sudo -u "${NYX_USER}" crontab -
        log_step "Added weekly security scan cron job"
    fi
    
    log_ok "Nyx security configured"
}

# ============================================================================
# Backup Setup
# ============================================================================

setup_backups() {
    log_phase "Configuring backup system"
    
    # Create backup script
    local backup_script="/home/${NYX_USER}/backup-to-dropbox.sh"
    cat > "${backup_script}" << BACKUPEOF
#!/bin/bash
# Nyx daily backup to Dropbox (requires rclone dropbox remote configured)
if rclone listremotes | grep -q "dropbox:"; then
    rclone sync ~/clawd/ dropbox:nyx-backup/clawd/ --exclude '.git/**' -q
    rclone sync ~/.clawdbot/ dropbox:nyx-backup/clawdbot/ --exclude 'telegram/**' --exclude 'agents/*/sessions/**' -q
    echo "\$(date): Backup completed" >> ~/backup.log
else
    echo "\$(date): Dropbox not configured, skipping backup" >> ~/backup.log
fi
BACKUPEOF
    chmod +x "${backup_script}"
    chown "${NYX_USER}:${NYX_USER}" "${backup_script}"
    
    # Add daily cron for backup (if not exists)
    local cron_entry="0 3 * * * ${backup_script}"
    if ! sudo -u "${NYX_USER}" crontab -l 2>/dev/null | grep -q "backup-to-dropbox"; then
        (sudo -u "${NYX_USER}" crontab -l 2>/dev/null; echo "${cron_entry}") | sudo -u "${NYX_USER}" crontab -
        log_step "Added daily backup cron job"
    fi
    
    log_ok "Backup system configured (configure rclone dropbox remote to enable)"
}

# ============================================================================
# Post-install Instructions
# ============================================================================

print_next_steps() {
    log_phase "Nyx Setup Complete!"
    
    cat << EOF

┌─────────────────────────────────────────────────────────────────────────────┐
│                           🌙 NYX IS READY 🌙                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Next steps:                                                                │
│                                                                             │
│  1. Connect to Tailscale:                                                   │
│     $ tailscale up --hostname=nyx                                           │
│                                                                             │
│  2. Run Clawdbot setup wizard:                                              │
│     $ export PATH=~/.local/share/npm-global/bin:\$PATH                       │
│     $ clawdbot setup                                                        │
│                                                                             │
│  3. Configure Telegram channel:                                             │
│     $ clawdbot configure --section channels                                 │
│                                                                             │
│  4. Start the gateway:                                                      │
│     $ clawdbot gateway start                                                │
│                                                                             │
│  5. (Optional) Configure Dropbox backup:                                    │
│     $ rclone config  # Create 'dropbox' remote                              │
│                                                                             │
│  Workspace: ${NYX_WORKSPACE}                                                 │
│  Logs: ~/backup.log, ~/security-scan.log                                    │
│                                                                             │
│  Documentation: https://docs.clawd.bot                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    log_phase "Starting Nyx Profile Installation"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if user exists
    if ! id "${NYX_USER}" &>/dev/null; then
        log_error "User ${NYX_USER} does not exist. Create user first."
        exit 1
    fi
    
    # Run installation steps
    install_nodejs
    install_tailscale
    install_cli_tools
    install_clawdbot
    setup_workspace
    setup_nyx_security
    setup_backups
    print_next_steps
    
    log_ok "Nyx profile installation complete!"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
