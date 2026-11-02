#!/usr/bin/env bash

probe_stack() {
    require_root
    load_state
    require_command docker
    require_command curl

    local config="${1:-}" config_path container image code=000
    local probe_url="${REMNASSH_PROBE_URL:-https://www.gstatic.com/generate_204}"
    [[ -n "$config" ]] || die "Укажите клиентский JSON: sudo remnassh probe /path/client.json"
    [[ -f "$config" ]] || die "Клиентский конфиг не найден: $config"
    config_path="$(readlink -f -- "$config")"
    image="${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}"
    container="remnassh-probe-$$"

    info "Проверяю клиентский конфиг Xray"
    docker run --rm --network host --entrypoint /usr/local/bin/xray \
        -v "$config_path:/etc/xray/config.json:ro" \
        "$image" run -test -c /etc/xray/config.json >/dev/null

    if port_is_listening tcp 10808; then
        die "Порт 10808 уже занят. Остановите локальный SOCKS-клиент и повторите проверку."
    fi

    info "Запускаю временный клиент и проверяю выход в интернет через VPN"
    docker run -d --name "$container" --network host --entrypoint /usr/local/bin/xray \
        -v "$config_path:/etc/xray/config.json:ro" \
        "$image" run -c /etc/xray/config.json >/dev/null

    for _ in {1..15}; do
        if port_is_listening tcp 10808; then
            break
        fi
        if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true ]]; then
            break
        fi
        sleep 1
    done

    if port_is_listening tcp 10808; then
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 \
            --proxy socks5h://127.0.0.1:10808 "$probe_url" || true)"
    fi

    if [[ "$code" == 200 || "$code" == 204 ]]; then
        docker rm -f "$container" >/dev/null 2>&1 || true
        ok "VPN-туннель работает: $probe_url вернул HTTP $code"
        return 0
    fi

    warn "Проверка через VPN не пройдена (HTTP $code)"
    docker logs --tail=120 "$container" 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
    return 1
}
