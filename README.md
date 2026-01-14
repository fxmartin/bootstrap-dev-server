# Claude Code Dev Server

A single-command bootstrap that transforms a fresh Ubuntu 24.04 server into a fully hardened, Nix-powered development environment with Claude Code.

---

## Why a Remote Dev Server?

**Claude Code is CLI-first.** Unlike traditional IDEs with desktop apps, Claude Code runs entirely in the terminal. This creates an opportunity: *your development environment can live anywhere*.

I manage multiple MacBooks and found myself constantly context-switching between machines, losing track of where my latest code changes lived. The solution? A **persistent cloud dev server** that I can access from anywhere:

- **From my MacBook Pro** via Terminal or Ghostty
- **From my MacBook Air** when traveling light
- **From my iPad** via [Blink Shell](https://blink.sh/) on the couch or in a café
- **From any machine** with an SSH client

The server maintains the **single source of truth** for all my projects. No more "which laptop has the latest changes?" Every session picks up exactly where I left off.

### The Benefits

| Benefit | Description |
|---------|-------------|
| **Always Available** | Your dev environment is always on, always accessible |
| **Single Source of Truth** | All projects, all progress, one location |
| **Device Agnostic** | SSH from Mac, iPad, Linux, Windows—anything |
| **Persistent Sessions** | Mosh + tmux = sessions that survive disconnects |
| **Consistent Environment** | Same tools, same config, every time |
| **Cost Effective** | ~€5.50/month for a CX33 (less than two coffees) |

---

## Quick Start: Hetzner Cloud

The recommended approach is a Hetzner Cloud VPS. It's affordable, reliable, and the automated provisioning script handles everything.

### Prerequisites

```bash
# Install hcloud CLI
brew install hcloud jq    # macOS
# or: snap install hcloud && sudo apt install jq (Linux)

# The script will generate a dedicated SSH key if needed
```

### One Command Provisioning

```bash
# Download and run the provisioning script
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/hcloud-provision.sh -o hcloud-provision.sh
chmod +x hcloud-provision.sh
./hcloud-provision.sh
```

The script will:
1. Generate a dedicated SSH key (`~/.ssh/id_devserver`) if needed
2. Authenticate with Hetzner Cloud API (prompts for token)
3. Upload your SSH key
4. Create a server with Ubuntu 24.04 (CX33 by default)
5. Create your user account with sudo access
6. Run the full bootstrap script
7. Print connection instructions

### Connect and Start Coding

```bash
ssh myserver          # Uses the SSH config created by provisioning
dev                   # Enter the Nix dev environment
claude                # Start Claude Code
```

That's it. You're coding in the cloud.

---

## Hetzner Cloud Setup (Detailed)

### Provisioning Options

```bash
# Custom server name
./hcloud-provision.sh --name my-dev-server

# Different datacenter (US East for North America)
./hcloud-provision.sh --location ash

# Default server (recommended for multi-agent Claude Code)
./hcloud-provision.sh --type cx33

# Larger server for heavier workloads
./hcloud-provision.sh --type cx43

# AMD server with more disk space
./hcloud-provision.sh --type cpx22

# Custom SSH port (default: 22)
./hcloud-provision.sh --ssh-port 22222

# GeoIP country whitelist (default: disabled)
./hcloud-provision.sh --geoip-countries "LU,FR,GR"

# Disable GeoIP blocking explicitly
./hcloud-provision.sh --no-geoip

# Auto-confirm (no prompts)
./hcloud-provision.sh --yes

# Skip bootstrap (just create server)
./hcloud-provision.sh --no-bootstrap

# List all your servers
./hcloud-provision.sh --list

# Rescale existing server to larger type (keeps data)
./hcloud-provision.sh --rescale dev-server --type cx33

# Delete a server
./hcloud-provision.sh --delete my-dev-server
```

### Available Locations

| Code | Location | Region | Best For |
|------|----------|--------|----------|
| `fsn1` | Falkenstein | Germany (EU) | Europe |
| `nbg1` | Nuremberg | Germany (EU) | Europe |
| `hel1` | Helsinki | Finland (EU) | Northern Europe |
| `ash` | Ashburn | Virginia (US) | US East Coast |
| `hil` | Hillsboro | Oregon (US) | US West Coast |
| `sin` | Singapore | Asia | Asia-Pacific |

### Server Types

**x86 Intel Gen3 (cost optimized, RECOMMENDED):**
| Type | vCPU | RAM | SSD | Monthly Cost |
|------|------|-----|-----|--------------|
| `cx23` | 2 | 4 GB | 40 GB | ~€3.50 |
| `cx33` | 4 | 8 GB | 80 GB | ~€5.50 ⭐ RECOMMENDED |
| `cx43` | 8 | 16 GB | 160 GB | ~€13.50 |
| `cx53` | 16 | 32 GB | 320 GB | ~€26.90 |

**x86 AMD Gen2 (more disk space):**
| Type | vCPU | RAM | SSD | Monthly Cost |
|------|------|-----|-----|--------------|
| `cpx22` | 2 | 4 GB | 80 GB | ~€7.00 |
| `cpx32` | 4 | 8 GB | 160 GB | ~€13.50 |
| `cpx42` | 8 | 16 GB | 320 GB | ~€26.90 |

**ARM Ampere (best value, ARM-compatible software only):**
| Type | vCPU | RAM | SSD | Monthly Cost |
|------|------|-----|-----|--------------|
| `cax11` | 2 | 4 GB | 40 GB | ~€3.85 |
| `cax21` | 4 | 8 GB | 80 GB | ~€7.25 |
| `cax31` | 8 | 16 GB | 160 GB | ~€13.95 |

**⚠️ Deprecated (unavailable after 2025-12-31):**
- Intel Gen1/Gen2: `cx11`, `cx22`, `cx32`, `cx42`, `cx52`
- AMD Gen1: `cpx11`, `cpx21`, `cpx31`, `cpx41`, `cpx51`

> **Recommendation**: Start with `cx33` for Claude Code multi-agent workflows. The 4 vCPU and 8GB RAM handles 5-8 parallel subagents smoothly (Explore, Plan, etc.), while CX23's 2 vCPU/4GB hits swap with 3+ concurrent agents. At only €2/month more (~€5.50 vs €3.50), it's the sweet spot for serious Claude Code usage. Use `cx23` only for single-agent work or budget constraints. Use AMD (`cpx22`) if you need more disk space, or ARM (`cax11`) for best value if your software supports ARM.

### Environment Variables

```bash
# Skip interactive API token prompt
export HCLOUD_TOKEN="your-api-token"

# Customize defaults
export SERVER_NAME="my-server"
export SERVER_LOCATION="ash"
export SSH_USER="developer"

./hcloud-provision.sh
```

### Manual Setup via Console

If you prefer manual control, see [Manual Hetzner Setup](#appendix-a-manual-hetzner-setup).

---

## What Gets Installed

The bootstrap script transforms a bare Ubuntu 24.04 server into a complete dev environment:

### Security Hardening
- **SSH hardened**: Key-only auth, no root login, strong ciphers, configurable port
- **UFW firewall**: SSH and Mosh only, with rate limiting (blocks after 6 connections/30s)
- **GeoIP blocking**: Country-based whitelist via geoip-shell (nftables backend)
- **Fail2Ban**: 24-hour bans after 3 failed attempts
- **Unattended upgrades**: Automatic Ubuntu security patches (daily check, auto-reboot at 4am if needed, email on error)
- **Tailscale**: VPN mesh network for secure access from anywhere (bypass for GeoIP)
- **auditd**: System auditing with rules for identity, sudo, SSH, cron, and PAM changes
- **Kernel hardening**: sysctl settings for ICMP, SYN flood protection, martian logging
- **PAM hardening**: Empty passwords disallowed (nullok removed)
- **Daily security report**: Email summary of Fail2Ban, SSH, UFW, and audit events (7am daily)

### Development Environment
- **Claude Code** with auto-updates
- **MCP Servers**: Context7, GitHub, Sequential Thinking
- **tmux** auto-launches on SSH connection
- **Weekly Nix updates**: Systemd timer updates flake.lock every Sunday at 3am (email summary)

#### Python/FastAPI Stack
- Python 3.12, uv, pip, virtualenv
- Linting: ruff, black, isort, mypy, pylint
- Testing: pytest, pytest-asyncio, pytest-cov, httpx
- Debugging: ipython, rich
- Code quality: pre-commit

#### React/Frontend Stack
- Node.js 22 LTS
- Package managers: bun, pnpm
- TypeScript + typescript-language-server
- Linting/formatting: eslint, prettier

#### Nix Development
- nil (Nix LSP)
- nixfmt-rfc-style
- nix-tree, nix-diff

#### Shell Development
- shellcheck, shfmt, bats

#### Containers
- Podman (rootless)
- podman-compose

#### General Development Tools
- Task runner: just
- File watcher: watchexec
- Code stats: tokei
- Syntax-aware diff: difftastic

#### CLI Productivity
- Search: ripgrep, fd, fzf
- File viewing: bat, eza, tree
- Git: lazygit, delta, git-lfs
- Other: jq, yq, httpie, websocat, glow
- Shell: zsh, starship, zoxide, direnv, tmux

#### Editors
- Neovim, Helix

### Available Commands

| Command | Description |
|---------|-------------|
| `dev` | Enter full dev environment |
| `dev minimal` | Minimal environment (Claude + basics) |
| `dev python` | Python-focused environment |
| `dev-update` | Pull latest from repo + update Nix packages |
| `claude` | Start Claude Code |

---

## Real-World Timing

Actual bootstrap timing from a CX33 server in Falkenstein (fsn1), December 2025:

| Phase | Description | Duration |
|-------|-------------|----------|
| 1 | Preflight & Base Packages | ~36s |
| 2 | Git & GitHub Setup | ~70s |
| 3 | Security Hardening | ~53s |
| 4 | Nix Installation | ~217s (3m 37s) |
| 5 | Final SSH Configuration | instant |
| **Total** | **Full bootstrap** | **~6-7 minutes** |

> **Note**: Phase 4 (Nix) takes the longest as it downloads and caches all development packages (~140 packages). Subsequent runs are much faster due to caching.

### SSH Disconnection During Bootstrap

The SSH connection may drop during Phase 3 (Security Hardening) due to firewall configuration or GeoIP blocking. **This is expected behavior** and the script is designed to handle it:

1. **Wait 30 seconds** for security services to stabilize
2. **Reconnect** via SSH:
   ```bash
   ssh your-server-name
   ```
3. **Re-run the bootstrap** (it's idempotent):
   ```bash
   cd ~/.local/share/bootstrap-dev-server
   ./bootstrap-dev-server.sh
   ```

The script detects what's already configured and skips completed steps. You'll see messages like:
- `GitHub CLI already installed`
- `SSH hardening already configured`
- `Firewall configured`

### Post-Bootstrap: Tailscale Authentication

Tailscale is installed but requires authentication. After bootstrap completes:

```bash
sudo tailscale up --ssh
```

This displays a URL to authenticate with your Tailscale account. The `--ssh` flag enables Tailscale SSH, allowing you to connect without SSH keys from any device on your Tailnet.

Once connected, you can access your server via Tailscale IP which bypasses GeoIP restrictions:

```bash
# Get your server's Tailscale IP
tailscale ip -4   # Shows 100.x.x.x

# Connect from any device on your Tailnet
ssh fx@100.x.x.x
```

---

## Accessing from iPad with Blink Shell

[Blink Shell](https://blink.sh/) is a professional SSH client for iOS/iPadOS with Mosh support.

### Setup

1. **Install Blink** from the App Store

2. **Copy your SSH private key to iPad**

   **Option A: AirDrop (Recommended)**
   ```bash
   # On your Mac, open the key in Finder for AirDrop
   open -R ~/.ssh/id_devserver
   # Right-click → Share → AirDrop → Select your iPad
   # On iPad: Save to Files app
   ```

   **Option B: Copy via clipboard (if same iCloud account)**
   ```bash
   # On Mac, copy the private key content
   cat ~/.ssh/id_devserver | pbcopy
   # On iPad in Blink: Settings → Keys → + → Create New
   # Name: devserver
   # Paste the key content in the "Private Key" field
   ```

   **Option C: iCloud Drive**
   ```bash
   # Copy to iCloud Drive (temporary - delete after import!)
   cp ~/.ssh/id_devserver ~/Library/Mobile\ Documents/com~apple~CloudDocs/
   # On iPad: Files app → iCloud Drive → select the key
   # After importing to Blink, DELETE from iCloud Drive for security
   ```

3. **Import key in Blink**:
   - Settings → Keys → + (Add)
   - If using AirDrop/iCloud: "Import from File" → select the key
   - If using clipboard: "Create New" → paste content
   - Name it: `devserver`

4. **Create a host**:
   - Settings → Hosts → + (Add Host)
   - Alias: `dev` (or whatever you like)
   - Hostname: Your server IP or domain
   - User: `fx` (your username)
   - Key: Select `devserver`
   - Port: 22

5. **Connect**:
   ```
   mosh dev
   ```

> **Security Note**: After copying your key to iPad, delete any temporary copies (iCloud Drive, Downloads). The key should only exist in Blink's secure storage and on your Mac.

### Why Mosh?

Mosh (Mobile Shell) is essential for mobile development:
- **Survives disconnects**: WiFi drops, cellular handoffs, iPad sleep
- **Instant echo**: Characters appear immediately, no lag feeling
- **Roaming**: Change networks without reconnecting

```bash
# From your Mac or iPad
mosh myserver
```

---

## Cost-Free Local Alternatives

If you want to test the setup locally before committing to a cloud server, or prefer local development:

### Option 1: Docker/Podman Container

The fastest way to try the environment locally:

```bash
# Using Docker
docker run -it --name claude-dev ubuntu:24.04 bash

# Or using Podman (rootless)
podman run -it --name claude-dev ubuntu:24.04 bash

# Inside the container, run the bootstrap
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | bash
```

**Pros**: Quick, disposable, no VM overhead
**Cons**: No Mosh (container networking), ephemeral by default

To persist your work:
```bash
# Create with volume mount
docker run -it -v ~/projects:/home/fx/projects --name claude-dev ubuntu:24.04 bash
```

### Option 2: Parallels Desktop VM (macOS)

For a more production-like local environment:

1. **Download Ubuntu Server 24.04** from [ubuntu.com/download/server](https://ubuntu.com/download/server)

2. **Create VM** in Parallels:
   - 2 CPU, 2-4GB RAM, 20GB disk
   - Network: Shared (for SSH access from Mac)

3. **Install Ubuntu Server** (not Desktop—we want lean)

4. **Copy SSH key and bootstrap**:
   ```bash
   # From Mac terminal
   ssh-keygen -t ed25519 -f ~/.ssh/id_devserver  # if not exists
   ssh-copy-id -i ~/.ssh/id_devserver fx@<VM_IP>

   # SSH in and bootstrap
   ssh fx@<VM_IP>
   curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | bash
   ```

**Pros**: Full VM isolation, Mosh works, matches cloud setup exactly
**Cons**: Uses local resources, not accessible from other devices

See [Appendix B: Parallels VM Setup](#appendix-b-parallels-vm-setup) for detailed steps.

---

## Post-Installation

### MCP Server Configuration

Claude Code MCP servers are automatically configured:

- **Context7**: Documentation lookup (no auth required)
- **GitHub**: Repository access (requires Personal Access Token)
- **Sequential Thinking**: Enhanced reasoning (no auth required) - *currently disabled due to [upstream build issue](https://github.com/natsukium/mcp-servers-nix/issues/285); fix pending in [PR #276](https://github.com/natsukium/mcp-servers-nix/pull/276) (Node.js 22 pinning)*

**To configure GitHub MCP server:**

1. Create a GitHub Personal Access Token:
   - Visit: https://github.com/settings/tokens
   - Scopes: `repo`, `read:org`, `read:user`

2. Add token to config:
   ```bash
   nano ~/.claude.json
   # Find "github" → "env", replace YOUR_TOKEN_HERE:
   "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
   ```

3. Verify:
   ```bash
   dev
   claude mcp list
   ```

### Project-Specific Environments

Create a `flake.nix` in any project for custom dependencies:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          postgresql
          redis
        ];
      };
    };
}
```

Then:
```bash
cd your-project
nix develop
```

---

## SSH Key Security

This project uses a **dedicated SSH key** (`~/.ssh/id_devserver`) for dev server access, separate from your GitHub or other service keys.

### Why a Dedicated Key?

| Benefit | Description |
|---------|-------------|
| **Isolation** | Compromised key doesn't affect GitHub, GitLab, etc. |
| **Auditability** | Easy to identify dev server access |
| **Rotation** | Rotate without affecting other services |

### Adding a Passphrase (Recommended)

The provisioning script creates the key without a passphrase for automation. Add one after:

```bash
# Use the helper script
./scripts/secure-ssh-key.sh

# Or manually
ssh-keygen -p -f ~/.ssh/id_devserver

# Add to ssh-agent with Keychain (macOS)
ssh-add --apple-use-keychain ~/.ssh/id_devserver
```

### SSH Config Security

The provisioning script creates secure SSH config entries:

```
Host myserver
    HostName 1.2.3.4
    User fx
    IdentityFile ~/.ssh/id_devserver
    IdentitiesOnly yes         # Only use specified key
    AddKeysToAgent yes         # Auto-add to ssh-agent
    UseKeychain yes            # Store passphrase in Keychain
    ForwardAgent no            # Don't forward agent (security)
```

---

## Security Notes

### SSH Configuration

After bootstrap, SSH is hardened:
- **Key-only authentication** (passwords disabled)
- **Root login disabled**
- **Strong ciphers**: chacha20-poly1305, aes256-gcm
- **Max 3 auth attempts**
- **30-second login grace period**

### Firewall Rules

**UFW** allows only:
- SSH (configurable port, default 22) with rate limiting
- Mosh (UDP 60000-60010)

**Rate limiting**: Blocks IP addresses after 6 connection attempts within 30 seconds. This protects against brute-force attacks while allowing legitimate reconnections.

**GeoIP blocking** (optional): When enabled, only allows connections from whitelisted countries. Uses nftables backend with daily IP database updates. Tailscale provides bypass access if you get locked out.

### Fail2Ban

- **3 failed attempts** → 24-hour ban
- Monitors `/var/log/auth.log`

### Daily Security Report

During bootstrap, you'll be prompted to configure SMTP settings for daily security emails. The report includes:

| Section | Metrics |
|---------|---------|
| **Fail2Ban** | Banned IPs (24h), currently banned, IP list |
| **SSH** | Failed attempts, invalid users, accepted logins |
| **UFW** | Blocked connections count |
| **Audit** | PAM failures, sudo usage, config changes |
| **System** | Uptime, load average, disk usage |

**Test commands:**
```bash
# Preview report without sending
sudo /usr/local/bin/security-report.sh --stdout

# Send test email
sudo /usr/local/bin/security-report.sh --test

# Send full report now
sudo /usr/local/bin/security-report.sh

# Check msmtp log
sudo cat /var/log/msmtp.log

# Verify cron job
sudo crontab -l | grep security
```

The report is sent daily at **7am Europe/Paris** via msmtp (installed from Nix flake).

---

## Troubleshooting

### Bootstrap disconnected mid-way

This is normal during Phase 3 (Security Hardening). See [SSH Disconnection During Bootstrap](#ssh-disconnection-during-bootstrap) for recovery steps. The script is idempotent - just reconnect and re-run it.

### Can't SSH after running script

SSH key must be copied **before** bootstrap (it disables password auth):
```bash
ssh-copy-id -i ~/.ssh/id_devserver user@server-ip
```

If locked out: Use Hetzner rescue mode or VM console.

### Claude Code authentication

First run requires OAuth:
```bash
dev
claude  # Provides URL for headless auth
```

### Nix command not found

Source the profile or reconnect:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Slow first `nix develop`

First run downloads packages. Subsequent runs are instant. Pre-warm with:
```bash
cd ~/.config/nix-dev-env
nix build .#devShells.x86_64-linux.default --no-link
```

### New packages not available after updating flake.nix

The dev shell is loaded once when you enter it. After updating `flake.nix`:
```bash
exit    # Exit current dev shell
dev     # Re-enter to load new packages
```

Since `~/.config/nix-dev-env` is a symlink to the repo, changes to `flake.nix` are picked up immediately - you just need a fresh shell session.

### Locked out by GeoIP blocking

If you're traveling and can't connect from a whitelisted country:

1. **Use Tailscale** (recommended): Connect via Tailscale IP which bypasses GeoIP
   ```bash
   ssh fx@100.x.x.x  # Your server's Tailscale IP
   ```

2. **Hetzner Console**: Use VNC access via the Hetzner Cloud web console

3. **Temporarily disable GeoIP** (from console or Tailscale):
   ```bash
   sudo geoip-shell off
   ```

4. **Add a country temporarily**:
   ```bash
   sudo geoip-shell configure -z -m whitelist -c "LU FR GR US" -i all -l none
   ```

5. **Check GeoIP status**:
   ```bash
   sudo geoip-shell status
   ```

### SSH connection refused on custom port

If using a non-standard SSH port and can't connect:

1. Verify the port is open in UFW:
   ```bash
   sudo ufw status | grep <port>
   ```

2. Check SSH is listening on the correct port:
   ```bash
   sudo ss -tlnp | grep sshd
   ```

3. Verify ssh.socket is disabled (Ubuntu 24.04):
   ```bash
   sudo systemctl status ssh.socket  # Should be inactive
   ```

---

## Configuration Options

Environment variables for the bootstrap script:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEV_USER` | Current user | Username for setup |
| `SSH_PORT` | 22 | SSH port (use non-standard like 22222 for security) |
| `MOSH_PORT_START` | 60000 | Mosh UDP range start |
| `MOSH_PORT_END` | 60010 | Mosh UDP range end |
| `REGEN_HOST_KEYS` | false | Regenerate SSH host keys |
| `UFW_RATE_LIMIT` | true | Enable UFW rate limiting for SSH |
| `GEOIP_ENABLED` | true | Enable GeoIP country-based blocking |
| `GEOIP_COUNTRIES` | LU,FR,GR | Comma-separated whitelist of country codes |

### GeoIP Country Codes

Common country codes for the whitelist:
- **EU**: DE (Germany), FR (France), NL (Netherlands), BE (Belgium), LU (Luxembourg), AT (Austria), CH (Switzerland)
- **Nordic**: FI (Finland), SE (Sweden), NO (Norway), DK (Denmark)
- **Southern EU**: ES (Spain), IT (Italy), PT (Portugal), GR (Greece)
- **UK/Ireland**: GB (United Kingdom), IE (Ireland)
- **Americas**: US (United States), CA (Canada)
- **Asia-Pacific**: JP (Japan), AU (Australia), SG (Singapore)

Example for European access only:
```bash
GEOIP_COUNTRIES="DE,FR,NL,BE,LU,AT,CH,GB,IE" ./bootstrap-dev-server.sh
```

### Logging Configuration

All scripts use a unified logging library with timestamps, log levels, and optional file output.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | INFO | Minimum level: DEBUG, INFO, WARN, ERROR |
| `LOG_FILE` | (auto) | Path to log file |
| `LOG_DIR` | `~/.local/log/bootstrap` | Directory for auto-created logs |
| `LOG_TIMESTAMPS` | true | Include timestamps in output |
| `NO_COLOR` | (unset) | Disable colored output |

**View logs:**
```bash
# List recent logs
ls -la ~/.local/log/bootstrap/

# Follow latest bootstrap log
tail -f ~/.local/log/bootstrap/bootstrap-dev-server-*.log

# View provisioning log
tail -f ~/.local/log/bootstrap/hcloud-provision-*.log
```

---

## File Structure

After installation:

```
~
├── .claude.json               # Claude Code config (includes MCP servers)
├── .claude/
│   ├── agents/                # Custom agent definitions (symlinked)
│   └── commands/              # Custom slash commands (symlinked)
├── .config/
│   └── nix-dev-env -> ~/.local/share/bootstrap-dev-server  # Symlink!
├── .local/
│   ├── log/bootstrap/         # Log files from bootstrap and provisioning
│   │   ├── bootstrap-dev-server-YYYYMMDD-HHMMSS.log
│   │   └── hcloud-provision-YYYYMMDD-HHMMSS.log
│   └── share/bootstrap-dev-server/  # Clone of this repo
│       ├── flake.nix          # Dev environment definition
│       ├── flake.lock         # Locked package versions
│       ├── lib/
│       │   └── logging.sh     # Shared logging library
│       ├── scripts/
│       │   └── secure-ssh-key.sh  # Add passphrase to SSH key
│       └── tests/
│           └── verify-server.sh   # Post-install verification
├── .bashrc                    # Shell integration
├── CLAUDE.md                  # Claude Code instructions
└── projects/                  # Your projects
```

**Note**: `~/.config/nix-dev-env` is a symlink to the repo. Changes to `flake.nix` are reflected immediately (after re-entering the dev shell with `dev`).

---

## Appendix A: Manual Hetzner Setup

If you prefer manual control over automated provisioning:

### Step 1: Create SSH Key

```bash
ssh-keygen -t ed25519 -C "devserver-$(date +%Y%m%d)" -f ~/.ssh/id_devserver
cat ~/.ssh/id_devserver.pub | pbcopy  # Copy to clipboard
```

### Step 2: Add Key to Hetzner

1. Log into [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Go to **Security** → **SSH Keys** → **Add SSH Key**
3. Paste your public key

### Step 3: Create Server

1. **Servers** → **Add Server**
2. **Location**: Choose nearest (fsn1 for EU, ash for US East)
3. **Image**: Ubuntu 24.04
4. **Type**: CX33 (recommended) or CX23 for budget
5. **SSH Key**: Select yours
6. **Name**: `dev-server`
7. **Create & Buy now**

### Step 4: Connect and Bootstrap

```bash
# Connect as root initially
ssh -i ~/.ssh/id_devserver root@YOUR_SERVER_IP

# Create your user
adduser fx
usermod -aG sudo fx
mkdir -p /home/fx/.ssh
cp ~/.ssh/authorized_keys /home/fx/.ssh/
chown -R fx:fx /home/fx/.ssh
chmod 700 /home/fx/.ssh
chmod 600 /home/fx/.ssh/authorized_keys

# Switch to user and bootstrap
su - fx
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | bash
```

### Step 5: Reconnect

```bash
# Disconnect and reconnect as your user (not root!)
ssh -i ~/.ssh/id_devserver fx@YOUR_SERVER_IP

# Or add to SSH config for convenience
cat >> ~/.ssh/config << EOF

Host dev-server
    HostName YOUR_SERVER_IP
    User fx
    IdentityFile ~/.ssh/id_devserver
    IdentitiesOnly yes
    ForwardAgent no
EOF

ssh dev-server
```

### Hetzner Tips

- **Snapshots**: Create before major changes (€0.01/GB/month)
- **Backups**: Enable automatic backups (20% of server price)
- **Firewall**: Hetzner has its own firewall (Security → Firewalls)
- **Rescue Mode**: If locked out, enable rescue mode to fix issues

---

## Appendix B: Parallels VM Setup

Detailed instructions for setting up a local VM with Parallels Desktop on macOS.

### Prerequisites

- macOS 11+ (Big Sur or later)
- Parallels Desktop 18+
- 20GB+ free disk space

### Step 1: Download Ubuntu Server

1. Go to [ubuntu.com/download/server](https://ubuntu.com/download/server)
2. Download **Ubuntu Server 24.04 LTS** (~2.5GB)

### Step 2: Create VM

1. **File → New** in Parallels
2. **Install from image** → Select the ISO
3. Name: `dev-server`
4. **Customize before installation**:
   - CPU: 2 cores
   - Memory: 2048-4096 MB
   - Disk: 20 GB
   - Network: Shared

### Step 3: Install Ubuntu

1. Language, keyboard, network (DHCP)
2. **Use entire disk** (no LVM for simplicity)
3. Username: `fx`, strong password
4. **Install OpenSSH server** ✓
5. Skip snaps
6. Reboot

### Step 4: Get VM IP

```bash
# In VM console
ip addr show | grep "inet " | grep -v 127.0.0.1
# Note the 10.211.55.X address
```

### Step 5: Copy Key and Bootstrap

```bash
# From Mac terminal
ssh-keygen -t ed25519 -f ~/.ssh/id_devserver  # if not exists
ssh-copy-id -i ~/.ssh/id_devserver fx@10.211.55.X

# SSH in
ssh -i ~/.ssh/id_devserver fx@10.211.55.X

# Bootstrap
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | bash
```

### Step 6: Verify

```bash
ssh fx@10.211.55.X
dev
claude --version
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [Determinate Systems](https://determinate.systems/) for the Nix installer
- [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix) for Claude Code packaging
- [natsukium/mcp-servers-nix](https://github.com/natsukium/mcp-servers-nix) for MCP server Nix packaging
- [Anthropic](https://anthropic.com) for Claude Code
- [Hetzner Cloud](https://www.hetzner.com/cloud) for affordable, reliable VPS hosting
- [Blink Shell](https://blink.sh/) for the best iOS SSH/Mosh client
- [geoip-shell](https://github.com/friendly-bits/geoip-shell) for country-based firewall blocking
