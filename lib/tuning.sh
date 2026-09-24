#!/usr/bin/env bash

configure_network_tuning() {
    local config_file="/etc/sysctl.d/99-remnassh.conf"
    local tmp_file available

    info "Настраиваю сетевые параметры"
    command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null || true
    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    tmp_file="$(mktemp /etc/sysctl.d/.99-remnassh.conf.XXXXXX)"

    {
        printf '%s\n' '# Managed by RemnaSSH'
        printf '%s\n' 'net.core.default_qdisc = fq'
        if [[ " $available " == *" bbr "* ]]; then
            printf '%s\n' 'net.ipv4.tcp_congestion_control = bbr'
        fi
        printf '%s\n' 'net.core.rmem_max = 16777216'
        printf '%s\n' 'net.core.wmem_max = 16777216'
    } > "$tmp_file"

    chmod 0644 "$tmp_file"
    mv -f "$tmp_file" "$config_file"
    if ! sysctl -p "$config_file" >/dev/null; then
        warn "Не удалось применить часть сетевых параметров; установка продолжена"
        return 0
    fi

    if [[ " $available " == *" bbr "* ]]; then
        ok "BBR + fq включены; UDP-буферы увеличены до 16 MiB"
    else
        warn "BBR недоступен в текущем ядре; применены fq и UDP-буферы"
    fi
}
