# Profiles

Profiles allow you to customize the server setup for different use cases.

## Available Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| `dev` | Default - Full dev environment with Nix, Claude Code | Development work |
| `nyx` | Clawdbot AI assistant server | Personal AI assistant |
| `full` | Both dev + nyx combined | Everything |

## Usage

### With hcloud-provision.sh

```bash
# Dev server (default)
./hcloud-provision.sh --name dev-server

# Nyx AI assistant
./hcloud-provision.sh --name nyx --profile nyx

# Full setup (dev + nyx)
./hcloud-provision.sh --name fullstack --profile full
```

### Standalone Profile Installation

On an existing server with base packages installed:

```bash
# Run nyx profile only
sudo ./profiles/nyx.sh

# Or source and call specific functions
source ./profiles/nyx.sh
install_clawdbot
```

## Profile: nyx

The Nyx profile transforms a base Ubuntu server into a Clawdbot-powered personal AI assistant.

### What Gets Installed

| Component | Description |
|-----------|-------------|
| **Node.js 22** | Runtime for Clawdbot |
| **Clawdbot** | AI assistant framework |
| **Tailscale** | Mesh VPN for secure access |
| **rclone** | Cloud backup (Dropbox, etc.) |
| **CLI tools** | ripgrep, jq, gh, hcloud, yt-dlp |
| **Security** | rkhunter, logwatch, fail2ban |

### Workspace Structure

```
~/clawd/
├── AGENTS.md      # Agent behavior instructions
├── SOUL.md        # Personality/identity
├── USER.md        # User context (customize this)
├── IDENTITY.md    # Bot identity
├── MEMORY.md      # Long-term memory
├── TOOLS.md       # Tool-specific notes
├── HEARTBEAT.md   # Periodic task config
└── memory/        # Daily memory logs
```

### Automated Tasks

| Schedule | Task | Script |
|----------|------|--------|
| Daily 3:00 AM | Dropbox backup | `~/backup-to-dropbox.sh` |
| Sunday 4:00 AM | Security scan | `~/security-scan.sh` |

### Post-Install Steps

1. Connect to Tailscale:
   ```bash
   tailscale up --hostname=nyx
   ```

2. Run Clawdbot setup:
   ```bash
   export PATH=~/.local/share/npm-global/bin:$PATH
   clawdbot setup
   ```

3. Configure Telegram:
   ```bash
   clawdbot configure --section channels
   ```

4. Start gateway:
   ```bash
   clawdbot gateway start
   ```

5. (Optional) Configure Dropbox:
   ```bash
   rclone config  # Create 'dropbox' remote
   ```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NYX_USER` | `fx` | Username for Clawdbot |
| `NYX_WORKSPACE` | `/home/$NYX_USER/clawd` | Workspace directory |
| `NODE_VERSION` | `22` | Node.js major version |
| `CLAWDBOT_VERSION` | `latest` | Clawdbot npm version |

## Creating New Profiles

1. Create `profiles/yourprofile.sh`
2. Follow the template structure (see `nyx.sh`)
3. Source `lib/logging.sh` for consistent logging
4. Make functions idempotent (safe to run multiple times)
5. Add documentation to this README
