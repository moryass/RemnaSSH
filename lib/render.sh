#!/usr/bin/env bash

prepare_directories() {
    install -d -m 0700 "$INSTALL_DIR" "$INSTALL_DIR/tool" "$INSTALL_DIR/caddy-data" "$INSTALL_DIR/caddy-config"
    install -d -m 0755 "$INSTALL_DIR/www"
    : > "$MARKER_FILE"
    chmod 600 "$MARKER_FILE"
}

install_runtime_files() {
    local target="$INSTALL_DIR/tool"
    if [[ "$(readlink -f "$SCRIPT_DIR")" != "$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")" ]]; then
        install -m 0755 "$SCRIPT_DIR/install.sh" "$target/install.sh"
        install -d -m 0755 "$target/lib" "$target/templates"
        install -m 0644 "$SCRIPT_DIR"/lib/*.sh "$target/lib/"
        install -m 0644 "$SCRIPT_DIR"/templates/* "$target/templates/"
    fi
}

generate_reality_keys() {
    local output
    info "Генерирую ключи REALITY"
    docker pull "${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}" >/dev/null
    output="$(docker run --rm --entrypoint /usr/local/bin/xray \
        "${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}" x25519)"
    REALITY_PRIVATE_KEY="$(awk -F': ' '/PrivateKey/ {print $2; exit}' <<<"$output")"
    REALITY_PUBLIC_KEY="$(awk -F': ' '/PublicKey|Password/ {print $2; exit}' <<<"$output")"
    [[ -n "$REALITY_PRIVATE_KEY" && -n "$REALITY_PUBLIC_KEY" ]] || die "Не удалось разобрать ключи x25519"
}

write_secret() {
    [[ "$NODE_SECRET" != *"'"* ]] || die "Secret Key содержит одинарную кавычку и не может быть записан в node.env"
    printf '%s\n' "$NODE_SECRET" > "$INSTALL_DIR/secret-key"
    chmod 600 "$INSTALL_DIR/secret-key"
    {
        printf 'NODE_PORT=%s\n' "$NODE_PORT"
        printf "SECRET_KEY='%s'\n" "$NODE_SECRET"
    } > "$INSTALL_DIR/node.env"
    chmod 600 "$INSTALL_DIR/node.env"
}

render_stack() {
    local template_dir="$INSTALL_DIR/tool/templates"
    sed \
        -e "s|__DOMAIN__|$NODE_DOMAIN|g" \
        -e "s|__EMAIL__|$ACME_EMAIL|g" \
        "$template_dir/index.html.tpl" > "$INSTALL_DIR/www/index.html"

    cp "$template_dir/Caddyfile.tpl" "$INSTALL_DIR/Caddyfile.final"
    cp "$template_dir/Caddyfile.bootstrap.tpl" "$INSTALL_DIR/Caddyfile.bootstrap"
    cp "$INSTALL_DIR/Caddyfile.final" "$INSTALL_DIR/Caddyfile"

    sed \
        -e "s|__CADDY_IMAGE__|${CADDY_IMAGE:-$CADDY_IMAGE_DEFAULT}|g" \
        -e "s|__REMNANODE_IMAGE__|${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}|g" \
        -e "s|__NODE_PORT__|$NODE_PORT|g" \
        "$template_dir/docker-compose.yml.tpl" > "$INSTALL_DIR/docker-compose.yml"

    {
        printf 'NODE_DOMAIN=%s\n' "$NODE_DOMAIN"
        printf 'ACME_EMAIL=%s\n' "$ACME_EMAIL"
        printf 'CADDY_INTERNAL_PORT=%s\n' "$CADDY_INTERNAL_PORT"
        printf 'XHTTP_PATH=%s\n' "$XHTTP_PATH"
    } > "$INSTALL_DIR/.env"

    chmod 600 "$INSTALL_DIR/.env" "$INSTALL_DIR/docker-compose.yml"
    chmod 644 "$INSTALL_DIR/Caddyfile" "$INSTALL_DIR/Caddyfile.final" "$INSTALL_DIR/Caddyfile.bootstrap" "$INSTALL_DIR/www/index.html"
    render_profile
}

render_profile() {
    local source_template="$INSTALL_DIR/tool/templates/full-profile.json.tpl"
    [[ -f "$source_template" ]] || source_template="$SCRIPT_DIR/templates/full-profile.json.tpl"

    sed \
        -e "s|__DOMAIN__|$NODE_DOMAIN|g" \
        -e "s|__CADDY_INTERNAL_PORT__|$CADDY_INTERNAL_PORT|g" \
        -e "s|__XHTTP_PATH__|$XHTTP_PATH|g" \
        -e "s|__XHTTP_MODE__|$XHTTP_MODE|g" \
        -e "s|__REALITY_PRIVATE_KEY__|$REALITY_PRIVATE_KEY|g" \
        -e "s|__REALITY_SHORT_ID__|$REALITY_SHORT_ID|g" \
        "$source_template" > "$PROFILE_FILE"
    chmod 600 "$PROFILE_FILE"
}

validate_rendered_files() {
    jq -e . "$PROFILE_FILE" >/dev/null || die "Сгенерирован некорректный JSON"
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"
    docker compose config --quiet
    docker compose run --rm --no-deps --entrypoint caddy caddy \
        validate --config /etc/caddy/Caddyfile --adapter caddyfile
    docker run --rm --entrypoint caddy --env-file "$INSTALL_DIR/.env" \
        -v "$INSTALL_DIR/Caddyfile.bootstrap:/etc/caddy/Caddyfile:ro" \
        "${CADDY_IMAGE:-$CADDY_IMAGE_DEFAULT}" \
        validate --config /etc/caddy/Caddyfile --adapter caddyfile
    ok "Compose, Caddyfile и JSON синтаксически корректны"
}

start_stack() {
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"
    docker compose pull

    if [[ ! -s "$(certificate_host_path)" ]]; then
        info "Временно запускаю Caddy на 443/tcp для первого выпуска сертификата"
        cp "$INSTALL_DIR/Caddyfile.bootstrap" "$INSTALL_DIR/Caddyfile"
        docker compose up -d caddy
        wait_for_certificate
    fi

    cp "$INSTALL_DIR/Caddyfile.final" "$INSTALL_DIR/Caddyfile"
    docker compose up -d --force-recreate caddy
    docker compose up -d --remove-orphans remnanode

    local _ health
    info "Проверяю Caddy на внутреннем HTTPS-порту"
    for _ in $(seq 1 24); do
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' remnassh-caddy 2>/dev/null || true)"
        [[ "$health" == healthy ]] && break
        sleep 5
    done
    if [[ "$health" != healthy ]]; then
        docker inspect -f '{{range .State.Health.Log}}{{println .Output}}{{end}}' remnassh-caddy >&2 2>/dev/null || true
        docker compose logs --tail=80 caddy >&2 || true
        die "Caddy не прошёл healthcheck после переключения на self-steal"
    fi
    ok "Caddy и Remnawave Node запущены"
}

certificate_host_path() {
    printf '%s/caddy-data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/%s/%s.crt' \
        "$INSTALL_DIR" "$NODE_DOMAIN" "$NODE_DOMAIN"
}

wait_for_certificate() {
    local cert_path _
    cert_path="$(certificate_host_path)"
    info "Ожидаю сертификат Let's Encrypt (до 3 минут)"
    for _ in $(seq 1 60); do
        if [[ -s "$cert_path" ]]; then
            ok "Сертификат получен"
            return
        fi
        sleep 3
    done
    docker compose -f "$INSTALL_DIR/docker-compose.yml" logs --tail=100 caddy >&2 || true
    die "Caddy не получил сертификат. Проверьте DNS, доступность 80/tcp и логи Caddy."
}

validate_xray_profile() {
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"
    docker run --rm \
        --entrypoint /usr/local/bin/xray \
        -v "$PROFILE_FILE:/etc/xray/config.json:ro" \
        -v "$INSTALL_DIR/caddy-data:/data:ro" \
        "${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}" \
        run -test -config /etc/xray/config.json
    ok "Профиль принят Xray-core"
}

validate_xray_profile_if_certificate_exists() {
    if [[ -s "$(certificate_host_path)" ]]; then
        validate_xray_profile
    else
        warn "Сертификат ещё не создан; выполнена только JSON-проверка"
        jq -e . "$PROFILE_FILE" >/dev/null
    fi
}

install_command() {
    ln -sfn "$INSTALL_DIR/tool/install.sh" /usr/local/sbin/remnassh
}

print_result() {
    cat > "$INSTALL_DIR/connection-settings.txt" <<EOF
Domain: $NODE_DOMAIN
Public TCP/UDP port: 443
Reality public key: $REALITY_PUBLIC_KEY
Reality short ID: $REALITY_SHORT_ID
Reality SNI: $NODE_DOMAIN
XHTTP path: $XHTTP_PATH
XHTTP mode: $XHTTP_MODE
XHTTP TLS SNI: $NODE_DOMAIN
Hysteria2 SNI: $NODE_DOMAIN
Remnawave Node port: $NODE_PORT/tcp (allowed from $PANEL_IP)
EOF
    chmod 600 "$INSTALL_DIR/connection-settings.txt"

    printf '\n'
    ok "Установка завершена"
    printf '  Config Profile: %s\n' "$PROFILE_FILE"
    printf '  Host settings:  %s\n' "$INSTALL_DIR/connection-settings.txt"
    printf '  Диагностика:     sudo remnassh diagnostics\n\n'
    warn "443/tcp и 443/udp начнут слушаться после назначения full-profile.json ноде в Remnawave."
    warn "Hysteria2 в актуальном Xray работает, но учёт UDP-трафика по пользователям в Remnawave может быть неполным."
}
