#!/usr/bin/env bash

configure_port_aliases() {
    local script_template="$INSTALL_DIR/tool/templates/remnassh-port-aliases.sh.tpl"
    local unit_template="$INSTALL_DIR/tool/templates/remnassh-port-aliases.service.tpl"
    local script_target="/usr/local/sbin/remnassh-port-aliases"
    local unit_target="/etc/systemd/system/remnassh-port-aliases.service"

    [[ -f "$script_template" ]] || script_template="$SCRIPT_DIR/templates/remnassh-port-aliases.sh.tpl"
    [[ -f "$unit_template" ]] || unit_template="$SCRIPT_DIR/templates/remnassh-port-aliases.service.tpl"

    if systemctl is-active --quiet remnassh-port-aliases.service 2>/dev/null; then
        systemctl stop remnassh-port-aliases.service
    fi

    sed \
        -e "s|__ALT_TCP_PORTS__|$ALT_TCP_PORTS|g" \
        -e "s|__ALT_UDP_PORTS__|$ALT_UDP_PORTS|g" \
        "$script_template" > "$script_target"
    install -m 0644 "$unit_template" "$unit_target"
    chmod 0755 "$script_target"

    systemctl daemon-reload
    systemctl enable --now remnassh-port-aliases.service >/dev/null
    "$script_target" status
    ok "Резервные порты активны: TCP ${ALT_TCP_PORTS:-нет}; UDP ${ALT_UDP_PORTS:-нет}"
}

port_aliases_active() {
    [[ -z "${ALT_TCP_PORTS:-}" && -z "${ALT_UDP_PORTS:-}" ]] && return 0
    systemctl is-active --quiet remnassh-port-aliases.service &&
        /usr/local/sbin/remnassh-port-aliases status
}
