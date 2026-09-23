#!/usr/bin/env bash
# ABOUTME: Installs Prometheus node_exporter as a tailnet-only system service
# ABOUTME: Pinned release, sha256-verified download, dedicated user, UFW rule on tailscale0
#
# Prometheus on the NAS scrapes this over Tailscale (fxmartin/nix-install
# Epic-15 "Fleet Cockpit"). node_exporter has NO authentication: the unit binds
# to the Tailscale IP only (config/node-exporter-start.sh), UFW opens 9100 on
# tailscale0 only, and the Tailscale ACL decides who may scrape.
#
# Idempotent: re-running converges the binary to the pinned version and leaves
# an up-to-date install untouched. Every path is env-overridable so
# tests/node-exporter.bats can run this end to end against a file:// release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
LIB_PATH="${REPO_DIR}/lib/logging.sh"

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

# Pinned on purpose. The previous agent's installer pulled whatever release
# was newest, which made every install unreproducible. Bump deliberately and
# re-run to converge.
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.12.1}"
NODE_EXPORTER_BASE_URL="${NODE_EXPORTER_BASE_URL:-https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}}"
NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-9100}"
NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-node_exporter}"
BIN_DIR="${NODE_EXPORTER_BIN_DIR:-/usr/local/bin}"
UNIT_DIR="${NODE_EXPORTER_UNIT_DIR:-/etc/systemd/system}"
TEXTFILE_DIR="${NODE_EXPORTER_TEXTFILE_DIR:-/var/lib/node_exporter/textfile}"
CONFIG_DIR="${REPO_DIR}/config"

# Root runs the privileged commands directly; anyone else goes through sudo.
SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

# Scratch directory for the download; removed on any exit, including a
# failed checksum, so a rejected tarball never lingers.
WORK_DIR=""
cleanup() {
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

# ============================================
# Helpers
# ============================================

detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)
            log_error "Unsupported architecture '$(uname -m)': upstream ships linux-amd64 and linux-arm64 only"
            return 1
            ;;
    esac
}

installed_version() {
    [[ -x "${BIN_DIR}/node_exporter" ]] || return 1
    "${BIN_DIR}/node_exporter" --version 2>&1 | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

# Downloads the tarball and sha256sums.txt from the same pinned release and
# verifies the tarball against it. Refuses on a mismatch or a missing entry.
download_and_verify() {
    local work_dir="$1" tarball="$2"
    local checksum_line

    log_info "Downloading ${tarball}..."
    curl -fsSL -o "${work_dir}/${tarball}" "${NODE_EXPORTER_BASE_URL}/${tarball}"
    curl -fsSL -o "${work_dir}/sha256sums.txt" "${NODE_EXPORTER_BASE_URL}/sha256sums.txt"

    checksum_line="$(grep -E "[[:space:]]+${tarball}\$" "${work_dir}/sha256sums.txt" || true)"
    if [[ -z "${checksum_line}" ]]; then
        log_error "No checksum for ${tarball} in sha256sums.txt - refusing to install"
        return 1
    fi

    if ! (cd "${work_dir}" && echo "${checksum_line}" | sha256sum -c - >/dev/null 2>&1); then
        log_error "Checksum mismatch for ${tarball} - refusing to install"
        return 1
    fi
    log_ok "Checksum verified against sha256sums.txt"
}

# ============================================
# Installation
# ============================================

create_user() {
    if getent passwd "${NODE_EXPORTER_USER}" >/dev/null 2>&1; then
        log_ok "User ${NODE_EXPORTER_USER} already exists"
        return 0
    fi
    ${SUDO} useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "${NODE_EXPORTER_USER}"
    log_ok "Created system user ${NODE_EXPORTER_USER}"
}

create_textfile_dir() {
    # Reserved for future custom metrics (*.prom files written by root jobs).
    ${SUDO} mkdir -p "${TEXTFILE_DIR}"
    ${SUDO} chmod 0755 "${TEXTFILE_DIR}"
    log_ok "Textfile collector directory: ${TEXTFILE_DIR}"
}

install_binary() {
    local arch current tarball work_dir
    arch="$(detect_arch)"

    current="$(installed_version || true)"
    if [[ "${current}" == "${NODE_EXPORTER_VERSION}" ]]; then
        log_ok "node_exporter ${NODE_EXPORTER_VERSION} already installed"
        return 0
    fi

    tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    work_dir="$(mktemp -d)"
    WORK_DIR="${work_dir}"

    download_and_verify "${work_dir}" "${tarball}"

    tar -xzf "${work_dir}/${tarball}" -C "${work_dir}" \
        "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter"
    ${SUDO} mkdir -p "${BIN_DIR}"
    ${SUDO} install -m 0755 \
        "${work_dir}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" \
        "${BIN_DIR}/node_exporter"

    if [[ -n "${current}" ]]; then
        log_ok "node_exporter updated ${current} -> ${NODE_EXPORTER_VERSION}"
    else
        log_ok "node_exporter ${NODE_EXPORTER_VERSION} installed to ${BIN_DIR}/node_exporter"
    fi
}

install_wrapper() {
    local src="${CONFIG_DIR}/node-exporter-start.sh"
    if [[ ! -f "${src}" ]]; then
        log_error "Start wrapper not found: ${src} (run from a full checkout of the repo)"
        return 1
    fi
    ${SUDO} install -m 0755 "${src}" "${BIN_DIR}/node-exporter-start"
    log_ok "Start wrapper installed to ${BIN_DIR}/node-exporter-start"
}

install_unit() {
    local src="${CONFIG_DIR}/node-exporter.service"
    if [[ ! -f "${src}" ]]; then
        log_error "Unit file not found: ${src} (run from a full checkout of the repo)"
        return 1
    fi
    ${SUDO} mkdir -p "${UNIT_DIR}"
    ${SUDO} install -m 0644 "${src}" "${UNIT_DIR}/node-exporter.service"
    ${SUDO} systemctl daemon-reload
    ${SUDO} systemctl enable --now node-exporter.service
    log_ok "node-exporter.service enabled"
}

configure_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        log_warn "ufw not found - open ${NODE_EXPORTER_PORT}/tcp on tailscale0 ONLY, never publicly"
        return 0
    fi
    # tailscale0 only. There is no rule on the public interface, by design.
    ${SUDO} ufw allow in on tailscale0 to any port "${NODE_EXPORTER_PORT}" proto tcp comment 'node_exporter (tailnet only)'
    log_ok "UFW: ${NODE_EXPORTER_PORT}/tcp allowed on tailscale0 only"
}

# ============================================
# Main
# ============================================

main() {
    echo ""
    echo "═══ Installing node_exporter ${NODE_EXPORTER_VERSION} (tailnet-only) ═══"
    echo ""

    create_user
    create_textfile_dir
    install_binary
    install_wrapper
    install_unit
    configure_firewall

    echo ""
    log_ok "node_exporter ready - Prometheus on the NAS scrapes <tailscale-ip>:${NODE_EXPORTER_PORT}"
    log_info "Tailscale ACL must allow the NAS to reach this node on ${NODE_EXPORTER_PORT}"
    echo ""
}

main "$@"
