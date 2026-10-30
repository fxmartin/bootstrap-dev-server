#!/usr/bin/env bash
# ABOUTME: Applies the per-user setup the dev shell's shellHook used to do on every `dev`
# ABOUTME: Claude config symlinks, stale MCP pruning, zshrc and msmtprc templates
#
# Runs from the bootstrap (after the dev-env profile is installed), so agents,
# sdlc and acmd get the same state without anyone entering `dev` first.
# Idempotent: every step converges and leaves an up-to-date setup untouched.
# Paths are env-overridable so tests/flake.bats can run it against a temp HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
LIB_PATH="${REPO_DIR}/lib/logging.sh"

if [[ -f "${LIB_PATH}" ]]; then
    # shellcheck source=../lib/logging.sh
    source "${LIB_PATH}"
else
    # shellcheck disable=SC2312
    log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  ${1}"; }
    # shellcheck disable=SC2312
    log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [OK]    ${1}"; }
    # shellcheck disable=SC2312
    log_warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  ${1}" >&2; }
fi

CLAUDE_JSON="${CLAUDE_JSON:-${HOME}/.claude.json}"
CLAUDE_USER_DIR="${CLAUDE_USER_DIR:-${HOME}/.claude}"
REPO_CLAUDE_DIR="${REPO_CLAUDE_DIR:-${HOME}/.local/share/bootstrap-dev-server/external/nix-install/config/claude}"
ZSHRC="${ZSHRC:-${HOME}/.zshrc}"
MSMTP_CONFIG="${MSMTP_CONFIG:-${HOME}/.msmtprc}"

# The dev-env profile supplies jq; make it findable when run outside a login shell.
export PATH="${HOME}/.nix-profile/bin:${PATH}"

# Prune MCP servers dropped from the flake.
# Their /nix/store paths get garbage-collected, so a leftover entry
# makes Claude Code fail to start that server on every launch.
prune_stale_mcp() {
    [[ -f "${CLAUDE_JSON}" ]] || return 0
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found - skipping stale MCP pruning"
        return 0
    fi
    if jq -e '.mcpServers.context7 // .mcpServers["sequential-thinking"]' "${CLAUDE_JSON}" >/dev/null 2>&1; then
        jq 'del(.mcpServers.context7) | del(.mcpServers["sequential-thinking"])' \
            "${CLAUDE_JSON}" >"${CLAUDE_JSON}.tmp" && mv "${CLAUDE_JSON}.tmp" "${CLAUDE_JSON}"
        log_ok "Pruned stale MCP server entries from ~/.claude.json"
    fi
}

# Ensure the symlink points at the right target, fixing it if broken/wrong
ensure_symlink() {
    local target="$1"
    local link="$2"
    local current_target
    current_target="$(readlink "${link}" 2>/dev/null || true)"
    if [[ "${current_target}" != "${target}" ]]; then
        # Backup existing file/dir if not a symlink
        if [[ -e "${link}" && ! -L "${link}" ]]; then
            mv "${link}" "${link}.backup"
        fi
        ln -sfn "${target}" "${link}"
        log_ok "Linked ${link} -> ${target}"
    fi
}

# Symlink from the repo to ~/.claude for version control (self-healing)
link_claude_config() {
    [[ -d "${REPO_CLAUDE_DIR}" ]] || return 0
    mkdir -p "${CLAUDE_USER_DIR}"

    [[ -d "${REPO_CLAUDE_DIR}/agents" ]] && ensure_symlink "${REPO_CLAUDE_DIR}/agents" "${CLAUDE_USER_DIR}/agents"
    [[ -d "${REPO_CLAUDE_DIR}/commands" ]] && ensure_symlink "${REPO_CLAUDE_DIR}/commands" "${CLAUDE_USER_DIR}/commands"
    [[ -f "${REPO_CLAUDE_DIR}/CLAUDE.md" ]] && ensure_symlink "${REPO_CLAUDE_DIR}/CLAUDE.md" "${CLAUDE_USER_DIR}/CLAUDE.md"
    [[ -f "${REPO_CLAUDE_DIR}/statusline-command.sh" ]] && ensure_symlink "${REPO_CLAUDE_DIR}/statusline-command.sh" "${CLAUDE_USER_DIR}/statusline-command.sh"
    [[ -f "${REPO_CLAUDE_DIR}/settings.json" ]] && ensure_symlink "${REPO_CLAUDE_DIR}/settings.json" "${CLAUDE_USER_DIR}/settings.json"
    return 0
}

# Generate .zshrc if it doesn't exist or doesn't carry our block
write_zshrc() {
    mkdir -p "$(dirname "${ZSHRC}")" "${HOME}/.config/zsh"
    if [[ ! -f "${ZSHRC}" ]] || ! grep -q "nix-dev-env" "${ZSHRC}" 2>/dev/null; then
        cat >"${ZSHRC}" <<'ZSHEOF'
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
if [[ ( -n "$SSH_CONNECTION" || -n "$MOSH_CONNECTION" ) && -z "$TMUX" ]]; then
  tmux attach-session -t main 2>/dev/null || tmux new-session -s main
fi
# <<< nix-dev-env zsh config <<<
ZSHEOF
        log_ok "Created ~/.zshrc with dev environment config"
    fi
}

# Create msmtp config template if not exists
write_msmtprc() {
    if [[ ! -f "${MSMTP_CONFIG}" ]]; then
        cat >"${MSMTP_CONFIG}" <<'MSMTPEOF'
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
        chmod 600 "${MSMTP_CONFIG}"
        log_warn "Configure email: edit ~/.msmtprc with your SMTP credentials"
    fi
}

main() {
    prune_stale_mcp
    link_claude_config
    write_zshrc
    write_msmtprc
}

main "$@"
