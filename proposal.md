# Dev Shell Enhancement Proposal

## Overview

Proposed additions to the `devShells.default` in `flake.nix` to better support Python/FastAPI, React, Zsh scripting, and Nix development workflows.

## Current Packages (Already Included)

### Python
- `python312`, `pip`, `virtualenv`
- `uv` - Fast package installer
- `ruff`, `black`, `isort`, `mypy`, `pylint` - Linting/formatting

### Node.js
- `nodejs_22`

### Shell
- `zsh`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `shellcheck`, `starship`, `zoxide`, `direnv`, `tmux`

### Git/VCS
- `git`, `git-lfs`, `lazygit`, `delta`, `gh`

### Containers
- `podman`, `podman-compose`

### Core CLI
- `curl`, `wget`, `jq`, `yq`, `ripgrep`, `fd`, `bat`, `eza`, `fzf`, `tree`, `htop`, `btop`, `gotop`

### Editors
- `neovim`, `helix`

### Other
- `httpie`, `websocat`, `msmtp`, `glow`

---

## Proposed Additions

### Python/FastAPI Development

| Package | Nix Attribute | Purpose | Priority |
|---------|---------------|---------|----------|
| pytest | `pkgs.python312Packages.pytest` | Testing framework | High |
| pytest-asyncio | `pkgs.python312Packages.pytest-asyncio` | Async test support for FastAPI | High |
| pytest-cov | `pkgs.python312Packages.pytest-cov` | Test coverage reporting | High |
| httpx | `pkgs.python312Packages.httpx` | Async HTTP client for testing FastAPI | High |
| ipython | `pkgs.python312Packages.ipython` | Enhanced REPL for debugging | Medium |
| rich | `pkgs.python312Packages.rich` | Pretty terminal output/debugging | Medium |
| pre-commit | `pkgs.pre-commit` | Git hooks for code quality | High |

### React/Frontend Development

| Package | Nix Attribute | Purpose | Priority |
|---------|---------------|---------|----------|
| bun | `pkgs.bun` | Fast JS runtime/bundler | Medium |
| pnpm | `pkgs.pnpm` | Efficient package manager | Medium |
| typescript | `pkgs.nodePackages.typescript` | TypeScript compiler | High |
| typescript-language-server | `pkgs.nodePackages.typescript-language-server` | LSP for editor integration | High |
| eslint | `pkgs.nodePackages.eslint` | JS/TS linting | High |
| prettier | `pkgs.nodePackages.prettier` | Code formatting | High |

### Nix Development

| Package | Nix Attribute | Purpose | Priority |
|---------|---------------|---------|----------|
| nil | `pkgs.nil` | Nix LSP for editor integration | High |
| nixfmt-rfc-style | `pkgs.nixfmt-rfc-style` | Nix code formatter (RFC compliant) | High |
| nix-tree | `pkgs.nix-tree` | Visualize Nix store dependencies | Medium |
| nix-diff | `pkgs.nix-diff` | Compare Nix derivations | Low |

### Shell/Zsh Development

| Package | Nix Attribute | Purpose | Priority |
|---------|---------------|---------|----------|
| shfmt | `pkgs.shfmt` | Shell script formatter | High |
| bats | `pkgs.bats` | Bash Automated Testing System | Medium |

### General Development Quality of Life

| Package | Nix Attribute | Purpose | Priority |
|---------|---------------|---------|----------|
| just | `pkgs.just` | Modern task runner (make alternative) | High |
| watchexec | `pkgs.watchexec` | File watcher for auto-reload | Medium |
| tokei | `pkgs.tokei` | Code statistics by language | Low |
| difftastic | `pkgs.difftastic` | Structural diff (syntax-aware) | Medium |

---

## Summary by Priority

### High Priority (Recommended)
```nix
# Python/FastAPI
pkgs.python312Packages.pytest
pkgs.python312Packages.pytest-asyncio
pkgs.python312Packages.pytest-cov
pkgs.python312Packages.httpx
pkgs.pre-commit

# React/Frontend
pkgs.nodePackages.typescript
pkgs.nodePackages.typescript-language-server
pkgs.nodePackages.eslint
pkgs.nodePackages.prettier

# Nix
pkgs.nil
pkgs.nixfmt-rfc-style

# Shell
pkgs.shfmt

# General
pkgs.just
```

### Medium Priority (Nice to Have)
```nix
# Python
pkgs.python312Packages.ipython
pkgs.python312Packages.rich

# React/Frontend
pkgs.bun
pkgs.pnpm

# Nix
pkgs.nix-tree

# Shell
pkgs.bats

# General
pkgs.watchexec
pkgs.difftastic
```

### Low Priority (Optional)
```nix
pkgs.nix-diff
pkgs.tokei
```

---

## Estimated Impact

- **Disk space**: ~500MB additional (mostly Node.js tooling)
- **Shell startup**: Negligible impact
- **Build time**: +2-3 minutes on first `nix develop`

---

## Decision

- [ ] Add all High Priority packages
- [ ] Add all High + Medium Priority packages
- [ ] Add all packages
- [ ] Cherry-pick specific packages (list below):
  -

---

## Notes

- `bun` vs `pnpm`: Both are fast package managers. Bun also includes a runtime and bundler. Choose based on project needs.
- `nil` vs `nixd`: Both are Nix LSPs. `nil` is more mature; `nixd` has better nixpkgs integration.
- `pytest-asyncio` is essential for FastAPI testing with async endpoints.
- `pre-commit` integrates with `ruff`, `black`, `prettier`, etc. for automated code quality.
