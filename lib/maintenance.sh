#!/usr/bin/env bash

backup_stack() {
    require_root
    load_state

    local backup_dir="$INSTALL_DIR/backups"
    local archive timestamp path
    local -a paths=()
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    archive="$backup_dir/remnassh-$timestamp.tar.gz"

    install -d -m 0700 "$backup_dir"
    for path in state.env node.env secret-key full-profile.json connection-settings.txt \
        docker-compose.yml Caddyfile Caddyfile.final Caddyfile.bootstrap .env www; do
        [[ -e "$INSTALL_DIR/$path" ]] && paths+=("$path")
    done
    ((${#paths[@]})) || die "Нет файлов для резервного копирования"

    tar -czf "$archive" -C "$INSTALL_DIR" "${paths[@]}"
    chmod 0600 "$archive"
    ok "Резервная копия: $archive"
}
