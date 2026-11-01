#!/usr/bin/env bash
# ABOUTME: Picks the interface(s) geoip-shell may filter on
# ABOUTME: Public uplink only - never "all" or tailscale0, whose sources have no country

# Prints the interface list for `geoip-shell configure -i`: GEOIP_IFACES when
# set, otherwise the default-route interface. geoip-shell's whitelist chain ends
# in a drop and tailnet sources (100.64.0.0/10, fd7a:115c:a1e0::/48) belong to
# no country, so covering tailscale0 (or "all") drops every inbound tailnet
# connection before UFW can accept it. Returns non-zero, printing nothing, when
# no safe interface is known: the caller skips geoblocking rather than widen it.
geoip_interfaces() {
    local ifaces="${GEOIP_IFACES:-}"
    if [[ -z "${ifaces}" ]]; then
        # "default via 10.0.0.1 dev eth0 proto dhcp ..." - first route wins
        ifaces="$(ip -o route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')" || true
    fi
    ifaces="${ifaces//,/ }"

    local iface
    for iface in ${ifaces}; do
        case "${iface}" in
            all | tailscale*) return 1 ;;
            *) ;;
        esac
    done
    [[ -n "${ifaces//[[:space:]]/}" ]] || return 1
    echo "${ifaces}"
}
