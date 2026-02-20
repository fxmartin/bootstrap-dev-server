# ABOUTME: Nix flake for Bootstrap Dev Server Environment
# ABOUTME: Provides development shells with Claude Code, MCP servers, Python, Node.js, and CLI tools
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

    # MCP servers for Claude Code (Context7, GitHub, Sequential Thinking)
    # NOTE: nixpkgs.follows means mcp-servers-nix uses our nixpkgs version.
    # If nixpkgs upgrades Node.js beyond v22, MCP server builds may fail because
    # upstream requires Node.js 22 (see natsukium/mcp-servers-nix#285, fix: #276).
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, claude-code-nix, mcp-servers-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # MCP servers:
        # - context7: from mcp-servers-nix (referenced directly in shellHook)
        # - github: from nixpkgs 25.11
        # - sequential-thinking: from mcp-servers-nix (issue #285 fixed)
        githubMcpServer = pkgs.github-mcp-server;
        sequentialThinkingMcp = mcp-servers-nix.packages.${system}.mcp-server-sequential-thinking;
      in
      {
        # Default dev shell
        devShells.default = pkgs.mkShell {
          name = "dev-server";

          buildInputs = [
            # Claude Code
            claude-code-nix.packages.${system}.claude-code

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
            pkgs.python312
            pkgs.python312Packages.pip
            pkgs.python312Packages.virtualenv
            pkgs.uv  # Fast Python package installer

            # Python Development Tools
            pkgs.ruff    # Fast Python linter and formatter
            pkgs.black   # Python code formatter
            pkgs.python312Packages.isort   # Import statement organizer
            pkgs.python312Packages.mypy    # Static type checker
            pkgs.python312Packages.pylint        # Comprehensive linter
            pkgs.python312Packages.flake8        # Style guide enforcement
            pkgs.python312Packages.flake8-bugbear # Additional flake8 bug checks

            # Python Testing & Debugging
            pkgs.python312Packages.pytest        # Testing framework
            pkgs.python312Packages.pytest-asyncio # Async test support for FastAPI
            pkgs.python312Packages.pytest-cov    # Test coverage reporting
            pkgs.python312Packages.httpx         # Async HTTP client for testing
            pkgs.python312Packages.ipython       # Enhanced REPL for debugging
            pkgs.python312Packages.rich          # Pretty terminal output
            pkgs.pre-commit                      # Git hooks for code quality

            # Node.js (pinned to v22 - MCP servers require it, see mcp-servers-nix#285)
            pkgs.nodejs_22

            # React/Frontend Development
            pkgs.bun                                    # Fast JS runtime/bundler
            pkgs.pnpm                                   # Efficient package manager
            pkgs.nodePackages.typescript                # TypeScript compiler
            pkgs.nodePackages.typescript-language-server # LSP for editors
            pkgs.nodePackages.eslint                    # JS/TS linting
            pkgs.nodePackages.prettier                  # Code formatting

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
            pkgs.mosh
            pkgs.httpie
            pkgs.websocat

            # Email (msmtp for sending via SMTP relay)
            pkgs.msmtp

            # Development utilities
            pkgs.gh  # GitHub CLI
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

            # Security
            pkgs.gnupg    # GPG for commit signing

            # Productivity
            pkgs.hyperfine  # CLI benchmarking
            pkgs.ncdu       # Disk usage analyzer
            pkgs.tldr       # Simplified man pages
            pkgs.entr       # Run commands when files change
          ];

          shellHook = ''
            # Handle Ghostty terminal - fallback if terminfo missing
            if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null 2>&1; then
              export TERM=xterm-256color
            fi

            export EDITOR=nvim
            export VISUAL=nvim

            # Set up Claude Code MCP servers in ~/.claude.json (user scope)
            # Each server is checked individually - missing ones are added without overwriting existing config
            CLAUDE_JSON="$HOME/.claude.json"
            MCP_UPDATED=false
            GITHUB_NEEDS_TOKEN=false

            # Create file if it doesn't exist
            if [ ! -f "$CLAUDE_JSON" ]; then
              echo '{}' > "$CLAUDE_JSON"
            fi

            # Add context7 if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.context7' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.context7 = {
                "type": "stdio",
                "command": "${mcp-servers-nix.packages.${system}.context7-mcp}/bin/context7-mcp",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added context7 MCP server"
              MCP_UPDATED=true
            fi

            # Add github if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.github' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.github = {
                "type": "stdio",
                "command": "${githubMcpServer}/bin/github-mcp-server",
                "args": ["stdio"],
                "env": {
                  "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_TOKEN_HERE"
                }
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added github MCP server"
              MCP_UPDATED=true
              GITHUB_NEEDS_TOKEN=true
            fi

            # Add sequential-thinking if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers["sequential-thinking"]' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers["sequential-thinking"] = {
                "type": "stdio",
                "command": "${sequentialThinkingMcp}/bin/mcp-server-sequential-thinking",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added sequential-thinking MCP server"
              MCP_UPDATED=true
            fi

            # Show GitHub token instructions only if github was just added
            if [ "$GITHUB_NEEDS_TOKEN" = true ]; then
              echo ""
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "📝 IMPORTANT: Configure GitHub MCP Server"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
              echo "1. Create GitHub Personal Access Token:"
              echo "   → Visit: https://github.com/settings/tokens"
              echo "   → Click 'Generate new token (classic)'"
              echo "   → Scopes: ✓ repo, ✓ read:org, ✓ read:user"
              echo ""
              echo "2. Add token to ~/.claude.json:"
              echo "   → Edit: $CLAUDE_JSON"
              echo "   → Find 'github' → 'env', replace YOUR_TOKEN_HERE:"
              echo "     \"GITHUB_PERSONAL_ACCESS_TOKEN\": \"ghp_...\""
              echo ""
              echo "3. Verify: claude mcp list"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
            fi

            # Set up Claude Code agents and commands
            # Symlink from repo to ~/.claude for version control (self-healing)
            CLAUDE_USER_DIR="$HOME/.claude"
            REPO_CLAUDE_DIR="$HOME/.local/share/bootstrap-dev-server/external/nix-install/config/claude"

            # Helper: ensure symlink points to correct target, fix if broken/wrong
            ensure_symlink() {
              local target="$1"
              local link="$2"
              local current_target
              current_target="$(readlink "$link" 2>/dev/null || true)"
              if [ "$current_target" != "$target" ]; then
                # Backup existing file/dir if not a symlink
                [ -e "$link" ] && [ ! -L "$link" ] && mv "$link" "$link.backup"
                ln -sfn "$target" "$link"
                echo "✓ Linked $link → $target"
              fi
            }

            if [ -d "$REPO_CLAUDE_DIR" ]; then
              mkdir -p "$CLAUDE_USER_DIR"

              # Symlink agents directory
              [ -d "$REPO_CLAUDE_DIR/agents" ] && ensure_symlink "$REPO_CLAUDE_DIR/agents" "$CLAUDE_USER_DIR/agents"

              # Symlink commands directory
              [ -d "$REPO_CLAUDE_DIR/commands" ] && ensure_symlink "$REPO_CLAUDE_DIR/commands" "$CLAUDE_USER_DIR/commands"

              # Symlink CLAUDE.md
              [ -f "$REPO_CLAUDE_DIR/CLAUDE.md" ] && ensure_symlink "$REPO_CLAUDE_DIR/CLAUDE.md" "$CLAUDE_USER_DIR/CLAUDE.md"
            fi

            # Create zsh config directory if needed
            mkdir -p "$HOME/.config/zsh"

            # Generate .zshrc if it doesn't exist or is minimal
            ZSHRC="$HOME/.zshrc"
            if [ ! -f "$ZSHRC" ] || ! grep -q "nix-dev-env" "$ZSHRC" 2>/dev/null; then
              cat > "$ZSHRC" << 'ZSHEOF'
# >>> nix-dev-env zsh config >>>
# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Key bindings (emacs style)
bindkey -e

# Auto-completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Zsh options
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt CORRECT

# Aliases
alias ls='eza --color=auto --icons'
alias ll='eza -la --color=auto --icons'
alias la='eza -a --color=auto --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=plain'
alias grep='rg'
alias find='fd'
alias vim='nvim'
alias vi='nvim'
alias lg='lazygit'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# Directory shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Health check
alias health-check='bash ~/.local/share/bootstrap-dev-server/scripts/health-check.sh'

# Dev environment
alias dev='nix develop ~/.config/nix-dev-env --no-warn-dirty'
alias dm='nix develop ~/.config/nix-dev-env#minimal --no-warn-dirty'
alias dp='nix develop ~/.config/nix-dev-env#python --no-warn-dirty'

# Update dev environment
# - Pulls latest from bootstrap-dev-server repo (flake.nix is symlinked, so changes apply automatically)
# - Updates flake.lock with latest packages
dev-update() {
  echo "🔄 Updating dev environment..."
  local REPO_DIR="$HOME/.local/share/bootstrap-dev-server"
  local FLAKE_DIR="$HOME/.config/nix-dev-env"

  # Pull latest from repo
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "📥 Pulling latest from bootstrap-dev-server repo..."
    (cd "$REPO_DIR" && git pull --quiet) || echo "⚠️  Failed to pull repo (continuing anyway)"

    # Update submodules (Claude Code configs from nix-install)
    echo "🔗 Updating Claude Code configs from nix-install..."
    (cd "$REPO_DIR" && git submodule update --recursive) || echo "⚠️  Failed to update submodules (continuing anyway)"
  fi

  # Update flake.lock (flake.nix is symlinked, no copy needed)
  echo "⬆️  Updating Nix packages..."
  (cd "$FLAKE_DIR" && nix flake update)

  # Commit and push updated flake.lock so new provisions get recent packages
  if [[ -d "$REPO_DIR/.git" ]]; then
    (cd "$REPO_DIR" && git diff --quiet flake.lock 2>/dev/null) || {
      echo "📌 Committing updated flake.lock..."
      (cd "$REPO_DIR" && git add flake.lock && git commit -m "chore: update flake.lock with latest nixpkgs" && git push) \
        || echo "⚠️  Failed to commit/push flake.lock (continuing anyway)"
    }
  fi

  echo ""
  echo "✅ Dev environment updated!"
  echo "   Exit and run 'dev' to use new packages"
}

# Source zsh plugins from Nix store (if available)
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  for dir in /nix/store/*-$plugin-*/share/*; do
    if [ -f "$dir/$plugin.zsh" ]; then
      source "$dir/$plugin.zsh"
      break
    fi
  done
done

# Initialize starship prompt
eval "$(starship init zsh)"

# Initialize zoxide (smart cd)
eval "$(zoxide init zsh)"

# Initialize direnv
eval "$(direnv hook zsh)"

# Initialize fzf
eval "$(fzf --zsh)"

# msmtp sendmail alias
alias sendmail='msmtp'
alias mail='msmtp'

# Auto-launch tmux on SSH connection
# - Attaches to existing 'main' session or creates new one
# - Only runs on SSH connections (not local terminals)
# - Skips if already inside tmux
if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
  tmux attach-session -t main 2>/dev/null || tmux new-session -s main
fi
# <<< nix-dev-env zsh config <<<
ZSHEOF
              echo "✓ Created ~/.zshrc with dev environment config"
            fi

            # Create msmtp config template if not exists
            MSMTP_CONFIG="$HOME/.msmtprc"
            if [ ! -f "$MSMTP_CONFIG" ]; then
              cat > "$MSMTP_CONFIG" << 'MSMTPEOF'
# msmtp configuration for Gandi SMTP
# Edit this file with your actual credentials

# Default settings
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

# Gandi account
account        gandi
host           mail.gandi.net
port           587
from           YOUR_EMAIL@YOUR_DOMAIN.COM
user           YOUR_EMAIL@YOUR_DOMAIN.COM
password       YOUR_PASSWORD_OR_APP_PASSWORD

# Set default account
account default : gandi
MSMTPEOF
              chmod 600 "$MSMTP_CONFIG"
              echo ""
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "📧 CONFIGURE EMAIL: Edit ~/.msmtprc with your Gandi credentials"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
            fi

            # Launch zsh only for interactive shells, not when running commands
            # Check: terminal attached, no command string, not already launched
            if [[ -t 0 && -t 1 && -z "''${BASH_EXECUTION_STRING:-}" && -z "''${__NIX_DEV_ZSH_LAUNCHED:-}" ]]; then
              echo ""
              echo "🚀 Dev Server Environment Loaded"
              echo "   Claude: $(claude --version 2>/dev/null || echo 'run: claude')"
              echo "   Python: $(python3 --version)"
              echo "   Node:   $(node --version)"
              echo "   MCP:    Context7, GitHub, Sequential Thinking"
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

            # Set up Claude Code MCP servers in ~/.claude.json (user scope)
            # Each server is checked individually - missing ones are added without overwriting existing config
            CLAUDE_JSON="$HOME/.claude.json"

            # Create file if it doesn't exist
            if [ ! -f "$CLAUDE_JSON" ]; then
              echo '{}' > "$CLAUDE_JSON"
            fi

            # Add context7 if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.context7' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.context7 = {
                "type": "stdio",
                "command": "${mcp-servers-nix.packages.${system}.context7-mcp}/bin/context7-mcp",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added context7 MCP server"
            fi

            # Add github if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.github' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.github = {
                "type": "stdio",
                "command": "${githubMcpServer}/bin/github-mcp-server",
                "args": ["stdio"],
                "env": {
                  "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_TOKEN_HERE"
                }
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added github MCP server (configure token in ~/.claude.json)"
            fi

            # Add sequential-thinking if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers["sequential-thinking"]' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers["sequential-thinking"] = {
                "type": "stdio",
                "command": "${sequentialThinkingMcp}/bin/mcp-server-sequential-thinking",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added sequential-thinking MCP server"
            fi
          '';
        };

        # Python-focused shell
        devShells.python = pkgs.mkShell {
          name = "python-dev";
          buildInputs = [
            claude-code-nix.packages.${system}.claude-code
            pkgs.python312
            pkgs.python312Packages.pip
            pkgs.python312Packages.virtualenv
            pkgs.uv
            # Python Development Tools
            pkgs.ruff
            pkgs.black
            pkgs.python312Packages.isort
            pkgs.python312Packages.mypy
            pkgs.python312Packages.pylint
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

            # Set up Claude Code MCP servers in ~/.claude.json (user scope)
            # Each server is checked individually - missing ones are added without overwriting existing config
            CLAUDE_JSON="$HOME/.claude.json"

            # Create file if it doesn't exist
            if [ ! -f "$CLAUDE_JSON" ]; then
              echo '{}' > "$CLAUDE_JSON"
            fi

            # Add context7 if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.context7' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.context7 = {
                "type": "stdio",
                "command": "${mcp-servers-nix.packages.${system}.context7-mcp}/bin/context7-mcp",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added context7 MCP server"
            fi

            # Add github if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers.github' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers.github = {
                "type": "stdio",
                "command": "${githubMcpServer}/bin/github-mcp-server",
                "args": ["stdio"],
                "env": {
                  "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_TOKEN_HERE"
                }
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added github MCP server (configure token in ~/.claude.json)"
            fi

            # Add sequential-thinking if missing
            if ! ${pkgs.jq}/bin/jq -e '.mcpServers["sequential-thinking"]' "$CLAUDE_JSON" > /dev/null 2>&1; then
              ${pkgs.jq}/bin/jq '.mcpServers["sequential-thinking"] = {
                "type": "stdio",
                "command": "${sequentialThinkingMcp}/bin/mcp-server-sequential-thinking",
                "args": [],
                "env": {}
              }' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
              echo "✓ Added sequential-thinking MCP server"
            fi
          '';
        };
      });
}
