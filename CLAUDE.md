# CLAUDE.md - Bootstrap Dev Server

This file provides guidance to Claude Code when working in this sub-project.

## Project Overview

**Bootstrap Dev Server** transforms a fresh Ubuntu 24.04 server into a fully hardened, Nix-powered development environment with Claude Code in a single command. The primary target is Hetzner Cloud VPS (~€3.50/month), but also supports local testing via Docker/Podman or Parallels VM.

**Purpose**: Provide a persistent cloud dev environment accessible from any device (Mac, iPad via Blink Shell, any SSH client) as a single source of truth for all development work.

**Related Project**: Originally extracted from `nix-install` (macOS declarative configuration system). Now a standalone project.

## Architecture

### Key Components

| Component | Purpose |
|-----------|---------|
| `hcloud-provision.sh` | Hetzner Cloud VPS provisioning (create, delete, rescale servers) |
| `bootstrap-dev-server.sh` | Main bootstrap script (idempotent, ~44KB) |
| `flake.nix` | Nix dev shell definition with all tools |
| `lib/logging.sh` | Shared logging library with timestamps and log files |
| `scripts/install-node-exporter.sh` | node_exporter installer: pinned release, sha256-verified, dedicated user, UFW on tailscale0 |
| `config/node-exporter-start.sh` | Unit wrapper: binds node_exporter to the Tailscale IP only, bounded wait for the tailnet |
| `lib/tailscale.sh` | Node-key-expiry predicate gating the SSH lockdown |
| `tests/verify-server.sh` | Post-install verification script |
| `scripts/secure-ssh-key.sh` | Add passphrase to SSH key helper |

### What Gets Installed

**Security Hardening:**
- SSH hardened (key-only auth, no root login, strong ciphers)
- UFW firewall (SSH + Mosh only)
- Fail2Ban (24-hour bans after 3 failed attempts)
- auditd (system auditing)
- Kernel hardening (sysctl)
- Daily security report via email

**Monitoring:**
- Prometheus node_exporter on the Tailscale IP only (port 9100), scraped by Prometheus on the TerraMaster NAS over the tailnet (nix-install Epic-15 "Fleet Cockpit")

**Development Environment:**
- Claude Code + herdr (agent multiplexer) + `gh` CLI for GitHub
- Python 3.12 + uv + ruff + pytest stack
- Node.js 22 + bun + pnpm + TypeScript
- Nix development tools (nil, nixfmt-rfc-style)
- Shell tools (shellcheck, shfmt, bats)
- Containers (Podman, podman-compose)
- CLI productivity (ripgrep, fd, fzf, bat, eza, lazygit, etc.)
- Editors (Neovim, Helix)
- Terminal multiplexer (tmux, auto-launches on SSH)

## Development Workflow

### Testing Protocol

**CRITICAL: Claude does NOT perform testing**

- Claude's role: Write code, configuration, and documentation ONLY
- FX's role: ALL testing, execution, and validation

**Claude must NEVER:**
- Run `bootstrap-dev-server.sh` or `hcloud-provision.sh`
- Execute any installation or configuration scripts
- Modify system state in any way

**Claude CAN use (safe, read-only):**
- `shellcheck` - Shell script linting
- `bats` - For static test definition (not execution on live systems)

### Commands Reference

| Command | Description |
|---------|-------------|
| `shellcheck bootstrap-dev-server.sh` | Lint main bootstrap script |
| `shellcheck hcloud-provision.sh` | Lint provisioning script |
| `shfmt -d -i 4 *.sh` | Check shell formatting |
| `nix flake check` | Validate flake.nix |

### Adding New Files

When adding new shell scripts:
1. Add `ABOUTME:` comment at top of file
2. Add to appropriate directory (`lib/`, `scripts/`, `tests/`)
3. Ensure shellcheck compliance
4. Follow existing logging patterns (use `lib/logging.sh`)

## Key Files

```
bootstrap-dev-server/
├── CLAUDE.md                 # This file
├── README.md                 # User-facing documentation
├── proposal.md               # Dev shell enhancement proposals
├── bootstrap-dev-server.sh   # Main bootstrap script (idempotent)
├── hcloud-provision.sh       # Hetzner Cloud provisioner
├── flake.nix                 # Nix dev shell definition
├── flake.lock                # Locked package versions
├── .gitmodules               # Git submodule configuration
├── external/
│   └── nix-install/          # Submodule: nix-install repo (source of truth)
│       └── config/claude/    # Claude Code configs (agents, commands, CLAUDE.md)
├── lib/
│   └── logging.sh            # Shared logging library
├── scripts/
│   ├── secure-ssh-key.sh     # SSH key passphrase helper
│   └── install-node-exporter.sh  # node_exporter installer (tailnet-only)
├── tests/
│   └── verify-server.sh      # Post-install verification
├── config/
│   ├── claude/               # Claude Code configuration (synced to ~/.claude)
│   │   ├── CLAUDE.md         # Multi-agent workflow system
│   │   ├── agents/           # Specialized agent definitions
│   │   └── commands/         # Slash command definitions
│   ├── node-exporter.service   # node_exporter system unit
│   └── node-exporter-start.sh  # ExecStart wrapper: Tailscale-IP bind
```

