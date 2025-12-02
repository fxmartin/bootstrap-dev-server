# Claude Code - Multi-Agent Development System

## Core Principles
- **Simple, clean, maintainable solutions** over complex/clever implementations
- **Smallest reasonable changes** - Ask permission before reimplementing from scratch
- **TDD always** - Write tests first, implement to pass, refactor
- **Production-ready code** with comprehensive error handling
- **Self-documenting code** - Clear naming, strategic comments explaining "why"
- **NEVER use --no-verify** when committing

## Development Workflow Requirements

### Issue & Story Management (MANDATORY)
1. **Always create GitHub issue** when investigating or fixing any problem
2. **New features require story documentation** - Add to appropriate epic based on complexity
3. **Requirements-first approach** - Always read `REQUIREMENTS.md` then relevant `stories/epic-XX` files before starting work
4. **Stories directory is single source of truth** for all epic, feature, and story definitions
5. **Update epic files directly** - All progress tracking and story status updates must be in epic files
6. **Link PRs to story IDs** from epic files (e.g., "Implements Story 01.2-001")

### Story Structure Protocol
- **STORIES.md**: Overview and navigation hub
- **stories/epic-XX-[name].md**: Detailed stories, progress, acceptance criteria
- **stories/non-functional-requirements.md**: NFR tracking
- **Story completion**: Update epic files within 24 hours of deployment

## Multi-Agent Development Workflow

### 1. Requirements Definition & Approval
```bash
# Generate requirements through structured discovery
claude brainstorm "<project-idea>"

# Cryptographically sign requirements for integrity
claude approve-requirements
```

### 2. Story Creation & Planning
```bash
# Generate epics, features, and user stories from requirements
claude create-stories
```

### 3. Iterative Development
```bash
# Launch specialized agents for incremental development
claude resume-build-agents next

# Available agents:
# - backend-typescript-architect: Bun + TypeScript backend
# - python-backend-engineer: FastAPI + uv + modern Python
# - ui-engineer: React/Vue/Angular frontend
# - podman-container-architect: OCI containerization
# - bash-zsh-macos-engineer: macOS automation
# - senior-code-reviewer: Architecture & security review
# - qa-engineer: Testing strategy & quality assurance
```

### 4. Issue Management
```bash
# Investigate and create comprehensive GitHub issues
claude create-issue "<defect-description>"
```

### 5. Quality Assurance
```bash
# Achieve 100% test coverage with comprehensive testing
claude coverage
```

### 6. Project Intelligence
```bash
# Generate project metrics and insights
claude create-project-summary-stats

# Update development time estimation
claude update-estimated-time-spent

# Create production-ready documentation
claude create-user-documentation
```

## Dev Environment Tools

The Nix dev shell provides the following tools. Use them appropriately for development tasks.

### Python/FastAPI Development
| Tool | Command | Purpose |
|------|---------|---------|
| Python 3.12 | `python3` | Python runtime |
| uv | `uv` | Fast package installer/resolver |
| ruff | `ruff check`, `ruff format` | Linting and formatting (replaces flake8/black) |
| black | `black` | Code formatter |
| isort | `isort` | Import sorting |
| mypy | `mypy` | Static type checking |
| pylint | `pylint` | Comprehensive linter |
| pytest | `pytest` | Testing framework |
| pytest-asyncio | `pytest` (with async) | Async test support for FastAPI |
| pytest-cov | `pytest --cov` | Test coverage reporting |
| httpx | (library) | Async HTTP client for testing APIs |
| ipython | `ipython` | Enhanced REPL for debugging |
| rich | (library) | Pretty terminal output |
| pre-commit | `pre-commit` | Git hooks for code quality |

### React/Frontend Development
| Tool | Command | Purpose |
|------|---------|---------|
| Node.js 22 | `node` | JavaScript runtime |
| bun | `bun` | Fast JS runtime/bundler/package manager |
| pnpm | `pnpm` | Efficient package manager |
| TypeScript | `tsc` | TypeScript compiler |
| typescript-language-server | (LSP) | Editor integration |
| ESLint | `eslint` | JS/TS linting |
| Prettier | `prettier` | Code formatting |

### Nix Development
| Tool | Command | Purpose |
|------|---------|---------|
| nil | (LSP) | Nix language server for editors |
| nixfmt | `nixfmt` | Nix code formatter (RFC-style) |
| nix-tree | `nix-tree` | Visualize Nix store dependencies |
| nix-diff | `nix-diff` | Compare Nix derivations |

