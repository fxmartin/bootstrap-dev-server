#!/usr/bin/env bash
# ABOUTME: Migration script to add auto-launch tmux + auto-enter dev shell on SSH login
# ABOUTME: Run on existing dev servers to apply the auto-dev-shell feature without full re-bootstrap
#
# Usage: ssh dev-server 'bash -s' < scripts/migrate-auto-dev-shell.sh
#    or: scp scripts/migrate-auto-dev-shell.sh dev-server: && ssh dev-server ./migrate-auto-dev-shell.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}[OK]${NC}    ${1}"; }
log_info() { echo -e "${BLUE}[INFO]${NC}  ${1}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  ${1}"; }

FLAKE_DIR="${HOME}/.config/nix-dev-env"
BASHRC="${HOME}/.bashrc"
ZSHRC="${HOME}/.zshrc"
CHANGES_MADE=false

#===============================================================================
# Patch .bashrc - add tmux auto-launch + auto-enter dev shell
#===============================================================================
patch_bashrc() {
    log_info "Checking .bashrc..."

    if [[ ! -f "${BASHRC}" ]]; then
        log_warn ".bashrc not found - skipping"
        return 0
    fi

    # Check if nix-dev-env block exists
    if ! grep -q '# >>> nix-dev-env >>>' "${BASHRC}"; then
        log_warn "No nix-dev-env block in .bashrc - run full bootstrap first"
        return 1
    fi

    # Check if already patched
    if grep -q 'Auto-launch tmux on SSH/Mosh' "${BASHRC}"; then
        log_ok ".bashrc already has tmux auto-launch"
        return 0
    fi

    # Insert before the closing marker
    local tmp="${BASHRC}.migrate.tmp"
    cp "${BASHRC}" "${tmp}"

    sed -i '/# <<< nix-dev-env <<</i\
\
# Auto-launch tmux on SSH/Mosh connection\
# - Attaches to existing '\''main'\'' session or creates new one\
# - Only runs on SSH/Mosh connections (not local terminals)\
# - Skips if already inside tmux\
if [[ ( -n "${SSH_CONNECTION:-}" || -n "${MOSH_CONNECTION:-}" ) && -z "${TMUX:-}" ]]; then\
    tmux attach-session -t main 2>/dev/null || tmux new-session -s main\
fi\
\
# Auto-enter nix dev shell inside tmux\
# - Only activates inside tmux sessions (new panes/windows get it too)\
# - Skips if already inside a nix dev shell (IN_NIX_SHELL is set by nix develop)\
# - Uses exec so exiting the dev shell exits the pane cleanly\
if [[ -n "${TMUX:-}" \\&\\& -z "${IN_NIX_SHELL:-}" ]]; then\
    exec nix develop '"${FLAKE_DIR}"' --no-warn-dirty -c ${SHELL}\
fi' "${BASHRC}"

    # Verify the patch worked
    if grep -q 'Auto-launch tmux on SSH/Mosh' "${BASHRC}"; then
        rm -f "${tmp}"
        log_ok ".bashrc patched with tmux auto-launch + auto-enter dev shell"
        CHANGES_MADE=true
    else
        # Restore backup
        mv "${tmp}" "${BASHRC}"
        log_warn ".bashrc patch failed - restored backup"
        return 1
    fi
}

#===============================================================================
# Patch .zshrc - add auto-enter dev shell (tmux auto-launch already exists)
#===============================================================================
patch_zshrc() {
    log_info "Checking .zshrc..."

    if [[ ! -f "${ZSHRC}" ]]; then
        log_warn ".zshrc not found - will be generated on next dev shell entry"
        return 0
    fi

    # Check if nix-dev-env block exists
    if ! grep -q 'nix-dev-env' "${ZSHRC}"; then
        log_warn "No nix-dev-env block in .zshrc - will be regenerated on next dev shell entry"
        return 0
    fi

    # Check if already patched
    if grep -q 'Auto-enter nix dev shell' "${ZSHRC}"; then
        log_ok ".zshrc already has auto-enter dev shell"
        return 0
    fi

    # Insert before the closing marker
    local tmp="${ZSHRC}.migrate.tmp"
    cp "${ZSHRC}" "${tmp}"

    sed -i '/# <<< nix-dev-env zsh config <<</i\
\
# Auto-enter nix dev shell inside tmux\
# - Only activates inside tmux sessions (new panes/windows get it too)\
# - Skips if already inside a nix dev shell (IN_NIX_SHELL is set by nix develop)\
# - Uses exec so exiting the dev shell exits the pane cleanly\
if [[ -n "$TMUX" \\&\\& -z "$IN_NIX_SHELL" ]]; then\
  exec nix develop ~/.config/nix-dev-env --no-warn-dirty -c zsh\
fi' "${ZSHRC}"

    # Verify the patch worked
    if grep -q 'Auto-enter nix dev shell' "${ZSHRC}"; then
        rm -f "${tmp}"
        log_ok ".zshrc patched with auto-enter dev shell"
        CHANGES_MADE=true
    else
        mv "${tmp}" "${ZSHRC}"
        log_warn ".zshrc patch failed - restored backup"
        return 1
    fi
}

#===============================================================================
# Pull latest repo (gets updated flake.nix with auto-enter block for new .zshrc)
#===============================================================================
update_repo() {
    local repo_dir="${HOME}/.local/share/bootstrap-dev-server"

    if [[ -d "${repo_dir}/.git" ]]; then
        log_info "Pulling latest bootstrap-dev-server repo..."
        if (cd "${repo_dir}" && git pull --quiet); then
            log_ok "Repo updated (flake.nix now includes auto-enter for new .zshrc generation)"
        else
            log_warn "Failed to pull repo (continuing with local patches)"
        fi
    fi
}

#===============================================================================
# Main
#===============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Migration: Auto-enter dev shell on SSH login${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

update_repo
patch_bashrc
patch_zshrc

echo ""
if [[ "${CHANGES_MADE}" == "true" ]]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Migration complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Next SSH/Mosh connection will automatically:"
    echo -e "    1. Launch tmux (session 'main')"
    echo -e "    2. Enter nix dev shell"
    echo ""
    echo -e "  ${YELLOW}Disconnect and reconnect to activate.${NC}"
else
    echo -e "${GREEN}  No changes needed - already up to date.${NC}"
fi
echo ""