## Code Standards

### Shell Scripts

- Use `set -euo pipefail` at script start
- Add `ABOUTME:` comment block at top
- Use `lib/logging.sh` for consistent logging
- shellcheck must pass with zero warnings
- Format with `shfmt -i 4` (4-space indent)
- Use `${variable}` syntax (not `$variable`)
- Quote all variable expansions

### Nix

- Follow nixfmt-rfc-style formatting
- Pin inputs with `follows` where appropriate
- Use `mkShell` for dev environments
- Keep `allowUnfree = true` for Claude Code

### Logging Standards

Use the logging library consistently:

```bash
log_info "Informational message"
log_ok "Success message"
log_warn "Warning message"
log_error "Error message"
log_step "Major step"
log_phase "Phase name"
log_debug "Debug message (only if LOG_LEVEL=DEBUG)"
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEV_USER` | Current user | Username for setup |
| `SSH_PORT` | 22 | SSH port |
| `MOSH_PORT_START` | 60000 | Mosh UDP range start |
| `MOSH_PORT_END` | 60010 | Mosh UDP range end |
| `TAILSCALE_TAGS` | tag:server | Tags advertised on `tailscale up` (tagged node keys never expire) |
| `SSH_TAILNET_ONLY` | false | Restrict SSH/Mosh to `tailscale0`, closing them publicly (refuses unless the node key never expires) |
| `LOG_LEVEL` | INFO | Minimum log level |
| `LOG_FILE` | (auto) | Path to log file |

### Hetzner Provisioning

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | dev-server | Server name |
| `SERVER_TYPE` | cx33 | Server type (cx33 recommended for multi-agent Claude Code) |
| `SERVER_LOCATION` | fsn1 | Datacenter (fsn1, nbg1, hel1, ash, hil, sin) |
| `SSH_KEY_PATH` | ~/.ssh/id_devserver | SSH private key path |
| `SSH_USER` | fx | Username to create on server |

## Source Control — GitLab is master, GitHub is a mirror

`origin` is the **local-ci-cd GitLab on `home-lab`**
(`http://home-lab:8080/root/bootstrap-dev-server.git`). Branches, merge requests
and issues live there. `github` is a named remote kept only so the push mirror
has somewhere to land.

- **Never push to `github`, and never merge on GitHub.** GitLab push-mirrors to
  it; anything committed on the GitHub side is divergent history that the next
  mirror run will fight with.
- Use `glab` for merge requests, issues and API calls. It is authenticated at
  the instance level (`glab auth status` → `home-lab:8080`, token in the OS
  keyring), so every repo on that instance reuses the same login. `--hostname`
  will not take a `host:port` — use `GITLAB_HOST=home-lab:8080`.
- `gh` remains correct for reading the GitHub mirror, and for any *other* repo
  that still has GitHub as its master. The `raw.githubusercontent.com` install
  URLs in the README keep working because the mirror keeps GitHub current.
- The `sdlc` controller's GitHub PR flow is **no longer authoritative** here.
  `.sdlc-forge.yaml` points it at GitLab; issue numbers are GitLab iids.
- Mirror lag is up to five minutes, and GitLab enforces a backoff between runs —
  a manual sync request does not bypass it. A stale `github/main` is expected,
  not a fault.

## Security Considerations

- SSH key is dedicated (`~/.ssh/id_devserver`) - separate from GitHub/other services
- Password authentication is disabled after bootstrap
- Root login is disabled after bootstrap
- UFW blocks all except SSH (22) and Mosh (60000-60010); 9100 (node_exporter) is open on `tailscale0` only
- node_exporter has no authentication: it binds to the Tailscale IP, never 0.0.0.0. Tailnet reachability + the tailscale0 UFW rule + the Tailscale ACL are the whole security model
- Daily security reports sent via msmtp

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Can't SSH after bootstrap | Key must be copied BEFORE running script |
| `nix` command not found | Source profile: `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` |
| Slow first `nix develop` | Normal - packages download on first run |
| New packages not available | Exit and re-enter dev shell: `exit` then `dev` |

### Log Locations

```bash
# Bootstrap logs
~/.local/log/bootstrap/bootstrap-dev-server-*.log

# Provisioning logs
~/.local/log/bootstrap/hcloud-provision-*.log

# System logs (on server)
/var/log/auth.log          # SSH/auth events
/var/log/fail2ban.log      # Ban events
/var/log/msmtp.log         # Email delivery
```

## Communication Style

- Address developer as **"FX"**
- Sharp, efficient, no-nonsense approach
- Ask for clarification rather than assuming
- Only write code and documentation - never execute scripts
