#!/usr/bin/env bash
# ABOUTME: Makes this server's acmd the fleet aggregator for acm's Android app (acm Epic-17)
# ABOUTME: Writes [[peers]], generates the peer SSH key and installs the restricted phone keys
#
# Idempotent: nothing is rewritten unless its content drifted, and everything
# outside the marker blocks is left alone. Run by the bootstrap. It reads the
# clone and does not update it, so to revoke a phone follow "Revoking a phone" in
# the README. Exits non-zero when a peer or phone line was refused, having applied
# the valid ones, so one typo cannot hold a revocation back, and when a marker
# block could not be updated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# shellcheck source=../lib/logging.sh
source "${REPO_DIR}/lib/logging.sh"
# shellcheck source=../lib/rc-block.sh
source "${REPO_DIR}/lib/rc-block.sh"
# shellcheck source=../lib/acm-phone-keys.sh
source "${REPO_DIR}/lib/acm-phone-keys.sh"

PEERS_FILE="${ACM_PEERS_FILE:-${REPO_DIR}/config/acm-peers.toml}"
ACM_CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/acm/config.toml"
SSH_DIR="${HOME}/.ssh"
PEER_KEY="${SSH_DIR}/id_acm_peers"
SSH_CONFIG="${SSH_DIR}/config"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

PEERS_BEGIN="# >>> bootstrap-dev-server acm peers >>>"
PEERS_END="# <<< bootstrap-dev-server acm peers <<<"
SSH_BEGIN="# >>> bootstrap-dev-server acm peer hosts >>>"
SSH_END="# <<< bootstrap-dev-server acm peer hosts <<<"
PHONES_BEGIN="# >>> bootstrap-dev-server acm phones >>>"
PHONES_END="# <<< bootstrap-dev-server acm phones <<<"

# Set when a peer, a phone line or a damaged block is refused: the run finishes,
# then exits non-zero.
REFUSED=false

# Prints stdin without the marker block.
without_block() {
    local begin="$1" end="$2"
    awk -v begin="${begin}" -v end="${end}" '$0 == begin { skip = 1 } !skip { print } $0 == end { skip = 0 }'
}

# write_rc_block with a refused block counted against the run, because logging it
# as "up to date" would hide a phone revocation that never applied. Same return
# codes; stdin is the block.
converge_block() {
    local status=0
    write_rc_block "$@" || status=$?
    if [[ "${status}" -eq 2 ]]; then
        log_error "$1 was not updated: restore the '$3' line, then run this again"
        REFUSED=true
    fi
    return "${status}"
}

