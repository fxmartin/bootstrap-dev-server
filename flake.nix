# ABOUTME: Nix flake for Bootstrap Dev Server Environment
# ABOUTME: Provides dev shells and the dev-env profile with Claude Code, herdr, Python, Node.js, and CLI tools
{
  description = "Bootstrap Dev Server Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Claude Code with auto-updates
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, claude-code-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Defined once: devShells.default and packages.dev-env both consume it,
        # so the interactive shell and the installed profile cannot drift.
        devPackages = [
          # Claude Code
          claude-code-nix.packages.${system}.claude-code

          # Agent multiplexer - keeps coding agents in persistent panes
          pkgs.herdr

          # Core CLI tools
          pkgs.git
          pkgs.curl
          pkgs.wget
          pkgs.jq
          pkgs.yq
          pkgs.ripgrep
          pkgs.mgrep     # Multi-line grep
          pkgs.fd
          pkgs.bat
          pkgs.eza
          pkgs.fzf
          pkgs.tree
          pkgs.htop
          pkgs.btop
          pkgs.gotop  # Terminal-based graphical activity monitor

          # Modern CLI replacements
          pkgs.sd        # Intuitive find & replace (sed alternative)
          pkgs.dust      # Visual disk usage (du alternative)
          pkgs.choose    # Human-friendly column select (cut/awk alternative)
          pkgs.xh        # Friendly HTTP client (curl alternative)

          # Editors
          pkgs.neovim

          # Shell enhancements
          pkgs.zsh
          pkgs.zsh-autosuggestions
          pkgs.zsh-syntax-highlighting
          pkgs.tmux
          pkgs.zoxide
          pkgs.starship
          pkgs.direnv

          # Version Control
          pkgs.git-lfs  # Git Large File Storage

          # Python
          pkgs.python3
          pkgs.python3Packages.pip
          pkgs.python3Packages.virtualenv
          pkgs.uv  # Fast Python package installer

          # Python Development Tools
          pkgs.ruff    # Fast Python linter and formatter
          pkgs.black   # Python code formatter
          pkgs.python3Packages.isort   # Import statement organizer
          pkgs.python3Packages.mypy    # Static type checker
          pkgs.python3Packages.pylint        # Comprehensive linter
          pkgs.python3Packages.flake8        # Style guide enforcement
          pkgs.python3Packages.flake8-bugbear # Additional flake8 bug checks

          # Python Testing & Debugging
          pkgs.python3Packages.pytest        # Testing framework
          pkgs.python3Packages.pytest-asyncio # Async test support for FastAPI
          pkgs.python3Packages.pytest-cov    # Test coverage reporting
          pkgs.python3Packages.httpx         # Async HTTP client for testing
          pkgs.python3Packages.ipython       # Enhanced REPL for debugging
          pkgs.python3Packages.rich          # Pretty terminal output
          pkgs.pre-commit                      # Git hooks for code quality

          # Node.js (pinned to v22 deliberately; the MCP constraint that forced it is gone)
          pkgs.nodejs_22

          # React/Frontend Development
          pkgs.bun                                    # Fast JS runtime/bundler
          pkgs.pnpm                                   # Efficient package manager
          pkgs.typescript                             # TypeScript compiler
          pkgs.typescript-language-server             # LSP for editors
          pkgs.eslint                                 # JS/TS linting
          pkgs.prettier                               # Code formatting

          # Nix Development
          pkgs.nil              # Nix LSP for editor integration
          pkgs.nixfmt           # Nix code formatter (RFC style)
          pkgs.nix-tree         # Visualize Nix store dependencies
          pkgs.nix-diff         # Compare Nix derivations

          # Shell Development
          pkgs.shfmt  # Shell script formatter
          pkgs.bats   # Bash Automated Testing System

          # General Development Tools
          pkgs.just       # Modern task runner (make alternative)
          pkgs.watchexec  # File watcher for auto-reload
          pkgs.tokei      # Code statistics by language
          pkgs.difftastic # Structural diff (syntax-aware)

          # Container tools
          pkgs.podman
          pkgs.podman-compose

          # Network tools
          pkgs.httpie
          pkgs.websocat

          # Email (msmtp for sending via SMTP relay)
          pkgs.msmtp

          # Development utilities
          pkgs.gh  # GitHub CLI
          pkgs.glab  # GitLab CLI (local-ci-cd GitLab, via GITLAB_HOST)
          pkgs.hcloud  # Hetzner Cloud CLI
          pkgs.lazygit
          pkgs.delta  # Git diff viewer

          # Linting & testing
          pkgs.shellcheck  # Shell script linter

          # Documentation tools
          pkgs.glow  # Terminal markdown renderer

          # Database tools
          pkgs.sqlite
          pkgs.postgresql  # PostgreSQL client (psql)
          pkgs.redis       # Redis CLI

          # Build essentials
          pkgs.gnumake
          pkgs.pkg-config
          pkgs.cmake

          # Data processing
          pkgs.miller   # CSV/JSON/tabular data swiss army knife
          pkgs.csvkit   # CSV manipulation suite

          # Security & secrets
          pkgs.gnupg    # GPG for commit signing
          pkgs.sops     # Encrypted secrets management
          pkgs.age      # Modern file encryption (used with SOPS)

          # Network security
          pkgs.nmap     # Network discovery and security auditing

          # Productivity
          pkgs.hyperfine  # CLI benchmarking
          pkgs.ncdu       # Disk usage analyzer
          pkgs.tldr       # Simplified man pages
          pkgs.entr       # Run commands when files change
        ];
      in
      {
        # The same toolset as devShells.default, installable as the user's
        # default Nix profile (`nix profile install .#dev-env`) so it is on PATH
        # in every context, not only inside `dev`.
        # Only /bin and /share are linked: Python/Node library trees from
        # unrelated packages would collide in a merged profile for no benefit.
        packages.dev-env = pkgs.buildEnv {
          name = "dev-env";
          paths = devPackages;
          pathsToLink = [ "/bin" "/share" ];
        };

        # Default dev shell
        devShells.default = pkgs.mkShell {
          name = "dev-server";

          buildInputs = devPackages;

          shellHook = ''
            # Handle Ghostty terminal - fallback if terminfo missing
            if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null 2>&1; then
              export TERM=xterm-256color
            fi

            export EDITOR=nvim
            export VISUAL=nvim

            # Launch zsh only for interactive shells, not when running commands
            # Check: terminal attached, no command string, not already launched
            if [[ -t 0 && -t 1 && -z "''${BASH_EXECUTION_STRING:-}" && -z "''${__NIX_DEV_ZSH_LAUNCHED:-}" ]]; then
              echo ""
              echo "🚀 Dev Server Environment Loaded"
              echo "   Claude: $(claude --version 2>/dev/null || echo 'run: claude')"
              echo "   Python: $(python3 --version)"
              echo "   Node:   $(node --version)"
              echo ""
              export __NIX_DEV_ZSH_LAUNCHED=1
              exec zsh
            fi
          '';
        };

        # Minimal shell (just Claude + basics)
        devShells.minimal = pkgs.mkShell {
          name = "minimal";
          buildInputs = [
            claude-code-nix.packages.${system}.claude-code
            pkgs.git
            pkgs.curl
            pkgs.jq
            pkgs.ripgrep
            pkgs.neovim
            pkgs.gotop
            pkgs.shellcheck
          ];

          shellHook = ''
            # Handle Ghostty terminal - fallback if terminfo missing
            if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null 2>&1; then
              export TERM=xterm-256color
            fi
          '';
        };

        # Python-focused shell
        devShells.python = pkgs.mkShell {
          name = "python-dev";
          buildInputs = [
            claude-code-nix.packages.${system}.claude-code
            pkgs.python3
            pkgs.python3Packages.pip
            pkgs.python3Packages.virtualenv
            pkgs.uv
            # Python Development Tools
            pkgs.ruff
            pkgs.black
            pkgs.python3Packages.isort
            pkgs.python3Packages.mypy
            pkgs.python3Packages.pylint
            # Core tools
            pkgs.git
            pkgs.git-lfs
            pkgs.neovim
            pkgs.gotop
            pkgs.shellcheck
          ];

          shellHook = ''
            # Handle Ghostty terminal - fallback if terminfo missing
            if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null 2>&1; then
              export TERM=xterm-256color
            fi
          '';
        };
      });
}
