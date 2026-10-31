#!/usr/bin/env bash

set -Eeuo pipefail

readonly TARGET_PORT=443
readonly TCP_PORTS="__ALT_TCP_PORTS__"
readonly UDP_PORTS="__ALT_UDP_PORTS__"

ports() {
    local value="$1"
    [[ -n "$value" ]] && tr ',' '\n' <<<"$value"
}

rule_exists() {
    local binary="$1" protocol="$2" port="$3"
    "$binary" -w 5 -t nat -C PREROUTING ! -i lo -p "$protocol" --dport "$port" \
        -j REDIRECT --to-ports "$TARGET_PORT" >/dev/null 2>&1
}

add_rule() {
    local binary="$1" protocol="$2" port="$3"
    rule_exists "$binary" "$protocol" "$port" ||
        "$binary" -w 5 -t nat -A PREROUTING ! -i lo -p "$protocol" --dport "$port" \
            -j REDIRECT --to-ports "$TARGET_PORT"
}

delete_rule() {
    local binary="$1" protocol="$2" port="$3"
    while rule_exists "$binary" "$protocol" "$port"; do
        "$binary" -w 5 -t nat -D PREROUTING ! -i lo -p "$protocol" --dport "$port" \
            -j REDIRECT --to-ports "$TARGET_PORT"
    done
}

for_each_rule() {
    local action="$1" binary="$2" protocol port
    while IFS= read -r port; do
        [[ -n "$port" ]] && "$action" "$binary" tcp "$port"
    done < <(ports "$TCP_PORTS")
    while IFS= read -r port; do
        [[ -n "$port" ]] && "$action" "$binary" udp "$port"
    done < <(ports "$UDP_PORTS")
}

case "${1:-start}" in
    start)
        for_each_rule add_rule iptables
        if command -v ip6tables >/dev/null 2>&1 && ip6tables -w 5 -t nat -L >/dev/null 2>&1; then
            for_each_rule add_rule ip6tables
        fi
        ;;
    stop)
        for_each_rule delete_rule iptables
        if command -v ip6tables >/dev/null 2>&1 && ip6tables -w 5 -t nat -L >/dev/null 2>&1; then
            for_each_rule delete_rule ip6tables
        fi
        ;;
    status)
        while IFS= read -r port; do
            [[ -z "$port" ]] || rule_exists iptables tcp "$port"
        done < <(ports "$TCP_PORTS")
        while IFS= read -r port; do
            [[ -z "$port" ]] || rule_exists iptables udp "$port"
        done < <(ports "$UDP_PORTS")
        ;;
    *)
        printf 'Usage: %s {start|stop|status}\n' "$0" >&2
        exit 2
        ;;
esac
