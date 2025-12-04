# CLAUDE.md - Bootstrap Dev Server

This file provides guidance to Claude Code when working in this sub-project.

## Project Overview

**Bootstrap Dev Server** transforms a fresh Ubuntu 24.04 server into a fully hardened, Nix-powered development environment with Claude Code in a single command. The primary target is Hetzner Cloud VPS (~€3.50/month), but also supports local testing via Docker/Podman or Parallels VM.

**Purpose**: Provide a persistent cloud dev environment accessible from any device (Mac, iPad via Blink Shell, any SSH client) as a single source of truth for all development work.

**Parent Project**: This is a sub-project of `nix-install` - see `/home/fx/dev/nix-install/CLAUDE.md` for the broader context (macOS declarative configuration system).

## Architecture

### Key Components

| Component | Purpose |
|-----------|---------|
| `hcloud-provision.sh` | Hetzner Cloud VPS provisioning (create, delete, rescale servers) |
| `bootstrap-dev-server.sh` | Main bootstrap script (idempotent, ~44KB) |
| `flake.nix` | Nix dev shell definition with all tools |
| `lib/logging.sh` | Shared logging library with timestamps and log files |
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

**Development Environment:**
- Claude Code with MCP servers (Context7, GitHub, Sequential Thinking)
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
├── lib/
│   └── logging.sh            # Shared logging library
├── scripts/
│   └── secure-ssh-key.sh     # SSH key passphrase helper
├── tests/
│   └── verify-server.sh      # Post-install verification
└── config/
    └── claude/               # Claude Code configuration (synced to ~/.claude)
        ├── CLAUDE.md         # Multi-agent workflow system
        ├── agents/           # Specialized agent definitions
        └── commands/         # Slash command definitions
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
| `LOG_LEVEL` | INFO | Minimum log level |
| `LOG_FILE` | (auto) | Path to log file |

### Hetzner Provisioning

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | dev-server | Server name |
| `SERVER_TYPE` | cx23 | Server type (cx23, cx33, cx43, cpx22) |
| `SERVER_LOCATION` | fsn1 | Datacenter (fsn1, nbg1, hel1, ash, hil, sin) |
| `SSH_KEY_PATH` | ~/.ssh/id_devserver | SSH private key path |
| `SSH_USER` | fx | Username to create on server |

## Security Considerations

- SSH key is dedicated (`~/.ssh/id_devserver`) - separate from GitHub/other services
- Password authentication is disabled after bootstrap
- Root login is disabled after bootstrap
- UFW blocks all except SSH (22) and Mosh (60000-60010)
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
