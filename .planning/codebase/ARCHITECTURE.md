# Architecture

**Analysis Date:** 2026-01-15

## Pattern Overview

**Overall:** Imperative Automation Pipeline - Shell script-based infrastructure provisioning system

**Key Characteristics:**
- Single-purpose orchestration (fresh Ubuntu → production dev server)
- Modular shell functions with single responsibility
- Idempotent operations (safe to re-run)
- Phase-based execution with logging

## Layers

**Phase 1: Preflight & Foundation**
- Purpose: System validation, internet checks, package manager setup
- Contains: Preflight checks, base package installation, unattended upgrades
- Entry: `preflight_checks()`, `install_base_packages()` in `bootstrap-dev-server.sh`
- Depends on: Internet connectivity, sudo access
- Used by: All subsequent phases

**Phase 2: Git & GitHub Setup**
- Purpose: Git identity and GitHub authentication
- Contains: Git config, GitHub CLI installation, OAuth authentication
- Entry: `install_github_cli()`, `configure_git_identity()`, `setup_github_auth()` in `bootstrap-dev-server.sh`
- Depends on: Phase 1 completion
- Used by: Repository cloning, Claude Code GitHub MCP

**Phase 3: Security Hardening**
- Purpose: SSH, firewall, intrusion prevention
- Contains: SSH hardening, UFW setup, Fail2Ban, auditd, kernel hardening, GeoIP blocking
- Entry: `harden_ssh()`, `configure_ufw()`, `configure_fail2ban()` in `bootstrap-dev-server.sh`
- Depends on: Base packages installed
- Used by: Production server security

**Phase 4: Development Environment**
- Purpose: Nix, Claude Code, dev tools installation
- Contains: Nix installer, flake.nix generation, Claude Code setup
- Entry: `install_nix()`, `setup_nix_development_environment()` in `bootstrap-dev-server.sh`
- Depends on: Security hardening complete
- Used by: Developer workflow

**Phase 5: Finalization**
- Purpose: Deferred SSH restart, summary
- Contains: SSH service restart, completion summary
- Entry: `restart_ssh_final()`, `print_summary()` in `bootstrap-dev-server.sh`
- Depends on: All phases complete
- Used by: User notification

**Logging Layer**
- Purpose: Centralized, timestamped logging
- Contains: Log functions, timers, file output
- Location: `lib/logging.sh`
- Depends on: Nothing (standalone)
- Used by: All scripts

## Data Flow

**Bootstrap Execution Flow:**

1. User runs: `curl -fsSL <url> | bash`
2. Minimal inline logging initialized
3. Clone repository → upgrade to full logging library
4. Execute 5 phases in sequence (with timers)
5. Log file written to `~/.local/log/bootstrap/`
6. System ready for SSH + dev + claude

**Hetzner Provisioning Flow:**

1. User runs: `./hcloud-provision.sh`
2. Prerequisites check (hcloud CLI, API token, SSH key)
3. Hetzner authentication
4. SSH key upload to Hetzner
5. Server creation (Ubuntu 24.04)
6. Create user account + sudo access
7. Run bootstrap-dev-server.sh on remote
8. Update local SSH config

**State Management:**
- File-based: All state in config files and log files
- No persistent in-memory state
- Each execution is independent (idempotent)

## Key Abstractions

**Logging Functions:**
- Purpose: Consistent output and file logging
- Examples: `log_info()`, `log_ok()`, `log_warn()`, `log_error()`, `log_step()`, `log_phase()`
- Pattern: Exported functions for use in subshells
- Location: `lib/logging.sh`

**Idempotent Operations:**
- Purpose: Safe re-runs without side effects
- Pattern: Check-before-act with early return
- Example: `if command -v X; then log_ok "Already installed"; return 0; fi`

**Configuration Variables:**
- Purpose: Customizable defaults
- Pattern: `VAR="${VAR:-default}"` with UPPER_CASE names
- Examples: `DEV_USER`, `SSH_PORT`, `MOSH_PORT_START`

## Entry Points

**Primary Entry: `bootstrap-dev-server.sh`**
- Location: Root directory (1808 lines)
- Triggers: `curl | bash` or direct execution
- Entry function: `main()` at line 1735
- Responsibilities: Transform fresh Ubuntu → production dev server

**Primary Entry: `hcloud-provision.sh`**
- Location: Root directory (993 lines)
- Triggers: Direct execution with options
- Entry function: `main()` at line 936
- Responsibilities: Hetzner API + server creation + bootstrap

**Utility Entry: `scripts/health-check.sh`**
- Location: `scripts/` (402 lines)
- Triggers: `health-check` alias or direct execution
- Responsibilities: Post-install verification

**Utility Entry: `scripts/secure-ssh-key.sh`**
- Location: `scripts/` (106 lines)
- Triggers: Direct execution
- Responsibilities: Add passphrase to SSH key

## Error Handling

**Strategy:** `set -euo pipefail` + explicit checks

**Patterns:**
- Early exit on critical failures
- Log warning and continue for non-critical issues
- Deferred SSH restart to avoid disconnection mid-bootstrap

## Cross-Cutting Concerns

**Logging:**
- Approach: `lib/logging.sh` sourced at script start
- Console: Colored output with timestamps
- File: `~/.local/log/bootstrap/{script}-{timestamp}.log`

**Validation:**
- Approach: Preflight checks before main execution
- Checks: OS version, internet connectivity, sudo access

**Idempotency:**
- Approach: Every function checks if already done
- Pattern: `if [[ ! -f "${FILE}" ]] || [[ "${FORCE_UPDATE}" == "true" ]]`

---

*Architecture analysis: 2026-01-15*
*Update when major patterns change*
