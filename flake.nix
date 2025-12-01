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
            pkgs.tmux
            pkgs.zoxide
            pkgs.starship
            pkgs.direnv

            # Python
            pkgs.python312
            pkgs.python312Packages.pip
            pkgs.python312Packages.virtualenv
            pkgs.uv  # Fast Python package installer

            # Node.js
            pkgs.nodejs_22

            # Container tools
            pkgs.podman
            pkgs.podman-compose

            # Network tools
            pkgs.httpie
            pkgs.websocat

            # Development utilities
            pkgs.gh  # GitHub CLI
            pkgs.lazygit
            pkgs.delta  # Git diff viewer
          ];

          shellHook = ''
            export EDITOR=nvim
            export VISUAL=nvim

            # Starship prompt
            eval "$(starship init bash)"

            # Zoxide (smart cd)
            eval "$(zoxide init bash)"

            # Direnv
            eval "$(direnv hook bash)"

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

            echo ""
            echo "🚀 Dev Server Environment Loaded"
            echo "   Claude: $(claude --version 2>/dev/null || echo 'run: claude')"
            echo "   Python: $(python3 --version)"
            echo "   Node:   $(node --version)"
            echo "   MCP:    Context7, GitHub, Sequential Thinking"
            echo ""
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
            pkgs.ruff
            pkgs.git
            pkgs.neovim
            pkgs.gotop
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
