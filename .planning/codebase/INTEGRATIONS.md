# External Integrations

**Analysis Date:** 2026-01-15

## APIs & External Services

**Hetzner Cloud API:**
- Service: VPS provisioning and management via `hcloud-provision.sh`
- Client: hcloud CLI (installed via apt)
- Auth: HCLOUD_TOKEN environment variable (interactive prompt if not set)
- Server types: cx23, cx33, cx43, cx53 (Intel), cpx22-42 (AMD), cax11-31 (ARM)
- Datacenters: fsn1, nbg1, hel1 (EU), ash, hil (US), sin (Asia)

**GitHub Integration:**
- Service: Repository operations and authentication
- Client: gh CLI (`pkgs.gh` in `flake.nix`)
- Auth: Device flow OAuth or token-based (`bootstrap-dev-server.sh` lines 302-328)
- Setup URL: https://github.com/login/device

**GitHub via gh CLI:**
- Claude Code uses `gh` CLI for all GitHub operations (no MCP server)
- Auth: `gh auth login` (device flow OAuth)

## Data Storage

**Databases:**
- SQLite - CLI client only (`pkgs.sqlite`)
- PostgreSQL - CLI client (psql) only (`pkgs.postgresql`)
- Redis - CLI client only (`pkgs.redis`)
- Note: No actual database servers deployed - clients for external connections

**File Storage:**
- Local file system only
- Log directory: `~/.local/log/bootstrap/`
- Config directory: `~/.claude/`

**Caching:**
- Nix store - `/nix/store/` for all packages
- No Redis or other cache servers deployed

## Authentication & Identity

**SSH Key Management:**
- Dedicated key: `~/.ssh/id_devserver` (separate from GitHub/other services)
- Key type: Ed25519 for new keys
- Passphrase helper: `scripts/secure-ssh-key.sh`
- SSH hardening: `/etc/ssh/sshd_config.d/99-hardening.conf`

**GitHub OAuth:**
- Provider: GitHub device flow
- Handled by: gh CLI
- No local token storage - uses gh credential manager

## Monitoring & Observability

**Error Tracking:**
- None (local shell logging only)

**Logging:**
- Framework: Custom `lib/logging.sh` library
- Levels: DEBUG, INFO, WARN, ERROR
- Output: Console (colored) + file (`~/.local/log/bootstrap/*.log`)
- Format: `[TIMESTAMP] [LEVEL] message`

**System Monitoring:**
- Health check: `scripts/health-check.sh`
- Checks: SSH, UFW, Fail2Ban, Nix daemon, disk space, dev tools
- Alias: `health-check` in dev shell

## CI/CD & Deployment

**Hosting:**
- Platform: Hetzner Cloud VPS (Ubuntu 24.04)
- Deployment: `curl -fsSL <url> | bash` or `hcloud-provision.sh`
- Environment vars: Configured via script prompts

**CI Pipeline:**
- None (local testing with BATS only)
- Tests: `bats tests/`

## Environment Configuration

**Development:**
- Required: None (uses Nix for all dependencies)
- Optional env vars: DEV_USER, SSH_PORT, LOG_LEVEL
- Mock services: None (all tests use mocks)

**Production:**
- Required: Hetzner API token (for provisioning)
- Required: GitHub auth via `gh auth login`
- Required: Gandi email credentials (for security reports)
- Secrets location: Interactive prompts, `~/.msmtprc`

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- Email: Security reports via msmtp to Gandi SMTP (`mail.gandi.net:587`)
- Schedule: Daily via systemd timer

## Third-Party Tools & MCP Servers

**Claude Code Integrations:**
- Claude Code - Main AI assistant (`claude-code-nix`)
- Context7 MCP - Code context retrieval (`mcp-servers-nix.context7-mcp`)
- GitHub via `gh` CLI (`pkgs.gh`) — no MCP server
- Sequential Thinking - DISABLED (upstream build broken, issue #285)
- GSD - Meta-prompting system (`npx get-shit-done-cc`)

**Security Services:**
- Fail2Ban - SSH intrusion prevention (`/etc/fail2ban/jail.local`)
- UFW Firewall - Port filtering (SSH + Mosh only)
- GeoIP blocking - Country-based firewall via geoip-shell
- auditd - System auditing

**Network Services:**
- Mosh - Mobile shell for persistent SSH (`pkgs.mosh`)
- Tailscale - Optional mesh VPN (commented in script)

---

*Integration audit: 2026-01-15*
*Update when adding/removing external services*
