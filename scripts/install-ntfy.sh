#!/usr/bin/env bash
# ABOUTME: Installs ntfy as a tailnet-only system service for acm's phone alerts (acm Epic-17, P2)
# ABOUTME: Pinned release, sha256-verified download, dedicated user, a user and topic per phone
#
# acmd publishes nudges here and the phone's ntfy app delivers them through
# UnifiedPush. Nothing here is public: the unit binds to the Tailscale IP only
# (config/ntfy-start.sh), UFW opens 2586 on tailscale0 only, and access is denied
# by default.
#
# Phones are the valid lines of the phone key file (lib/acm-phone-keys.sh): each
# gets an ntfy user named after it and the topic acm-<name>, declared in
# /etc/ntfy/server.yml, so a revoked phone's user disappears at the next start.
#
# UnifiedPush needs one exception: the publisher is anonymous, so `up*` topics are
# write-only for everyone, and only the phones may read them. A tailnet node can
# therefore post to a phone's up<random> topic, if it knows the name.
#
# Idempotent: re-running converges to the pinned version and restarts ntfy only
# when something changed. Every path is env-overridable so tests/ntfy.bats can run
# this end to end against a file:// release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${REPO_DIR}/config"

# shellcheck source=../lib/logging.sh
source "${REPO_DIR}/lib/logging.sh"
# shellcheck source=../lib/acm-phone-keys.sh
source "${REPO_DIR}/lib/acm-phone-keys.sh"

PINNED_NTFY_VERSION="$(sed -n 's/^NTFY_VERSION=//p' "${CONFIG_DIR}/versions.env")"
NTFY_VERSION="${NTFY_VERSION:-${PINNED_NTFY_VERSION}}"
NTFY_BASE_URL="${NTFY_BASE_URL:-https://github.com/binwiederhier/ntfy/releases/download/v${NTFY_VERSION}}"
NTFY_PORT=2586
NTFY_USER=ntfy
BIN_DIR="${NTFY_BIN_DIR:-/usr/local/bin}"
UNIT_DIR="${NTFY_UNIT_DIR:-/etc/systemd/system}"
ETC_DIR="${NTFY_CONFIG_DIR:-/etc/ntfy}"
# Passwords for the phones' ntfy apps, readable by the operator and nobody else.
CREDENTIALS_DIR="${NTFY_CREDENTIALS_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/acm/ntfy}"

# Root runs the privileged commands directly; anyone else goes through sudo.
SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

# Set when a file ntfy reads changed, so the service restarts once at the end.
RESTART_NEEDED=false

# Scratch directory for the download and the rendered config, which holds password
# hashes; removed on any exit, including a failed checksum.
WORK_DIR=""
cleanup() {
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR:?}"
    fi
}
trap cleanup EXIT

detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)
            log_error "Unsupported architecture '$(uname -m)': this installer handles linux-amd64 and linux-arm64 only"
            return 1
            ;;
    esac
}

