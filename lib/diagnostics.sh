#!/usr/bin/env bash

state_or_fail() {
    require_root
    load_state
    require_command docker
}

status_report() {
    state_or_fail
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"
    docker compose ps
    printf '\n'
    if [[ -f "$INSTALL_DIR/connection-settings.txt" ]]; then
        cat "$INSTALL_DIR/connection-settings.txt"
    fi
}

check_item() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ok "$label"
        return 0
    fi
    warn "$label — ошибка"
    return 1
}

container_running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]
}

xray_running() {
    docker top remnanode 2>/dev/null | grep -Eq '(^|[[:space:]/])(rw-core|xray)([[:space:]]|$)'
}

certificate_valid() {
    openssl x509 -in "$(certificate_host_path)" -checkend 604800 -noout
}

time_is_synchronized() {
    command -v timedatectl >/dev/null 2>&1 || return 0
    [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == true ]]
}

network_tuning_active() {
    [[ "$(sysctl -n net.core.rmem_max 2>/dev/null)" -ge 16777216 ]] &&
        [[ "$(sysctl -n net.core.wmem_max 2>/dev/null)" -ge 16777216 ]]
}

diagnostics() {
    state_or_fail
    local failed=0
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"

    check_item "Docker daemon" docker info || failed=1
    check_item "Compose config" docker compose config --quiet || failed=1
    check_item "Контейнер Caddy" container_running remnassh-caddy || failed=1
    check_item "Контейнер Remnawave Node" container_running remnanode || failed=1
    check_item "Xray Core запущен" xray_running || failed=1
    check_item "HTTPS decoy через self-steal" curl -fsS --max-time 15 "https://$NODE_DOMAIN/" || failed=1
    if curl --version 2>/dev/null | grep -q 'HTTP2'; then
        check_item "HTTP/2 на Caddy" bash -c "curl -fsSI --http2 --max-time 15 https://'$NODE_DOMAIN'/ | grep -qE '^HTTP/2'" || failed=1
    else
        warn "Локальный curl собран без HTTP/2; проверка пропущена"
    fi
    check_item "Сертификат Hysteria2 доступен" test -s "$(certificate_host_path)" || failed=1
    check_item "Сертификат действителен ещё минимум 7 дней" certificate_valid || failed=1
    check_item "Системное время синхронизировано" time_is_synchronized || failed=1
    check_item "UDP-буферы настроены" network_tuning_active || failed=1

    if port_is_listening tcp 443; then ok "443/tcp слушается"; else warn "Xray не слушает 443/tcp"; failed=1; fi
    if port_is_listening udp 443; then ok "443/udp слушается"; else warn "Xray не слушает 443/udp"; failed=1; fi
    if port_is_listening tcp "$NODE_PORT"; then ok "$NODE_PORT/tcp (Node API) слушается"; else warn "$NODE_PORT/tcp не слушается"; failed=1; fi
    if [[ -S /dev/shm/remnassh-xhttp.sock ]]; then ok "XHTTP Unix socket создан"; else warn "XHTTP Unix socket не создан"; failed=1; fi

    if [[ "$failed" -ne 0 ]]; then
        printf '\nПоследние логи:\n'
        docker compose logs --tail=100 caddy remnanode || true
        return 1
    fi
    ok "Все проверки пройдены"
}
