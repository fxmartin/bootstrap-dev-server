#!/usr/bin/env bash
# ABOUTME: Installs Beszel agent on the dev server for system resource monitoring
# ABOUTME: Downloads binary, configures systemd user service, prompts for hub key

set -euo pipefail

# ============================================
# Logging
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/logging.sh"

if [[ -f "${LIB_PATH}" ]]; then
    # shellcheck source=../lib/logging.sh
    source "${LIB_PATH}"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    # shellcheck disable=SC2312
    log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[INFO]${NC}  ${1}"; }
    # shellcheck disable=SC2312
    log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[OK]${NC}    ${1}"; }
    # shellcheck disable=SC2312
    log_warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARN]${NC}  ${1}" >&2; }
    # shellcheck disable=SC2312
    log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} ${1}" >&2; }
fi

# ============================================
# Configuration
# ============================================

BIN_DIR="${HOME}/.local/bin"
SERVICE_DIR="${HOME}/.config/systemd/user"
ENV_FILE="${HOME}/.config/beszel-agent.env"
AGENT_PORT="${BESZEL_AGENT_PORT:-45876}"

BESZEL_BASE_URL="https://github.com/henrygd/beszel/releases/latest/download"

# ============================================
# Installation
# ============================================

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "arm" ;;
        *)       echo "$arch" ;;
    esac
}

install_binary() {
    local os arch tarball_url
    os=$(uname -s)
    arch=$(detect_arch)
    tarball_url="${BESZEL_BASE_URL}/beszel-agent_${os}_${arch}.tar.gz"

    mkdir -p "${BIN_DIR}"

    if [[ -f "${BIN_DIR}/beszel-agent" ]]; then
        log_info "Beszel agent binary already exists, updating..."
    fi

    log_info "Downloading beszel-agent for ${os}/${arch}..."
    if ! curl -sL "${tarball_url}" | tar -xz -C "${BIN_DIR}" beszel-agent 2>/dev/null; then
        log_error "Failed to download beszel-agent from: ${tarball_url}"
        return 1
    fi
    chmod 755 "${BIN_DIR}/beszel-agent"

    log_ok "Beszel agent installed: ${BIN_DIR}/beszel-agent"
}

configure_env() {
    mkdir -p "$(dirname "${ENV_FILE}")"

    if [[ -f "${ENV_FILE}" ]] && grep -q '^KEY=.\+' "${ENV_FILE}" 2>/dev/null; then
        log_ok "Agent environment already configured: ${ENV_FILE}"
        return 0
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Beszel Agent Configuration"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "  To get the KEY value:"
    echo "  1. Open Beszel Hub in your browser"
    echo "  2. Click 'Add System'"
    echo "  3. Copy the SSH public key shown"
    echo ""

    read -rp "Enter Beszel Hub KEY (or press Enter to skip): " agent_key

    if [[ -z "${agent_key}" ]]; then
        log_warn "No KEY provided. Creating placeholder env file."
        cat > "${ENV_FILE}" <<EOF
# Beszel agent configuration
# Get the KEY value from Beszel Hub after adding this system
KEY=
PORT=${AGENT_PORT}
EOF
    else
        cat > "${ENV_FILE}" <<EOF
KEY=${agent_key}
PORT=${AGENT_PORT}
EOF
        log_ok "Agent environment configured"
    fi
}

install_service() {
    mkdir -p "${SERVICE_DIR}"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_dir
    repo_dir="$(dirname "${script_dir}")"
    local service_src="${repo_dir}/config/beszel-agent.service"

    if [[ -f "${service_src}" ]]; then
        cp "${service_src}" "${SERVICE_DIR}/beszel-agent.service"
    else
        log_warn "Service file not found at ${service_src}, using embedded config"
        cat > "${SERVICE_DIR}/beszel-agent.service" <<EOF
[Unit]
Description=Beszel Agent - System Resource Metrics Collector
After=network.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${BIN_DIR}/beszel-agent
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
    fi

    systemctl --user daemon-reload
    systemctl --user enable beszel-agent

    if grep -q '^KEY=.\+' "${ENV_FILE}" 2>/dev/null; then
        systemctl --user start beszel-agent
        log_ok "Beszel Agent running on port ${AGENT_PORT}"
    else
        log_warn "Beszel Agent enabled but not started (KEY not configured)"
        echo ""
        echo "After configuring KEY in ${ENV_FILE}, run:"
        echo "  systemctl --user start beszel-agent"
    fi
}

# ============================================
# Main
# ============================================

main() {
    echo ""
    echo "═══ Installing Beszel Agent ═══"
    echo ""

    install_binary
    configure_env
    install_service

    echo ""
    log_ok "Beszel agent installation complete"
    echo ""
}

main "$@"