### Shell Development
| Tool | Command | Purpose |
|------|---------|---------|
| shellcheck | `shellcheck` | Shell script linter |
| shfmt | `shfmt` | Shell script formatter |
| bats | `bats` | Bash Automated Testing System |

### General Development
| Tool | Command | Purpose |
|------|---------|---------|
| just | `just` | Task runner (modern make alternative) |
| watchexec | `watchexec` | File watcher for auto-reload |
| tokei | `tokei` | Code statistics by language |
| difftastic | `difft` | Syntax-aware structural diff |
| pre-commit | `pre-commit install` | Git hook management |

### CLI Productivity
| Tool | Command | Purpose |
|------|---------|---------|
| ripgrep | `rg` | Fast text search |
| fd | `fd` | Fast file finder |
| fzf | `fzf`, `Ctrl+R` | Fuzzy finder |
| bat | `bat` | Cat with syntax highlighting |
| eza | `ls`, `ll`, `lt` | Modern ls replacement |
| zoxide | `z` | Smart directory jumping |
| jq/yq | `jq`, `yq` | JSON/YAML processing |
| httpie | `http` | HTTP client |
| lazygit | `lg` | Terminal git UI |
| delta | (git pager) | Beautiful git diffs |
| glow | `glow` | Terminal markdown renderer |
| tmux | `tmux` | Terminal multiplexer (auto-launches on SSH) |

### Containers
| Tool | Command | Purpose |
|------|---------|---------|
| Podman | `podman` | Docker-compatible container runtime |
| podman-compose | `podman-compose` | Multi-container orchestration |

### Editors
| Tool | Command | Purpose |
|------|---------|---------|
| Neovim | `nvim`, `vim`, `vi` | Primary editor |
| Helix | `hx` | Modal editor alternative |

## Code Quality Standards

### Python (uv + FastAPI)
- Use `uv` for dependency management and project setup
- Comprehensive type hints throughout
- Self-documenting variable names and strategic docstrings
- Follow SOLID principles with clean architecture
- Run `ruff check --fix` before committing
- Run `pytest --cov` for test coverage

### TypeScript (Bun Runtime)
- Advanced TypeScript patterns for backend systems
- Proper error handling and input validation
- OWASP security guidelines
- Microservices-ready architecture
- Run `eslint` and `prettier` before committing

### Testing (NO EXCEPTIONS)
- **Unit tests**: Cover all business logic
- **Integration tests**: Validate component interactions
- **End-to-end tests**: Verify user workflows
- Authorization required: "I AUTHORIZE YOU TO SKIP WRITING TESTS THIS TIME"

### File Structure
```
project/
├── REQUIREMENTS.md          # Signed requirements (SHA-256)
├── STORIES.md              # Overview and navigation
├── PROJECT-STATS.md        # Condensed project health
├── docs/                   # User documentation
└── stories/
    ├── epic-01-[epic-name].md
    ├── epic-02-[epic-name].md
    ├── epic-03-[epic-name].md
    └── non-functional-requirements.md
```

## Integration Patterns
- **API-agnostic frontend**: Components work with any backend
- **Database optimization**: Eliminate N+1 problems, proper indexing
- **Container-first**: Podman + OCI compliance
- **Security-first**: Authentication, authorization, input validation
- **Performance monitoring**: Profiling, caching, async patterns

## Agent Specializations
- **backend-typescript-architect**: Bun runtime, advanced TypeScript, microservices
- **python-backend-engineer**: uv tooling, FastAPI, SQLAlchemy, async Python
- **ui-engineer**: Modern frontend, component architecture, responsive design
- **senior-code-reviewer**: Security audits, architecture validation, best practices
- **podman-container-architect**: OCI containers, multi-stage builds, rootless Podman
- **qa-engineer**: Comprehensive testing strategy, quality metrics, defect management

## Communication Style
- Address developer as **"FX"**
- Sharp, efficient, no-nonsense approach
- Business-minded with C-level context awareness
- Challenge when needed, push back on inefficiency
- Clear, structured responses with actionable insights
- ALWAYS ask for clarification rather than making assumptions.
- If you're having trouble with something, it's ok to stop and ask for help. Especially if it's something your human might be better at.

## Reference Materials
- **TDD Process**: Red → Green → Refactor cycle
- **Python**: `@~/.claude/docs/python.md`
- **Source Control**: `@~/.claude/docs/source-control.md`
- **Container Tools**: `@~/.claude/docs/docker-uv.md`

---
*Multi-agent orchestration for enterprise-grade development workflows*
