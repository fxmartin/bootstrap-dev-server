# ABOUTME: Nix flake for CX11 Dev Server Environment
# ABOUTME: Provides development shells with Claude Code, Python, Node.js, and CLI tools
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
  };

  outputs = { self, nixpkgs, flake-utils, claude-code-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
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

            echo ""
            echo "🚀 Dev Server Environment Loaded"
            echo "   Claude: $(claude --version 2>/dev/null || echo 'run: claude')"
            echo "   Python: $(python3 --version)"
            echo "   Node:   $(node --version)"
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
          ];
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
          ];
        };
      });
}
