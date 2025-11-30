# CX11 Dev Server Bootstrap

A single-command bootstrap script that transforms a fresh Ubuntu 24.04 server into a fully hardened, Nix-powered development environment with Claude Code.

**One curl. Fully idempotent. Production-ready.**

```bash
curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | bash
```

---

## What This Does

This script automates the complete setup of a secure development server, designed to mirror a Hetzner CX11 VPS locally or provision cloud servers consistently.

### Security Hardening
- **SSH hardened** with key-only authentication, disabled root login, strong ciphers
- **UFW firewall** configured for SSH and Mosh only
- **Fail2Ban** installed with 24-hour bans after 3 failed attempts
- **Unattended upgrades** enabled for automatic security patches

### Development Environment
- **Nix** with flakes enabled (via Determinate Systems installer)
- **Claude Code** (Anthropic's AI coding assistant) with auto-updates
- **MCP Servers**: Context7, GitHub, Sequential Thinking (pre-configured)
- **GitHub CLI** with OAuth authentication
- **Python 3.12** with uv, pip, virtualenv, ruff
- **Node.js 22** LTS
- **Podman** for rootless containers
- **Modern CLI tools**: ripgrep, fd, bat, eza, fzf, lazygit, delta, httpie, gotop
- **Shell enhancements**: starship prompt, zoxide, direnv, tmux

### Idempotent Design
Safe to run multiple times. The script detects existing configurations and skips or updates appropriately.

---

## Quick Start

### For Existing Ubuntu Servers

```bash
# Basic install (uses defaults)
curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | bash

# Custom SSH port
curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | SSH_PORT=2222 bash

# Regenerate SSH host keys (fresh install)
curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | REGEN_HOST_KEYS=true bash
```

### After Installation

```bash
# Reconnect or reload shell
source ~/.bashrc

# Enter the dev environment
dev

# Start Claude Code
claude
```

---

## Setting Up a Local VM with Parallels Desktop

This section walks you through creating an Ubuntu 24.04 VM on macOS using Parallels Desktop—perfect for prototyping your Hetzner CX11 setup locally.

### Prerequisites

- macOS 11+ (Big Sur or later)
- Parallels Desktop 18+ (Pro or Standard edition)
- At least 20GB free disk space
- Internet connection

### Step 1: Download Ubuntu 24.04 Server ISO

1. Go to [ubuntu.com/download/server](https://ubuntu.com/download/server)
2. Download **Ubuntu Server 24.04 LTS** (not Desktop—we want lean)
3. Save the ISO to your Downloads folder (~2.5GB)

> **Why Server instead of Desktop?** Server edition has no GUI overhead, matches production environments, and boots faster. You'll SSH into it anyway.

### Step 2: Create the Virtual Machine

1. **Open Parallels Desktop**

2. **Create New VM**
   - Click **File → New** (or the `+` button)
   - Select **Install Windows or another OS from DVD or image file**
   - Click **Continue**

3. **Select the ISO**
   - Click **Choose Manually**
   - Navigate to your downloaded `ubuntu-24.04-live-server-amd64.iso`
   - Click **Continue**

4. **Name and Location**
   - Name: `cx11-dev` (or whatever you prefer)
   - Check **Customize settings before installation**
   - Click **Create**

### Step 3: Configure VM Resources (Match CX11 Specs)

The Hetzner CX11 has: 1 vCPU, 2GB RAM, 20GB SSD. For local dev, we'll be slightly more generous:

1. **Hardware Tab**
   
   | Setting | Value | Notes |
   |---------|-------|-------|
   | **CPU & Memory → Processors** | 2 | Matches CX11 shared vCPU performance |
   | **CPU & Memory → Memory** | 2048 MB | Exact CX11 spec (increase to 4GB if you have RAM) |
   | **Hard Disk → Size** | 20 GB | CX11 default |

2. **Options Tab**
   
   | Setting | Value |
   |---------|-------|
   | **Startup and Shutdown → Start view** | Headless (optional, for server feel) |
   | **Sharing → Share Mac folders** | Disabled (cleaner isolation) |

3. **Network Tab**
   
   | Setting | Value | Notes |
   |---------|-------|-------|
   | **Source** | Shared Network | Allows SSH from Mac |
   | **Type** | Virtio | Best performance |

4. Click **Continue** to start the installation

### Step 4: Install Ubuntu Server

The Ubuntu installer will boot. Follow these steps:

1. **Language**: English (or your preference)

2. **Keyboard**: Detect or select manually

3. **Installation Type**: **Ubuntu Server** (not minimized)

4. **Network**: Should auto-configure via DHCP. Note the IP if shown.

5. **Proxy**: Leave blank (unless you need one)

6. **Mirror**: Keep default archive.ubuntu.com

7. **Storage**: 
   - Select **Use an entire disk**
   - Uncheck **Set up this disk as an LVM group** (simpler)
   - Confirm the disk layout

8. **Profile Setup**:
   ```
   Your name: Your Name
   Server name: cx11-dev
   Username: fx (or your preferred username)
   Password: [choose a strong password]
   ```

9. **Ubuntu Pro**: Skip (select **Skip for now**)

10. **SSH Setup**: 
    - ✅ **Install OpenSSH server**
    - Skip importing SSH keys (we'll add them after)

11. **Featured Snaps**: Don't select any (we're using Nix)

12. **Wait for installation** to complete (~5-10 minutes)

13. **Reboot** when prompted

### Step 5: First Boot & Get IP Address

After reboot:

1. Log in with your username and password

2. Get the VM's IP address:
   ```bash
   ip addr show | grep "inet " | grep -v 127.0.0.1
   ```
   You'll see something like `inet 10.211.55.X/24`. Note this IP.

3. **Optional**: Set a static IP in Parallels for consistency
   - Parallels → Preferences → Network → Change Settings
   - Add a DHCP reservation for your VM's MAC address

### Step 6: Copy Your SSH Key

From your **Mac terminal** (not the VM):

```bash
# Generate a key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy your public key to the VM
ssh-copy-id fx@10.211.55.X  # Use your VM's IP

# Test the connection
ssh fx@10.211.55.X
```

### Step 7: Run the Bootstrap Script

Now SSH into your VM and run the bootstrap:

```bash
# SSH into the VM
ssh fx@10.211.55.X

# Run the bootstrap script
curl -fsSL https://raw.githubusercontent.com/fxmartin/nix-install/main/bootstrap-dev-server/bootstrap-dev-server.sh | bash
```

The script will:
1. Update the system and install base packages
2. Install GitHub CLI and authenticate via OAuth
3. Configure Git identity (prompts for name/email if not set)
4. Sparse clone the bootstrap-dev-server folder from GitHub
5. Harden SSH (disable password auth after your key is added)
6. Configure firewall and Fail2Ban
7. Install Nix with flakes
8. Create the dev environment with MCP servers
9. Pre-build all packages (takes 5-10 min first time)

### Step 8: Reconnect and Verify

```bash
# Exit and reconnect
exit
ssh fx@10.211.55.X

# Or use Mosh for persistent sessions
mosh fx@10.211.55.X

# Enter the dev environment
dev

# Verify Claude Code
claude --version

# Start a Claude session
claude
```

---

## Post-Installation Usage

### Available Commands

| Command | Description |
|---------|-------------|
| `dev` | Enter full dev environment (Claude + Python + Node + all tools) |
| `dev minimal` | Minimal environment (just Claude + basics) |
| `dev python` | Python-focused environment with ruff, uv |
| `dev-update` | Update all Nix packages to latest |
| `claude` | Start Claude Code (must be in a dev shell) |

### Environment Details

The default `dev` shell includes:

**AI & Coding**
- Claude Code (auto-updated via sadjow/claude-code-nix)
- MCP Servers: Context7, GitHub, Sequential Thinking

**Languages**
- Python 3.12 + pip + virtualenv + uv + ruff
- Node.js 22 LTS

**CLI Tools**
- `ripgrep` (rg) - Fast grep
- `fd` - Fast find
- `bat` - Cat with syntax highlighting
- `eza` - Modern ls
- `fzf` - Fuzzy finder
- `jq` / `yq` - JSON/YAML processors
- `httpie` - HTTP client
- `websocat` - WebSocket client

**System Monitoring**
- `htop` - Interactive process viewer
- `btop` - Resource monitor
- `gotop` - Terminal-based graphical activity monitor

**Git & Dev**
- `lazygit` - Terminal UI for git
- `delta` - Beautiful git diffs
- `gh` - GitHub CLI
- `neovim` / `helix` - Modern editors

**Containers**
- `podman` - Rootless containers
- `podman-compose` - Docker Compose compatible

**Shell**
- `tmux` - Terminal multiplexer
- `starship` - Cross-shell prompt
- `zoxide` - Smart cd
- `direnv` - Per-directory environments

### Updating Packages

```bash
# Update all Nix packages
dev-update

# Or manually
cd ~/.config/nix-dev-env
nix flake update
```

### MCP Server Configuration

Claude Code MCP servers are automatically configured on first `dev` shell entry:

- **Context7**: Documentation lookup (no authentication required)
- **GitHub**: Repository access (requires Personal Access Token)
- **Sequential Thinking**: Enhanced reasoning (no authentication required)

**To configure GitHub MCP server:**

1. Create a GitHub Personal Access Token:
   - Visit: https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Scopes: `repo`, `read:org`, `read:user`

2. Add token to config:
   ```bash
   # Edit the MCP config
   nano ~/.config/claude/config.json

   # Find the "github" section and add to "env":
   "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
   ```

3. Verify MCP servers:
   ```bash
   dev
   claude mcp list
   ```

### Adding Project-Specific Tools

Create a `flake.nix` in your project directory:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";  # or aarch64-linux for ARM
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Add project-specific packages here
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
git add flake.nix
nix develop
```

---

## Configuration Options

Set these environment variables before running the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEV_USER` | Current user | Username for setup |
| `SSH_PORT` | 22 | SSH port number |
| `MOSH_PORT_START` | 60000 | Mosh UDP port range start |
| `MOSH_PORT_END` | 60010 | Mosh UDP port range end |
| `REGEN_HOST_KEYS` | false | Regenerate SSH host keys |
| `FORCE_SSH_UPDATE` | false | Overwrite existing SSH config |

Example:
```bash
curl -fsSL https://example.com/bootstrap.sh | \
    SSH_PORT=2222 REGEN_HOST_KEYS=true bash
```

---

## Security Notes

### SSH Configuration

After running the script, SSH is configured with:

- **Key-only authentication** (passwords disabled)
- **Root login disabled**
- **Strong ciphers only**: chacha20-poly1305, aes256-gcm, aes256-ctr
- **Strong key exchange**: curve25519-sha256, diffie-hellman-group18-sha512
- **Max 3 auth attempts** before disconnect
- **30-second login grace period**

### Firewall Rules

UFW is configured to:
- **Deny all incoming** by default
- **Allow outgoing** by default
- **Allow SSH** (port 22 or custom)
- **Allow Mosh** (UDP 60000-60010)

### Fail2Ban

- Monitors `/var/log/auth.log`
- **3 failed attempts** triggers ban
- **24-hour ban** duration
- Localhost excluded from bans

---

## Troubleshooting

### Can't SSH after running script

The script disables password authentication. Ensure you've copied your SSH key **before** running:

```bash
ssh-copy-id user@server-ip
```

If locked out, use Parallels console (VM window) or Hetzner rescue mode.

### Nix command not found after install

Source the Nix profile:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Or reconnect your SSH session.

### Claude Code authentication

First run requires OAuth:
```bash
dev        # Enter dev environment
claude     # Opens browser for auth
```

If headless, Claude will provide a URL to open on another device.

### Slow first `nix develop`

First run downloads and builds all packages. Subsequent runs are instant due to Nix's caching. To pre-warm:

```bash
cd ~/.config/nix-dev-env
nix build .#devShells.x86_64-linux.default --no-link
```

### Mosh connection refused

Ensure UFW allows Mosh ports:
```bash
sudo ufw status
sudo ufw allow 60000:60010/udp
```

---

## File Structure

After installation:

```
~
├── .config/
│   ├── claude/
│   │   └── config.json    # MCP server configuration
│   └── nix-dev-env/
│       ├── flake.nix      # Main dev environment definition
│       └── flake.lock     # Locked package versions
├── .local/
│   └── share/
│       └── nix-install/   # Sparse clone of repository
│           └── bootstrap-dev-server/
│               ├── bootstrap-dev-server.sh
│               ├── flake.nix
│               └── README.md
├── .bashrc                # Shell integration added
├── CLAUDE.md              # Claude Code instructions template
└── projects/              # Suggested project directory
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test on a fresh Ubuntu 24.04 VM
4. Submit a pull request

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [Determinate Systems](https://determinate.systems/) for the Nix installer
- [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix) for Claude Code packaging
- [nix-community/mcp-servers-nix](https://github.com/nix-community/mcp-servers-nix) for MCP server packaging
- [Anthropic](https://anthropic.com) for Claude Code
- [GitHub CLI](https://cli.github.com/) for seamless GitHub integration
