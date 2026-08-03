# AGENT.md - Bootstrap Dev Server

This repository was initially developed with Claude Code. Treat `CLAUDE.md` as the historical project guide and this file as the current agent-facing operating guide for Codex-compatible work.

## Project Summary

Bootstrap Dev Server turns a fresh Ubuntu 24.04 server into a hardened, Nix-powered development environment with Claude Code, MCP servers, shell tooling, monitoring, and optional Nyx profile support.

Primary targets:

- Hetzner Cloud VPS provisioned by `hcloud-provision.sh`
- Fresh Ubuntu 24.04 hosts bootstrapped by `bootstrap-dev-server.sh`
- Local validation through mocked Bats tests and optional container E2E tooling

## Key Files

| Path | Purpose |
| ---- | ------- |
| `bootstrap-dev-server.sh` | Main idempotent bootstrap script |
| `hcloud-provision.sh` | Hetzner Cloud provisioning wrapper |
| `flake.nix` | Nix development shell and toolchain definition |
| `lib/logging.sh` | Shared logging functions |
| `profiles/` | Optional install profiles, including Nyx |
| `scripts/` | Supporting operational scripts |
| `tests/*.bats` | Mocked Bats test suites |
| `tests/e2e/` | Container-based E2E runner |
| `.planning/codebase/` | Architecture, conventions, testing, and stack notes |

## Operating Rules

- Read the relevant code before editing. This repo is mostly Bash and Nix; small shell changes can have server-level impact.
- Make surgical changes that preserve current script structure, logging style, and idempotency.
- Do not run live provisioning or bootstrap flows unless FX explicitly asks for that exact action:
  - `./bootstrap-dev-server.sh`
  - `./hcloud-provision.sh`
  - `tests/e2e/e2e-runner.sh` when it creates containers or mutates host/container state
- Safe local verification is allowed and expected when relevant:
  - `shellcheck ...`
  - `shfmt -d -i 4 ...`
  - `bats tests/*.bats`
  - `nix flake check`
- Use `gh` for GitHub operations. Do not rely on a GitHub MCP server.
- Ask FX via Spokenly dictation if a decision would change live infrastructure, credentials, SSH access, firewalling, or server cost.

## Shell Conventions

- Use Bash with `set -euo pipefail`.
- Use 4-space indentation; format with `shfmt -i 4`.
- Prefer `${variable}` over `$variable`.
- Quote variable expansions.
- Keep functions focused and named in `snake_case`.
- Use configuration variables in `UPPER_CASE`.
- New shell scripts should start with `ABOUTME:` comments.
- Source shared behavior from `lib/` when practical instead of duplicating it.

## Logging Conventions

Use `lib/logging.sh` patterns consistently:

```bash
log_info "Starting work..."
log_ok "Completed work"
log_warn "Non-critical issue"
log_error "Critical failure"
log_step "Major step"
log_phase "Phase name"
log_debug "Debug detail"
```

Errors should be explicit and actionable. For critical failures, log the reason before exiting.

## Testing Conventions

Tests use Bats and shared helpers in `tests/test_helper.bash`.

When behavior can be captured cleanly, write or update the test first, then implement the change. Tests should mock system commands, network calls, privilege boundaries, SSH operations, and filesystem writes outside temporary directories.

Useful commands:

```bash
bats tests/
bats tests/bootstrap.bats
bats tests/hcloud-provision.bats
shellcheck bootstrap-dev-server.sh hcloud-provision.sh lib/logging.sh scripts/*.sh profiles/*.sh
shfmt -d -i 4 bootstrap-dev-server.sh hcloud-provision.sh lib/*.sh scripts/*.sh profiles/*.sh
nix flake check
```

## Security And Infrastructure Guardrails

This project manages SSH hardening, firewalling, Fail2Ban, auditd, Tailscale, Nix installation, GitHub CLI auth, and monitoring. Changes in these areas need extra care.

Before changing security or provisioning logic:

1. Identify whether the change affects existing servers, new servers, or both.
2. Add or update mocked Bats coverage for the behavior.
3. Keep rollback and lockout risks visible in the final response.
4. Do not weaken SSH, firewall, GeoIP, sudo, or key handling defaults without explicit direction from FX.

## Documentation

Keep `README.md` user-facing and operational. Keep this file and `CLAUDE.md` agent-facing. If instructions diverge, prefer this file for Codex behavior and preserve `CLAUDE.md` as Claude Code context unless FX asks to consolidate.
