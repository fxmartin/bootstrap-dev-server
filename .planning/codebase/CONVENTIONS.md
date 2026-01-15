# Coding Conventions

**Analysis Date:** 2026-01-15

## Naming Patterns

**Files:**
- `kebab-case.sh` for all shell scripts (`bootstrap-dev-server.sh`, `hcloud-provision.sh`)
- `kebab-case.bats` for BATS test files (`bootstrap.bats`, `edge-cases.bats`)
- `snake_case.bash` for bash helpers (`test_helper.bash`)
- `UPPERCASE.md` for important documentation (`README.md`, `CLAUDE.md`)

**Functions:**
- `snake_case` for all functions
- Prefix patterns:
  - `install_*` for installation functions (`install_base_packages`, `install_nix`)
  - `configure_*` for configuration functions (`configure_ufw`, `configure_fail2ban`)
  - `setup_*` for setup functions (`setup_github_auth`, `setup_nix_development_environment`)
  - `harden_*` for security hardening (`harden_ssh`, `harden_kernel`)
  - `log_*` for logging functions (`log_info`, `log_ok`, `log_warn`, `log_error`)
  - `check_*` for validation functions (`check_prerequisites`)

**Variables:**
- `UPPER_CASE` for configuration variables (`DEV_USER`, `SSH_PORT`, `MOSH_PORT_START`)
- `UPPER_CASE` for color codes (`RED`, `GREEN`, `YELLOW`, `BLUE`, `NC`)
- `snake_case` for local variables (`local script_name`, `local timestamp`)
- `${braces}` notation always (not `$variable`)

**Types:**
- Not applicable (shell scripts)

## Code Style

**Formatting:**
- Tool: `shfmt` with `-i 4` (4-space indentation)
- Line length: No hard limit (pragmatic wrapping)
- Quotes: Single for literals, double for variable expansions
- Semicolons: Not used at end of lines

**Linting:**
- Tool: `shellcheck` (inline directives)
- Common disables: SC2312, SC1091, SC2154, SC2317
- Run: `shellcheck bootstrap-dev-server.sh`

**Shebang & Setup:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

## Import Organization

**Shell Script Sourcing:**
1. Inline minimal functions (for curl|bash bootstrap)
2. Source `lib/logging.sh` after repository clone
3. Use full paths with `${SCRIPT_DIR}` or `${PROJECT_ROOT}`

**Example:**
```bash
# Source logging library if available
lib_path="${REPO_CLONE_DIR}/${BOOTSTRAP_SUBDIR}/lib/logging.sh"
if [[ -f "${lib_path}" ]]; then
    # shellcheck disable=SC1091
    source "${lib_path}"
fi
```

**Path Variables:**
- `SCRIPT_DIR` - Directory containing current script
- `PROJECT_ROOT` - Repository root directory
- `REPO_CLONE_DIR` - Clone location for bootstrap

## Error Handling

**Patterns:**
- `set -euo pipefail` at script start
- Explicit error checking with `if` statements
- Log error before exit: `log_error "message"; exit 1`
- Suppress expected errors: `&>/dev/null`
- Logical operators for flow: `&&`, `||`

**Error Types:**
- Exit on critical failures (no internet, no sudo)
- Log warning and continue for non-critical issues
- Use early return for idempotent checks

**Example:**
```bash
if ! ping -c 1 github.com &>/dev/null; then
    log_error "No internet connectivity"
    exit 1
fi
log_ok "Internet connectivity verified"
```

## Logging

**Framework:**
- Custom `lib/logging.sh` (279 lines)
- Levels: DEBUG, INFO, WARN, ERROR
- Exported functions for subshell access

**Patterns:**
- Start function: `log_info "Starting X..."`
- End function: `log_ok "X completed"`
- Errors: `log_error "Failed to X"`
- Warnings: `log_warn "X not configured (continuing)"`

**File Output:**
- Directory: `~/.local/log/bootstrap/`
- Format: `{script-name}-{timestamp}.log`
- Timestamps in log entries

## Comments

**When to Comment:**
- ABOUTME tags at file start (required)
- Section headers with box-style comments
- Shellcheck directive explanations
- Non-obvious logic ("why" not "what")

**ABOUTME Pattern:**
```bash
# ABOUTME: Shared logging library with timestamps and log files
# ABOUTME: Used by bootstrap-dev-server.sh, hcloud-provision.sh
```

**Section Headers:**
```bash
#===============================================================================
# Configuration
#===============================================================================
```

**Shellcheck Directives:**
```bash
# shellcheck disable=SC2312  # gh --version is safe
log_ok "GitHub CLI: $(gh --version | head -1)"
```

**TODO Comments:**
- Format: `# TODO: description`
- Not heavily used (prefer issues)

## Function Design

**Size:**
- Most functions 10-50 lines
- Extract helpers for complex logic
- Single responsibility per function

**Parameters:**
- Use `${1:-default}` for optional parameters
- Document parameters in ABOUTME if complex
- Prefer environment variables for configuration

**Return Values:**
- Exit 0 for success
- Exit 1 for failure
- Use `return` for early exit in functions

**Example:**
```bash
install_github_cli() {
    log_info "Installing GitHub CLI..."

    if command -v gh &>/dev/null; then
        log_ok "GitHub CLI already installed"
        return 0
    fi

    # Installation logic...
    log_ok "GitHub CLI installed"
}
```

## Module Design

**Exports:**
- `export -f` for logging functions (subshell access)
- Environment variables for configuration
- No complex module system (shell scripts)

**File Organization:**
- One main script per purpose
- Shared functions in `lib/`
- Tests in `tests/` with matching names

---

*Convention analysis: 2026-01-15*
*Update when patterns change*
