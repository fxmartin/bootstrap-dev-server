#!/usr/bin/env bash
# ABOUTME: Reads the phone key file: which file applies, and which lines are safe to install
# ABOUTME: Shared by scripts/setup-acm-fleet.sh (authorized_keys) and scripts/install-ntfy.sh (ntfy users)

# A phone's key must do nothing on this server but run `acm bridge`, so a line
# is only accepted in the exact form `acm mobile key-line` prints. An extra
# option such as port-forwarding, a chained command or a missing `restrict`
# would widen what a lost phone can do. The name also becomes an ntfy user and
# the topic acm-<name>, so it is held to what ntfy allows for both, and 64-char
# topics leave it 60.
ACM_PHONE_LINE_RE='^command="((/[A-Za-z0-9._-]+)*/acm) bridge --allow (p1|p2|p3)",restrict (ecdsa-sha2-nistp256|ssh-ed25519) [A-Za-z0-9+/]+={0,2} ([A-Za-z0-9_-]{1,60})$'

# Returns 0 when the line is a safe key-line.
acm_phone_line_valid() {
    local line="$1" path name
    [[ "${line}" =~ ${ACM_PHONE_LINE_RE} ]] || return 1
    path="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[5]}"
    # sshd runs this path after every upgrade: garbage collection deletes a
    # store path, and `..` could hide one.
    [[ "${path}" != /nix/store/* && "${path}" != *..* ]] || return 1
    # ntfy reads `everyone` as the anonymous user.
    [[ "${name,,}" != "everyone" ]]
}

# Prints the key file in force: ACM_PHONE_KEYS_FILE, else the secret path on the
# server, else the file in this repository.
acm_phone_keys_file() {
    local repo_dir="$1"
    local secret="${XDG_CONFIG_HOME:-${HOME}/.config}/acm/phone-keys.pub"
    if [[ -n "${ACM_PHONE_KEYS_FILE:-}" ]]; then
        echo "${ACM_PHONE_KEYS_FILE}"
    elif [[ -f "${secret}" ]]; then
        echo "${secret}"
    else
        echo "${repo_dir}/config/acm-phone-keys.pub"
    fi
}

# Prints each valid phone's name once, sorted.
acm_phone_names() {
    local file="$1" line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if acm_phone_line_valid "${line}"; then
            echo "${line##* }"
        fi
    done <"${file}" | sort -u
}