# Prints "label|ssh|socket" for each [[peers]] table on stdin. Only the keys acm
# reads are kept, so comments and stray keys do not travel into config.toml.
peer_rows() {
    awk '
        function flush() {
            if (in_peer) { print label "|" dest "|" socket }
            label = ""; dest = ""; socket = ""
        }
        /^[[:space:]]*\[/ { flush(); in_peer = ($0 ~ /^[[:space:]]*\[\[peers\]\]/); next }
        in_peer {
            key = $0
            sub(/^[[:space:]]*/, "", key)
            sub(/[[:space:]]*=.*/, "", key)
            split($0, quoted, "\"")
            if (key == "label") { label = quoted[2] }
            if (key == "ssh") { dest = quoted[2] }
            if (key == "socket") { socket = quoted[2] }
        }
        END { flush() }
    '
}

# These values reach ~/.ssh/config and the ssh command line: a leading "-" would
# be read as an option, and a space or newline as another ssh config keyword.
peer_row_valid() {
    local label="$1" dest="$2" socket="$3"
    [[ "${label}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
    [[ "${dest}" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*@)?[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
    [[ -z "${socket}" || "${socket}" =~ ^(/|~/)[A-Za-z0-9._/-]*$ ]]
}

# acmd opens one ssh forward per peer with BatchMode, so `ssh <host>` must find
# the peer key by itself and must not stop at an unknown host key. accept-new
# still refuses a host key that changed.
write_peer_ssh_config() {
    local hosts="$1"
    [[ -n "${hosts}" ]] || return 0
    local block
    block="${SSH_BEGIN}
Host ${hosts}
    IdentityFile ~/.ssh/id_acm_peers
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
${SSH_END}"
    converge_block "${SSH_CONFIG}" "${SSH_BEGIN}" "${SSH_END}" <<<"${block}" || true
    chmod 600 "${SSH_CONFIG}"
}

# acmd reads its peers at start, so a changed list needs a restart. A stopped
# acmd stays stopped: the service setup decides when it runs.
restart_acmd() {
    if systemctl --user is-active --quiet acmd.service 2>/dev/null; then
        systemctl --user restart acmd.service || log_warn "acmd restart failed - restart it by hand so it reads the new peers"
        log_info "acmd restarted onto the new peers"
    fi
}

setup_peers() {
    if [[ ! -f "${PEERS_FILE}" ]]; then
        log_error "Peers file not found: ${PEERS_FILE}"
        return 1
    fi

    mkdir -p "$(dirname "${ACM_CONFIG}")"
    local taken="" label dest socket hosts=""
    if [[ -f "${ACM_CONFIG}" ]]; then
        taken="$(without_block "${PEERS_BEGIN}" "${PEERS_END}" <"${ACM_CONFIG}" | peer_rows | cut -d'|' -f1)"
    fi

    local block="${PEERS_BEGIN}
# Generated from config/acm-peers.toml by scripts/setup-acm-fleet.sh. Add your own peers outside this block."
    while IFS='|' read -r label dest socket; do
        if ! peer_row_valid "${label}" "${dest}" "${socket}"; then
            log_error "Refusing peer '${label}' in ${PEERS_FILE}: it needs a valid label and ssh host, and socket must be absolute or start with ~/"
            REFUSED=true
            continue
        fi
        hosts="${hosts:+${hosts} }${dest##*@}"
        if grep -qxF -- "${label}" <<<"${taken}"; then
            log_info "Peer ${label} is already in ${ACM_CONFIG} - keeping that entry"
            continue
        fi
        block+="

[[peers]]
label = \"${label}\"
ssh = \"${dest}\""
        if [[ -n "${socket}" ]]; then
            block+="
socket = \"${socket}\""
        fi
    done < <(peer_rows <"${PEERS_FILE}")
    block+=$'\n'"${PEERS_END}"

    local result=0
    converge_block "${ACM_CONFIG}" "${PEERS_BEGIN}" "${PEERS_END}" <<<"${block}" || result=$?
    case "${result}" in
    0)
        log_ok "Peers written to ${ACM_CONFIG}"
        restart_acmd
        ;;
    1) log_ok "Peers in ${ACM_CONFIG} are up to date" ;;
    esac

    write_peer_ssh_config "${hosts}"
}

# No passphrase: acmd uses this key unattended, from a user service.
setup_peer_key() {
    if [[ ! -f "${PEER_KEY}" ]]; then
        ssh-keygen -q -t ed25519 -N "" -C "acm-peers@$(uname -n)" -f "${PEER_KEY}"
        log_ok "Generated the peer SSH key ${PEER_KEY}"
    elif [[ ! -f "${PEER_KEY}.pub" ]]; then
        ssh-keygen -y -P "" -f "${PEER_KEY}" >"${PEER_KEY}.pub"
    fi

    log_info "Add this key to each peer (nix-install for the Macs, the XPS's authorized_keys):"
    cat "${PEER_KEY}.pub"
}

# Installs the valid lines. A key that is also authorized elsewhere in the file
# keeps working unrestricted, which is reported rather than edited: lines outside
# the block are the operator's.
setup_phone_keys() {
    local keys_file line number=0 count=0 blob outside acm_path
    keys_file="$(acm_phone_keys_file "${REPO_DIR}")"
    if [[ ! -f "${keys_file}" ]]; then
        log_error "Phone keys file not found: ${keys_file} - leaving authorized_keys as it is"
        return 1
    fi

    # touch only when missing: on an existing file it would bump the mtime of a
    # file this script may have no reason to change.
    [[ -e "${AUTHORIZED_KEYS}" ]] || touch "${AUTHORIZED_KEYS}"
    chmod 600 "${AUTHORIZED_KEYS}"
    outside="$(without_block "${PHONES_BEGIN}" "${PHONES_END}" <"${AUTHORIZED_KEYS}")"

    local block="${PHONES_BEGIN}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        number=$((number + 1))
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        # Named by number only: the line may be something that must not be logged.
        if ! acm_phone_line_valid "${line}"; then
            log_error "Refusing line ${number} of ${keys_file}: it must be exactly what 'acm mobile key-line' prints, with a profile path to acm, never /nix/store"
            REFUSED=true
            continue
        fi
        blob="$(awk '{ print $(NF - 1) }' <<<"${line}")"
        if grep -qF -- "${blob}" <<<"${outside}"; then
            log_error "The key on line ${number} of ${keys_file} is also in ${AUTHORIZED_KEYS} outside the phones block, where nothing restricts it - remove that line"
            REFUSED=true
        fi
        acm_path="${line#command=\"}"
        acm_path="${acm_path%% *}"
        if [[ ! -x "${acm_path}" ]]; then
            log_warn "Line ${number} of ${keys_file} runs ${acm_path}, which is not executable here"
        fi
        block+=$'\n'"${line}"
        count=$((count + 1))
    done <"${keys_file}"
    block+=$'\n'"${PHONES_END}"

    # Nothing enrolled and nothing to revoke: stay out of the file entirely.
    if [[ "${count}" -eq 0 ]] && ! grep -qxF -- "${PHONES_BEGIN}" "${AUTHORIZED_KEYS}"; then
        log_info "No phone keys to install"
        return 0
    fi

    local result=0
    converge_block "${AUTHORIZED_KEYS}" "${PHONES_BEGIN}" "${PHONES_END}" <<<"${block}" || result=$?
    case "${result}" in
    0) log_ok "authorized_keys: ${count} phone key(s) installed from ${keys_file}" ;;
    1) log_ok "authorized_keys: ${count} phone key(s) up to date" ;;
    esac
}

main() {
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"

    local status=0
    setup_peers || status=1
    setup_peer_key
    setup_phone_keys || status=1

    if [[ "${status}" -ne 0 || "${REFUSED}" == "true" ]]; then
        return 1
    fi
}

main "$@"
