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

diagnostics() {
    state_or_fail
    local failed=0
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"

    check_item "Docker daemon" docker info || failed=1
    check_item "Compose config" docker compose config --quiet || failed=1
    check_item "Контейнер Caddy" container_running remnassh-caddy || failed=1
    check_item "Контейнер Remnawave Node" container_running remnanode || failed=1
    check_item "HTTPS decoy через self-steal" curl -fsS --max-time 15 "https://$NODE_DOMAIN/" || failed=1
    check_item "HTTP/2 на Caddy" bash -c "curl -fsSI --http2 --max-time 15 https://'$NODE_DOMAIN'/ | grep -qE '^HTTP/2'" || failed=1
    check_item "Сертификат Hysteria2 доступен" test -s "$(certificate_host_path)" || failed=1

    if port_is_listening tcp 443; then ok "443/tcp слушается"; else warn "443/tcp ещё не слушается — назначьте профиль ноде"; failed=1; fi
    if port_is_listening udp 443; then ok "443/udp слушается"; else warn "443/udp ещё не слушается — назначьте профиль ноде"; failed=1; fi
    if port_is_listening tcp "$NODE_PORT"; then ok "$NODE_PORT/tcp (Node API) слушается"; else warn "$NODE_PORT/tcp не слушается"; failed=1; fi
    if [[ -S /dev/shm/remnassh-xhttp.sock ]]; then ok "XHTTP Unix socket создан"; else warn "XHTTP socket ещё не создан — назначьте профиль ноде"; failed=1; fi

    if [[ "$failed" -ne 0 ]]; then
        printf '\nПоследние логи:\n'
        docker compose logs --tail=40 caddy remnanode || true
        return 1
    fi
    ok "Все проверки пройдены"
}
