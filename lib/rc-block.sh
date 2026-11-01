#!/usr/bin/env bash
# ABOUTME: Converges a marker-delimited block in a shell rc file to the text on stdin
# ABOUTME: Rewrites only on content drift, keeping everything outside the markers

# A marker means "this block is ours to keep current", not "already done":
# treating it as done froze the first-ever dev-update on provisioned servers.
#
# Same contract as install_systemd_unit: returns 0 when the file changed, 1 when
# it was already current. Beyond that contract, 2 when it was refused because the
# block has no closing marker, so a caller can tell that from "current". stdin is
# the whole block, markers included. The block keeps its position, and the file
# is written in place so a symlinked rc and its mode survive. The previous content
# goes to <rc-file>.backup, because a block on a live box may hold a hand edit.
# Callers provide log_warn.
#
# Usage: write_rc_block <rc-file> <begin-marker> <end-marker> <<<"${block}"
write_rc_block() {
    local rc_file="$1"
    local begin="$2"
    local end="$3"
    local block first last merged
    block="$(mktemp)"
    cat >"${block}"

    first="$(grep -nxF -- "${begin}" "${rc_file}" 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
    last="$(grep -nxF -- "${end}" "${rc_file}" 2>/dev/null | tail -n 1 | cut -d: -f1 || true)"

    if [[ -z "${first}" ]]; then
        if [[ -s "${rc_file}" ]]; then
            echo >>"${rc_file}"
        fi
        cat "${block}" >>"${rc_file}"
        rm -f "${block}"
        return 0
    fi

    # Replacing up to a marker that is not there would eat the rest of the file.
    if [[ -z "${last}" || "${last}" -lt "${first}" ]]; then
        log_warn "${rc_file}: '${begin}' has no closing marker - leaving the file as it is"
        rm -f "${block}"
        return 2
    fi

    if sed -n "${first},${last}p" "${rc_file}" | cmp -s - "${block}"; then
        rm -f "${block}"
        return 1
    fi

    merged="$(mktemp)"
    {
        head -n "$((first - 1))" "${rc_file}"
        cat "${block}"
        tail -n "+$((last + 1))" "${rc_file}"
    } >"${merged}"
    cp -p "${rc_file}" "${rc_file}.backup"
    cat "${merged}" >"${rc_file}"
    rm -f "${block}" "${merged}"
    return 0
}
