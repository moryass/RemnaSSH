#!/usr/bin/env bash

menu_clear() {
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

menu_pause() {
    printf '\n'
    read -r -p "Нажмите Enter, чтобы вернуться в меню..." _ || true
}

menu_installed() {
    [[ -f "$STATE_FILE" && -f "$INSTALL_DIR/docker-compose.yml" ]]
}

menu_container_state() {
    local container="$1" state
    if ! command -v docker >/dev/null 2>&1; then
        printf 'Docker не установлен'
        return
    fi
    state="$(docker inspect -f '{{if .State.Running}}работает{{else}}остановлен{{end}}' "$container" 2>/dev/null || true)"
    printf '%s' "${state:-не найден}"
}

menu_header() {
    local domain="" node_state caddy_state
    menu_clear
    banner
    if menu_installed; then
        # state.env принадлежит root и записывается установщиком.
        # shellcheck source=/dev/null
        source "$STATE_FILE"
        domain="${NODE_DOMAIN:-не задан}"
        node_state="$(menu_container_state remnanode)"
        caddy_state="$(menu_container_state remnassh-caddy)"
        printf '%bНода:%b %s\n' "$BLUE" "$NC" "$domain"
        printf '%bСостояние:%b Node — %s, Caddy — %s\n\n' "$BLUE" "$NC" "$node_state" "$caddy_state"
    else
        printf '%bСостояние:%b нода не установлена\n\n' "$YELLOW" "$NC"
    fi
}

menu_run() {
    printf '\n'
    if bash "$SCRIPT_PATH" "$@"; then
        printf '\n%bОперация завершена.%b\n' "$GREEN" "$NC"
    else
        printf '\n%bОперация завершилась с ошибкой.%b\n' "$RED" "$NC"
    fi
    menu_pause
}

menu_confirm() {
    local prompt="$1" answer
    read -r -p "$prompt [y/N]: " answer
    [[ "${answer,,}" =~ ^(y|yes|д|да)$ ]]
}

backup_menu() {
    local choice archive
    while true; do
        menu_header
        printf '%bРезервные копии%b\n\n' "$GREEN" "$NC"
        printf '  1. Создать резервную копию\n'
        printf '  2. Показать список копий\n'
        printf '  3. Восстановить последнюю копию\n'
        printf '  4. Восстановить выбранный архив\n'
        printf '\n  0. Назад\n\n'
        read -r -p "Выберите действие: " choice
        case "$choice" in
            1) menu_run backup ;;
            2) menu_run backups ;;
            3)
                if menu_confirm "Восстановить последнюю копию?"; then
                    menu_run restore latest
                fi
                ;;
            4)
                read -r -p "Полный путь к архиву: " archive
                if [[ -n "$archive" ]] && menu_confirm "Восстановить $archive?"; then
                    menu_run restore "$archive"
                fi
                ;;
            0) return ;;
            *) warn "Выберите пункт от 0 до 4"; sleep 1 ;;
        esac
    done
}

installed_menu() {
    local choice config
    while true; do
        menu_header
        printf '  1. Состояние ноды\n'
        printf '  2. Полная диагностика\n'
        printf '  3. Обновить RemnaSSH, Node и конфигурацию\n'
        printf '  4. Перезапустить сервисы\n'
        printf '  5. Пересобрать профиль ноды\n'
        printf '  6. Показать параметры подключений\n'
        printf '  7. Синхронизировать с панелью Remnawave\n'
        printf '  8. Резервные копии и восстановление\n'
        printf '  9. Проверить VPN клиентским JSON\n'
        printf ' 10. Последние логи\n'
        printf '\n  0. Выход\n\n'
        read -r -p "Выберите действие: " choice
        case "$choice" in
            1) menu_run status ;;
            2) menu_run diagnostics ;;
            3)
                if menu_confirm "Запустить безопасное обновление?"; then
                    menu_run remote-update
                fi
                ;;
            4)
                if menu_confirm "Перезапустить Caddy и Remnawave Node?"; then
                    menu_run restart
                fi
                ;;
            5) menu_run generate ;;
            6) menu_run settings ;;
            7) menu_run panel-sync ;;
            8) backup_menu ;;
            9)
                read -r -p "Полный путь к клиентскому JSON: " config
                [[ -z "$config" ]] || menu_run probe "$config"
                ;;
            10) menu_run logs ;;
            0) return ;;
            *) warn "Выберите пункт от 0 до 10"; sleep 1 ;;
        esac
    done
}

interactive_menu() {
    require_root
    if menu_installed; then
        installed_menu
        return
    fi

    local choice
    while true; do
        menu_header
        printf '  1. Установить Remnawave Node\n'
        printf '\n  0. Выход\n\n'
        read -r -p "Выберите действие: " choice
        case "$choice" in
            1) menu_run install ;;
            0) return ;;
            *) warn "Выберите 0 или 1"; sleep 1 ;;
        esac
        if menu_installed; then
            installed_menu
            return
        fi
    done
}