installed_version() {
    [[ -x "${BIN_DIR}/ntfy" ]] || return 1
    "${BIN_DIR}/ntfy" --version 2>&1 | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

# Downloads the tarball and checksums.txt from the same pinned release and
# verifies the tarball against it. Refuses on a mismatch or a missing entry.
download_and_verify() {
    local tarball="$1"
    local checksum_line

    log_info "Downloading ${tarball}..."
    curl -fsSL -o "${WORK_DIR}/${tarball}" "${NTFY_BASE_URL}/${tarball}"
    curl -fsSL -o "${WORK_DIR}/checksums.txt" "${NTFY_BASE_URL}/checksums.txt"

    checksum_line="$(grep -E "[[:space:]]+${tarball}\$" "${WORK_DIR}/checksums.txt" || true)"
    if [[ -z "${checksum_line}" ]]; then
        log_error "No checksum for ${tarball} in checksums.txt - refusing to install"
        return 1
    fi

    if ! (cd "${WORK_DIR}" && echo "${checksum_line}" | sha256sum -c - >/dev/null 2>&1); then
        log_error "Checksum mismatch for ${tarball} - refusing to install"
        return 1
    fi
    log_ok "Checksum verified against checksums.txt"
}

create_user() {
    if getent passwd "${NTFY_USER}" >/dev/null 2>&1; then
        log_ok "User ${NTFY_USER} already exists"
        return 0
    fi
    ${SUDO} useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "${NTFY_USER}"
    log_ok "Created system user ${NTFY_USER}"
}

install_binary() {
    local arch current stem
    arch="$(detect_arch)"

    current="$(installed_version || true)"
    if [[ "${current}" == "${NTFY_VERSION}" ]]; then
        log_ok "ntfy ${NTFY_VERSION} already installed"
        return 0
    fi

    stem="ntfy_${NTFY_VERSION}_linux_${arch}"
    download_and_verify "${stem}.tar.gz"
    tar -xzf "${WORK_DIR}/${stem}.tar.gz" -C "${WORK_DIR}" "${stem}/ntfy"
    ${SUDO} mkdir -p "${BIN_DIR}"
    ${SUDO} install -m 0755 "${WORK_DIR}/${stem}/ntfy" "${BIN_DIR}/ntfy"
    RESTART_NEEDED=true
    log_ok "ntfy ${NTFY_VERSION} installed to ${BIN_DIR}/ntfy${current:+ (was ${current})}"
}

# Installs a file if its content differs, and marks the service for a restart.
# Returns 1 when the file was already current.
install_if_changed() {
    local mode="$1" src="$2" dest="$3"
    if ${SUDO} cmp -s "${src}" "${dest}"; then
        return 1
    fi
    ${SUDO} mkdir -p "$(dirname "${dest}")"
    ${SUDO} install -m "${mode}" "${src}" "${dest}"
    RESTART_NEEDED=true
}

# Creates a phone's password and its bcrypt hash on the first run. The hash is
# kept because bcrypt salts every call: rehashing would rewrite server.yml, and
# restart ntfy, on every run.
ensure_phone_credentials() {
    local phone="$1"
    local password_file="${CREDENTIALS_DIR}/${phone}.password"
    local hash_file="${CREDENTIALS_DIR}/${phone}.hash"

    if [[ ! -f "${password_file}" ]]; then
        (
            umask 077
            head -c 32 /dev/urandom | base64 | tr -d '/+=\n' >"${password_file}"
        )
        rm -f "${hash_file:?}"
        log_ok "ntfy password for ${phone} generated: ${password_file}"
    fi
    if [[ ! -s "${hash_file}" ]]; then
        local password
        password="$(cat "${password_file}")"
        # sudo: `ntfy user` reads server.yml, which this user cannot.
        (
            umask 077
            printf '%s\n%s\n' "${password}" "${password}" | ${SUDO} "${BIN_DIR}/ntfy" user hash 2>/dev/null >"${hash_file}"
        )
    fi
}

# A revoked phone keeps no credentials behind.
remove_stale_credentials() {
    local phones="$1" file phone
    for file in "${CREDENTIALS_DIR}"/*.password; do
        [[ -e "${file}" ]] || continue
        phone="$(basename "${file}" .password)"
        if ! grep -qxF -- "${phone}" <<<"${phones}"; then
            rm -f "${CREDENTIALS_DIR:?}/${phone:?}.password" "${CREDENTIALS_DIR:?}/${phone:?}.hash"
            log_info "Removed the ntfy credentials of revoked phone ${phone}"
        fi
    done
}

# Prints server.yml: the repo's settings, then the users and grants.
render_server_config() {
    local phones="$1" phone
    cat "${CONFIG_DIR}/ntfy-server.yml"
    echo
    if [[ -n "${phones}" ]]; then
        echo "auth-users:"
        while IFS= read -r phone; do
            echo "  - \"${phone}:$(cat "${CREDENTIALS_DIR}/${phone}.hash"):user\""
        done <<<"${phones}"
    fi
    echo "auth-access:"
    if [[ -n "${phones}" ]]; then
        while IFS= read -r phone; do
            echo "  - \"${phone}:acm-${phone}:read-write\""
            echo "  - \"${phone}:up*:read-only\""
        done <<<"${phones}"
    fi
    echo '  - "*:up*:write-only"'
}

install_server_config() {
    local keys_file phones phone
    keys_file="$(acm_phone_keys_file "${REPO_DIR}")"
    if [[ ! -f "${keys_file}" ]]; then
        log_error "Phone keys file not found: ${keys_file} - not touching ${ETC_DIR}/server.yml"
        return 1
    fi

    phones="$(acm_phone_names "${keys_file}")"
    mkdir -p "${CREDENTIALS_DIR}"
    chmod 700 "${CREDENTIALS_DIR}"
    if [[ -n "${phones}" ]]; then
        while IFS= read -r phone; do
            ensure_phone_credentials "${phone}"
        done <<<"${phones}"
    fi
    render_server_config "${phones}" >"${WORK_DIR}/server.yml"
    remove_stale_credentials "${phones}"

    # 0640: the file holds password hashes.
    if install_if_changed 0640 "${WORK_DIR}/server.yml" "${ETC_DIR}/server.yml"; then
        ${SUDO} chgrp "${NTFY_USER}" "${ETC_DIR}/server.yml"
        log_ok "${ETC_DIR}/server.yml updated"
    else
        log_ok "${ETC_DIR}/server.yml is up to date"
    fi
}

install_service() {
    local file
    for file in "${CONFIG_DIR}/ntfy-start.sh" "${CONFIG_DIR}/ntfy.service"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Not found: ${file} (run from a full checkout of the repo)"
            return 1
        fi
    done

    install_if_changed 0755 "${CONFIG_DIR}/ntfy-start.sh" "${BIN_DIR}/ntfy-start" || true
    if install_if_changed 0644 "${CONFIG_DIR}/ntfy.service" "${UNIT_DIR}/ntfy.service"; then
        ${SUDO} systemctl daemon-reload
    fi

    ${SUDO} systemctl enable ntfy.service
    if [[ "${RESTART_NEEDED}" == "true" ]]; then
        ${SUDO} systemctl restart ntfy.service
    else
        ${SUDO} systemctl start ntfy.service
    fi
    log_ok "ntfy.service enabled"
}

configure_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        log_warn "ufw not found - open ${NTFY_PORT}/tcp on tailscale0 ONLY, never publicly"
        return 0
    fi
    # tailscale0 only. There is no rule on the public interface, by design.
    ${SUDO} ufw allow in on tailscale0 to any port "${NTFY_PORT}" proto tcp comment 'ntfy (tailnet only)'
    log_ok "UFW: ${NTFY_PORT}/tcp allowed on tailscale0 only"
}

main() {
    echo ""
    echo "═══ Installing ntfy ${NTFY_VERSION} (tailnet-only) ═══"
    echo ""

    WORK_DIR="$(mktemp -d)"
    create_user
    install_binary
    install_server_config
    install_service
    configure_firewall

    echo ""
    log_ok "ntfy ready on <tailscale-ip>:${NTFY_PORT}"
    log_info "Tailscale ACL must allow the phones to reach this node on ${NTFY_PORT}"
    echo ""
}

main "$@"
