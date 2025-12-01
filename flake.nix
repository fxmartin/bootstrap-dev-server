# ABOUTME: Nix flake for CX11 Dev Server Environment
# ABOUTME: Provides development shells with Claude Code, MCP servers, Python, Node.js, and CLI tools
{
  description = "CX11 Dev Server Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Claude Code with auto-updates
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP servers for Claude Code (Context7, GitHub, Sequential Thinking)
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

        # Generate MCP server configuration
        mcpConfig = mcp-servers-nix.lib.mkConfig pkgs {
          programs = {
            # Context7 MCP server - No authentication required
            context7.enable = true;
            # GitHub MCP server - Requires GITHUB_PERSONAL_ACCESS_TOKEN
            github.enable = true;
            # Sequential Thinking MCP server - No authentication required
            sequential-thinking.enable = true;
          };
        };
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
            pkgs.fd
            pkgs.bat
            pkgs.eza
            pkgs.fzf
            pkgs.tree
            pkgs.htop
            pkgs.btop
            pkgs.gotop  # Terminal-based graphical activity monitor

            # Editors
            pkgs.neovim
            pkgs.helix

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
            pkgs.python312Packages.pylint  # Comprehensive linter

            # Node.js
            pkgs.nodejs_22

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
            pkgs.lazygit
            pkgs.delta  # Git diff viewer

            # Linting & testing
            pkgs.shellcheck  # Shell script linter
          ];

          shellHook = ''
            export EDITOR=nvim
            export VISUAL=nvim

            # Set up Claude Code MCP configuration if not exists
            CLAUDE_CONFIG_DIR="$HOME/.config/claude"
            CLAUDE_CONFIG_JSON="$CLAUDE_CONFIG_DIR/config.json"

            if [ ! -f "$CLAUDE_CONFIG_JSON" ]; then
              mkdir -p "$CLAUDE_CONFIG_DIR"
              cp "${mcpConfig}" "$CLAUDE_CONFIG_JSON"
              echo "✓ Created Claude Code MCP config: $CLAUDE_CONFIG_JSON"
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
              echo "2. Add token to config.json:"
              echo "   → Edit: $CLAUDE_CONFIG_JSON"
              echo "   → Find 'github' section, add to 'env':"
              echo "     \"GITHUB_PERSONAL_ACCESS_TOKEN\": \"ghp_...\""
              echo ""
              echo "3. Verify: claude mcp list"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo ""
            fi

            # Set up Claude Code agents and commands
            # Symlink from repo to ~/.claude for version control
            CLAUDE_USER_DIR="$HOME/.claude"
            REPO_CLAUDE_DIR="$HOME/.local/share/nix-install/bootstrap-dev-server/config/claude"

            if [ -d "$REPO_CLAUDE_DIR" ]; then
              mkdir -p "$CLAUDE_USER_DIR"

              # Symlink agents directory
              if [ -d "$REPO_CLAUDE_DIR/agents" ] && [ ! -L "$CLAUDE_USER_DIR/agents" ]; then
                [ -d "$CLAUDE_USER_DIR/agents" ] && mv "$CLAUDE_USER_DIR/agents" "$CLAUDE_USER_DIR/agents.backup"
                ln -sfn "$REPO_CLAUDE_DIR/agents" "$CLAUDE_USER_DIR/agents"
                echo "✓ Linked ~/.claude/agents → repo"
              fi

              # Symlink commands directory
              if [ -d "$REPO_CLAUDE_DIR/commands" ] && [ ! -L "$CLAUDE_USER_DIR/commands" ]; then
                [ -d "$CLAUDE_USER_DIR/commands" ] && mv "$CLAUDE_USER_DIR/commands" "$CLAUDE_USER_DIR/commands.backup"
                ln -sfn "$REPO_CLAUDE_DIR/commands" "$CLAUDE_USER_DIR/commands"
                echo "✓ Linked ~/.claude/commands → repo"
              fi

              # Symlink CLAUDE.md
              if [ -f "$REPO_CLAUDE_DIR/CLAUDE.md" ] && [ ! -L "$CLAUDE_USER_DIR/CLAUDE.md" ]; then
                [ -f "$CLAUDE_USER_DIR/CLAUDE.md" ] && mv "$CLAUDE_USER_DIR/CLAUDE.md" "$CLAUDE_USER_DIR/CLAUDE.md.backup"
                ln -sf "$REPO_CLAUDE_DIR/CLAUDE.md" "$CLAUDE_USER_DIR/CLAUDE.md"
                echo "✓ Linked ~/.claude/CLAUDE.md → repo"
              fi
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

# Dev environment
alias dev='nix develop ~/.config/nix-dev-env'
alias dm='nix develop ~/.config/nix-dev-env#minimal'
alias dp='nix develop ~/.config/nix-dev-env#python'

# Update dev environment
# - Pulls latest from nix-install repo
# - Syncs flake.nix to ~/.config/nix-dev-env
# - Updates flake.lock with latest packages
# - Rebuilds the environment
dev-update() {
  echo "🔄 Updating dev environment..."
  local REPO_DIR="$HOME/.local/share/nix-install"
  local FLAKE_DIR="$HOME/.config/nix-dev-env"

  # Pull latest from repo
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "📥 Pulling latest from nix-install repo..."
    (cd "$REPO_DIR" && git pull --quiet) || echo "⚠️  Failed to pull repo (continuing anyway)"
  fi

  # Sync flake.nix from repo to config
  local SOURCE_FLAKE="$REPO_DIR/bootstrap-dev-server/flake.nix"
  if [[ -f "$SOURCE_FLAKE" ]]; then
    echo "📋 Syncing flake.nix..."
    cp "$SOURCE_FLAKE" "$FLAKE_DIR/flake.nix"
    (cd "$FLAKE_DIR" && git add -A)
  fi

  # Update flake.lock
  echo "⬆️  Updating Nix packages..."
  (cd "$FLAKE_DIR" && nix flake update)

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
            # Set up Claude Code MCP configuration if not exists
            CLAUDE_CONFIG_DIR="$HOME/.config/claude"
            CLAUDE_CONFIG_JSON="$CLAUDE_CONFIG_DIR/config.json"

            if [ ! -f "$CLAUDE_CONFIG_JSON" ]; then
              mkdir -p "$CLAUDE_CONFIG_DIR"
              cp "${mcpConfig}" "$CLAUDE_CONFIG_JSON"
              echo "✓ Created Claude Code MCP config: $CLAUDE_CONFIG_JSON"
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
            # Set up Claude Code MCP configuration if not exists
            CLAUDE_CONFIG_DIR="$HOME/.config/claude"
            CLAUDE_CONFIG_JSON="$CLAUDE_CONFIG_DIR/config.json"

            if [ ! -f "$CLAUDE_CONFIG_JSON" ]; then
              mkdir -p "$CLAUDE_CONFIG_DIR"
              cp "${mcpConfig}" "$CLAUDE_CONFIG_JSON"
              echo "✓ Created Claude Code MCP config: $CLAUDE_CONFIG_JSON"
            fi
          '';
        };
      });
}
