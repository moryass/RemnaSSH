#!/usr/bin/env bash

configure_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
        info "Настраиваю активный UFW"
        ufw allow 80/tcp comment 'RemnaSSH ACME' >/dev/null
        ufw allow 443/tcp comment 'RemnaSSH REALITY/XHTTP' >/dev/null
        ufw allow 443/udp comment 'RemnaSSH Hysteria2' >/dev/null
        ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'Remnawave Panel' >/dev/null
        ufw reload >/dev/null
        ok "UFW настроен"
        return
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        info "Настраиваю активный firewalld"
        firewall-cmd --permanent --add-service=http >/dev/null
        firewall-cmd --permanent --add-service=https >/dev/null
        firewall-cmd --permanent --add-port=443/udp >/dev/null
        firewall-cmd --permanent --add-rich-rule="rule family=\"$( [[ "$PANEL_IP" == *:* ]] && echo ipv6 || echo ipv4 )\" source address=\"$PANEL_IP\" port port=\"$NODE_PORT\" protocol=\"tcp\" accept" >/dev/null
        firewall-cmd --reload >/dev/null
        ok "firewalld настроен"
        return
    fi

    warn "Активный UFW/firewalld не найден. У провайдера откройте 80/tcp, 443/tcp, 443/udp."
    warn "$NODE_PORT/tcp разрешите только с адреса панели: $PANEL_IP"
}
