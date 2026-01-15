# Codebase Structure

**Analysis Date:** 2026-01-15

## Directory Layout

```
bootstrap-dev-server/
├── bootstrap-dev-server.sh   # Main bootstrap script (1808 lines)
├── hcloud-provision.sh       # Hetzner provisioning (993 lines)
├── flake.nix                 # Nix dev shell definition (~600 lines)
├── flake.lock                # Pinned dependency versions
├── README.md                 # User documentation (30KB)
├── CLAUDE.md                 # Developer guidelines (7KB)
├── proposal.md               # Proposed package additions
├── lib/                      # Shared libraries
│   └── logging.sh            # Unified logging layer (279 lines)
├── scripts/                  # Utility scripts
│   ├── health-check.sh       # System verification (402 lines)
│   └── secure-ssh-key.sh     # SSH key protection (106 lines)
├── tests/                    # BATS test suite
│   ├── test_helper.bash      # Test fixtures & helpers (296 lines)
│   ├── bootstrap.bats        # Bootstrap script tests
│   ├── hcloud-provision.bats # Provisioning tests
│   ├── logging.bats          # Logging library tests
│   ├── health-check.bats     # Health check tests
│   ├── edge-cases.bats       # Edge case scenarios
│   ├── flake.bats            # Flake validation tests
│   ├── secure-ssh-key.bats   # SSH key helper tests
│   ├── verify-server.sh      # Post-install verification
│   └── README.md             # Testing documentation
├── external/                 # Git submodules
│   └── nix-install/          # Parent project (macOS Nix config)
├── config/                   # Configuration templates
│   └── claude/               # Claude Code config (synced to ~/.claude)
└── .planning/                # GSD project management
    └── codebase/             # Codebase analysis (this directory)
```

## Directory Purposes

**lib/**
- Purpose: Shared libraries sourced by multiple scripts
- Contains: `logging.sh` (279 lines)
- Key files: `logging.sh` - timestamps, log levels, file output, timers
- Subdirectories: None

**scripts/**
- Purpose: Standalone utility scripts
- Contains: `health-check.sh`, `secure-ssh-key.sh`
- Key files: `health-check.sh` - post-bootstrap system verification
- Subdirectories: None

**tests/**
- Purpose: BATS test suite with 281 tests
- Contains: `*.bats` files, `test_helper.bash`, `verify-server.sh`
- Key files: `test_helper.bash` - shared fixtures and assertions
- Subdirectories: None (flat structure)

**external/**
- Purpose: Git submodules for shared configuration
- Contains: `nix-install/` - parent project for macOS Nix config
- Key files: Claude Code config symlinked from here
- Subdirectories: `nix-install/config/claude/`

**config/**
- Purpose: Configuration templates synced to user directories
- Contains: Claude Code configuration
- Key files: `claude/` directory with agents, commands, CLAUDE.md
- Subdirectories: `claude/agents/`, `claude/commands/`

**.planning/**
- Purpose: GSD project management artifacts
- Contains: Codebase analysis documents
- Key files: This codebase map
- Subdirectories: `codebase/`

## Key File Locations

**Entry Points:**
- `bootstrap-dev-server.sh` - Main bootstrap orchestrator
- `hcloud-provision.sh` - Hetzner Cloud provisioning
- `scripts/health-check.sh` - System verification utility
- `scripts/secure-ssh-key.sh` - SSH key passphrase helper

**Configuration:**
- `flake.nix` - Nix dev shell definition with all tools
- `flake.lock` - Pinned package versions
- `CLAUDE.md` - Developer guidelines for Claude Code

**Core Logic:**
- `lib/logging.sh` - Unified logging with timestamps and file output
- `bootstrap-dev-server.sh` - 30+ functions for server setup
- `hcloud-provision.sh` - 20+ functions for Hetzner API

**Testing:**
- `tests/*.bats` - BATS test files (7 files, 281 tests)
- `tests/test_helper.bash` - Shared test utilities
- `tests/verify-server.sh` - Post-install verification script

**Documentation:**
- `README.md` - User-facing documentation
- `CLAUDE.md` - Developer guidelines
- `tests/README.md` - Testing documentation

## Naming Conventions

**Files:**
- `kebab-case.sh` for shell scripts (`bootstrap-dev-server.sh`, `health-check.sh`)
- `kebab-case.bats` for BATS test files (`bootstrap.bats`, `edge-cases.bats`)
- `snake_case.bash` for bash helpers (`test_helper.bash`)
- `UPPERCASE.md` for important docs (`README.md`, `CLAUDE.md`)

**Directories:**
- `lowercase` for all directories (`lib/`, `scripts/`, `tests/`)
- Plural for collections (`tests/`, `scripts/`)

**Special Patterns:**
- `*-PLAN.md`, `*-SUMMARY.md` for GSD artifacts
- `.bats` extension for BATS test files
- `verify-*.sh` for verification scripts

## Where to Add New Code

**New Bootstrap Function:**
- Primary code: Add to `bootstrap-dev-server.sh`
- Tests: Add to `tests/bootstrap.bats`
- Follow existing function pattern with logging

**New Utility Script:**
- Implementation: `scripts/{script-name}.sh`
- Tests: `tests/{script-name}.bats`
- Add ABOUTME comments and source `lib/logging.sh`

**New Library Function:**
- Implementation: `lib/logging.sh` (or new `lib/{name}.sh`)
- Tests: `tests/logging.bats` (or new test file)
- Export functions for subshell access

**New Test Suite:**
- Implementation: `tests/{feature}.bats`
- Helper functions: `tests/test_helper.bash`
- Follow BATS conventions with setup/teardown

**New Nix Package:**
- Configuration: `flake.nix` in `buildInputs`
- Documentation: Update `proposal.md` if proposed

## Special Directories

**external/nix-install/**
- Purpose: Git submodule with parent project
- Source: GitHub fxmartin/nix-install
- Committed: Yes (submodule reference only)
- Contains: macOS Nix configuration, Claude Code config

**.planning/**
- Purpose: GSD project management
- Source: Generated by `/gsd:map-codebase`
- Committed: Yes
- Contains: Codebase analysis documents

**~/.local/log/bootstrap/** (runtime)
- Purpose: Log file storage
- Source: Created by `lib/logging.sh`
- Committed: No (user-local)
- Contains: Timestamped log files

---

*Structure analysis: 2026-01-15*
*Update when directory structure changes*
