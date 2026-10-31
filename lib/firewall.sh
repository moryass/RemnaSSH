#!/usr/bin/env bash

detect_ssh_ports() {
    local connection_port=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        connection_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
        validate_port "$connection_port" && printf '%s\n' "$connection_port"
    fi

    if command -v sshd >/dev/null 2>&1; then
        sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' || true
    fi
}

validate_alias_ports_against_ssh() {
    local alias_port ssh_port
    local -a ssh_ports=()
    mapfile -t ssh_ports < <(detect_ssh_ports | awk '!seen[$0]++')
    while IFS= read -r alias_port; do
        [[ -n "$alias_port" ]] || continue
        for ssh_port in "${ssh_ports[@]}"; do
            [[ "$alias_port" != "$ssh_port" ]] || die "Резервный порт $alias_port совпадает с SSH-портом"
        done
    done < <(printf '%s,%s\n' "$ALT_TCP_PORTS" "$ALT_UDP_PORTS" | tr ',' '\n')
}

configure_ufw() {
    local ssh_port alias_port
    local -a ssh_ports=()

    mapfile -t ssh_ports < <(detect_ssh_ports | awk '!seen[$0]++')
    ((${#ssh_ports[@]})) || ssh_ports=(22)

    info "Настраиваю UFW"
    for ssh_port in "${ssh_ports[@]}"; do
        ufw allow "$ssh_port/tcp" comment 'SSH' >/dev/null
    done

    ufw allow 80/tcp comment 'RemnaSSH ACME' >/dev/null
    ufw allow 443/tcp comment 'RemnaSSH REALITY/XHTTP/gRPC' >/dev/null
    ufw allow 443/udp comment 'RemnaSSH Hysteria2' >/dev/null
    while IFS= read -r alias_port; do
        [[ -n "$alias_port" ]] && ufw allow "$alias_port/tcp" comment 'RemnaSSH TCP alias' >/dev/null
    done < <(tr ',' '\n' <<<"$ALT_TCP_PORTS")
    while IFS= read -r alias_port; do
        [[ -n "$alias_port" ]] && ufw allow "$alias_port/udp" comment 'RemnaSSH UDP alias' >/dev/null
    done < <(tr ',' '\n' <<<"$ALT_UDP_PORTS")
    ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'Remnawave Panel' >/dev/null
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw --force enable >/dev/null
    ufw reload >/dev/null

    ok "UFW включён: SSH ${ssh_ports[*]}/tcp, 80/tcp, 443/tcp, 443/udp, резервные TCP ${ALT_TCP_PORTS:-нет}, UDP ${ALT_UDP_PORTS:-нет}; $NODE_PORT/tcp только с $PANEL_IP"
}

configure_firewall() {
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        local alias_port
        info "Настраиваю активный firewalld"
        firewall-cmd --permanent --add-service=http >/dev/null
        firewall-cmd --permanent --add-service=https >/dev/null
        firewall-cmd --permanent --add-port=443/udp >/dev/null
        while IFS= read -r alias_port; do
            [[ -n "$alias_port" ]] && firewall-cmd --permanent --add-port="$alias_port/tcp" >/dev/null
        done < <(tr ',' '\n' <<<"$ALT_TCP_PORTS")
        while IFS= read -r alias_port; do
            [[ -n "$alias_port" ]] && firewall-cmd --permanent --add-port="$alias_port/udp" >/dev/null
        done < <(tr ',' '\n' <<<"$ALT_UDP_PORTS")
        firewall-cmd --permanent --add-rich-rule="rule family=\"$( [[ "$PANEL_IP" == *:* ]] && echo ipv6 || echo ipv4 )\" source address=\"$PANEL_IP\" port port=\"$NODE_PORT\" protocol=\"tcp\" accept" >/dev/null
        firewall-cmd --reload >/dev/null
        ok "firewalld настроен"
        warn "Если у провайдера есть внешний firewall, откройте 80/tcp, 443/tcp, 443/udp, TCP ${ALT_TCP_PORTS:-нет} и UDP ${ALT_UDP_PORTS:-нет}."
        return
    fi

    command -v ufw >/dev/null 2>&1 || die "UFW не установлен"
    configure_ufw
    warn "Если у провайдера есть внешний firewall, откройте 80/tcp, 443/tcp, 443/udp, TCP ${ALT_TCP_PORTS:-нет} и UDP ${ALT_UDP_PORTS:-нет}."
}
