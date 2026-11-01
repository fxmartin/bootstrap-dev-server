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

# shellcheck source=../lib/rc-block.sh
source "${REPO_DIR}/lib/rc-block.sh"

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

# Keep our .zshrc block current, so config changes reach provisioned servers
write_zshrc() {
    mkdir -p "$(dirname "${ZSHRC}")" "${HOME}/.config/zsh"
    if write_rc_block "${ZSHRC}" "# >>> nix-dev-env zsh config >>>" "# <<< nix-dev-env zsh config <<<" <<'ZSHEOF'; then
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
# - The repository is the only source of flake.lock: hard-resets the checkout
#   to origin/main (flake.nix is symlinked, so the checkout IS the flake),
#   builds dev-env, and only then upgrades the profile
# - Never bumps the lock itself; lock updates arrive through merge requests
dev-update() {
  echo "🔄 Updating dev environment..."
  local REPO_DIR="$HOME/.local/share/bootstrap-dev-server"
  local FLAKE_DIR="$HOME/.config/nix-dev-env"

  if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "❌ No checkout at $REPO_DIR"
    return 1
  fi

  echo "📥 Fetching origin..."
  (cd "$REPO_DIR" && git fetch --quiet origin) || {
    echo "❌ Failed to fetch origin - nothing applied"
    return 1
  }

  # Log what the reset throws away so nothing vanishes silently
  local discarded
  discarded="$(cd "$REPO_DIR" && git diff --stat HEAD)"
  if [[ -n "$discarded" ]]; then
    echo "⚠️  Discarding local changes:"
    echo "$discarded"
  fi
  discarded="$(cd "$REPO_DIR" && git log --oneline origin/main..HEAD)"
  if [[ -n "$discarded" ]]; then
    echo "⚠️  Discarding local commits:"
    echo "$discarded"
  fi

  (cd "$REPO_DIR" && git reset --hard --quiet origin/main) || {
    echo "❌ Failed to reset to origin/main"
    return 1
  }

  # Update submodules (Claude Code configs from nix-install)
  (cd "$REPO_DIR" && git submodule update --recursive) || echo "⚠️  Failed to update submodules (continuing anyway)"

  # --no-update-lock-file: a flake.nix the committed lock does not cover fails
  # here instead of locking on the box
  echo "🔨 Building dev-env..."
  nix build "$FLAKE_DIR#dev-env" --no-update-lock-file --no-link || {
    echo "❌ Build failed - profile left unchanged"
    return 1
  }
  nix profile upgrade dev-env || {
    echo "❌ nix profile upgrade dev-env failed"
    return 1
  }

  # Converge the sdlc controller to the tag pinned in config/versions.env. The
  # profile upgrade already succeeded, so a failure or refusal only warns.
  local sdlc_installer="$REPO_DIR/scripts/install-sdlc-controller.sh"
  if [[ ! -f "$sdlc_installer" ]] || ! bash "$sdlc_installer"; then
    echo "⚠️  sdlc controller not converged to the pinned tag; re-run: bash $sdlc_installer"
  fi

  echo ""
  echo "✅ Dev environment updated to $(git -C "$REPO_DIR" log -1 --oneline)"
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

# Attach to the herdr server on an interactive ssh login
# - Same guard as the ~/.bashrc block, which is what a provisioned server's bash login
#   reads; this copy covers a login shell changed to zsh by hand
# - SSH_TTY set: `ssh dev '<cmd>'`, scp and probes have none. `ssh -t dev <cmd>` has one,
#   but runs a non-interactive shell that never reads this file
# - SSH_ORIGINAL_COMMAND: sshd sets it only for a forced command (authorized_keys command=)
# - Skipped inside herdr (HERDR_ENV) or tmux (TMUX) so a pane never nests a client
# - Skipped with NO_HERDR=1, e.g. `ssh -o SetEnv=NO_HERDR=1 dev` (sshd AcceptEnv NO_HERDR)
# - Exports NO_HERDR before the client, however it ends: zsh, exec zsh and `dev` run from
#   this login inherit SSH_TTY and read this file, and must stay plain shells
# - Not exec'd: quitting herdr returns to this plain login shell
herdr_login_attach() {
  [[ -n "${SSH_TTY:-}" && -z "${SSH_ORIGINAL_COMMAND:-}" ]] || return 0
  [[ -z "${HERDR_ENV:-}" && -z "${TMUX:-}" ]] || return 0
  [[ -z "${NO_HERDR:-}" || "${NO_HERDR}" == "0" ]] || return 0
  command -v herdr >/dev/null 2>&1 || return 0
  export NO_HERDR=1
  herdr
  return 0
}
herdr_login_attach
# <<< nix-dev-env zsh config <<<
ZSHEOF
        log_ok "Wrote dev environment config to ~/.zshrc"
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
