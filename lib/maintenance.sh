#!/usr/bin/env bash

backup_stack() {
    require_root
    load_state

    local backup_dir="$INSTALL_DIR/backups"
    local archive timestamp path
    local -a paths=()
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    archive="$backup_dir/remnassh-$timestamp.tar.gz"

    install -d -m 0700 "$backup_dir"
    for path in .remnassh-managed state.env node.env secret-key full-profile.json happ-balancer.json connection-settings.txt \
        docker-compose.yml Caddyfile Caddyfile.final Caddyfile.bootstrap .env www caddy-data caddy-config; do
        [[ -e "$INSTALL_DIR/$path" ]] && paths+=("$path")
    done
    ((${#paths[@]})) || die "Нет файлов для резервного копирования"

    tar -czf "$archive" -C "$INSTALL_DIR" "${paths[@]}"
    chmod 0600 "$archive"
    ok "Резервная копия: $archive"
}

resolve_backup_archive() {
    local requested="${1:-latest}" backup_dir="$INSTALL_DIR/backups" archive
    if [[ "$requested" == latest ]]; then
        archive="$(find "$backup_dir" -maxdepth 1 -type f -name 'remnassh-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr | head -n 1 | cut -d' ' -f2-)"
    else
        archive="$requested"
    fi
    [[ -n "$archive" && -f "$archive" ]] || die "Резервная копия не найдена: $requested"
    readlink -f -- "$archive"
}

validate_backup_archive() {
    local archive="$1" entry
    local -a allowed=(
        .remnassh-managed state.env node.env secret-key full-profile.json happ-balancer.json
        connection-settings.txt docker-compose.yml Caddyfile Caddyfile.final Caddyfile.bootstrap
        .env www caddy-data caddy-config
    )
    local root allowed_root valid

    tar -tzf "$archive" >/dev/null || die "Архив повреждён: $archive"
    while IFS= read -r entry; do
        entry="${entry#./}"
        [[ -n "$entry" ]] || continue
        [[ "$entry" != /* && "$entry" != *"../"* && "$entry" != ".." ]] ||
            die "Архив содержит небезопасный путь: $entry"
        root="${entry%%/*}"
        valid=0
        for allowed_root in "${allowed[@]}"; do
            if [[ "$root" == "$allowed_root" ]]; then
                valid=1
                break
            fi
        done
        ((valid == 1)) || die "Архив содержит неизвестный объект: $entry"
    done < <(tar -tzf "$archive")
    tar -tzf "$archive" | sed 's|^\./||' | grep -qx 'state.env' ||
        die "В архиве нет state.env"
}

restore_stack() {
    require_root
    require_command docker
    require_command tar

    local archive temp_dir
    install -d -m 0700 "$INSTALL_DIR" "$INSTALL_DIR/backups"
    archive="$(resolve_backup_archive "${1:-latest}")"
    validate_backup_archive "$archive"
    temp_dir="$(mktemp -d "$INSTALL_DIR/.restore.XXXXXX")"
    tar -xzf "$archive" -C "$temp_dir"
    if find "$temp_dir" -type l -print -quit | grep -q .; then
        rm -rf -- "$temp_dir"
        die "Архив содержит символические ссылки"
    fi

    if [[ -f "$STATE_FILE" ]]; then
        info "Создаю страховочную копию текущего состояния"
        backup_stack
    else
        warn "Текущего state.env нет; страховочная копия не создана"
    fi
    info "Восстанавливаю $archive"
    cp -a "$temp_dir"/. "$INSTALL_DIR"/
    rm -rf -- "$temp_dir"

    install_runtime_files
    load_state
    cd "$INSTALL_DIR" || die "Не удалось перейти в $INSTALL_DIR"
    validate_rendered_files
    configure_firewall
    configure_port_aliases
    configure_network_tuning
    start_stack
    validate_xray_profile
    diagnostics
    ok "Состояние восстановлено из $archive"
}

running_image_id() {
    docker inspect -f '{{.Image}}' "$1" 2>/dev/null || true
}

rollback_container_images() {
    local caddy_id="$1" node_id="$2"
    local caddy_ref="${CADDY_IMAGE:-$CADDY_IMAGE_DEFAULT}"
    local node_ref="${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}"

    warn "Возвращаю предыдущие образы контейнеров"
    [[ -z "$caddy_id" || "$caddy_ref" == *@* ]] || docker image tag "$caddy_id" "$caddy_ref"
    [[ -z "$node_id" || "$node_ref" == *@* ]] || docker image tag "$node_id" "$node_ref"
    cd "$INSTALL_DIR" || return 1
    docker compose up -d --force-recreate --remove-orphans
}
