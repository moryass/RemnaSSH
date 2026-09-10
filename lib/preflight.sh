#!/usr/bin/env bash

detect_os() {
    [[ -r /etc/os-release ]] || die "Не удалось определить ОС"
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_ID="$ID"
    OS_VERSION_ID="$VERSION_ID"

    case "$OS_ID" in
        ubuntu)
            [[ "${OS_VERSION_ID%%.*}" -ge 22 ]] || die "Нужна Ubuntu 22.04 или новее"
            ;;
        debian)
            [[ "${OS_VERSION_ID%%.*}" -ge 12 ]] || die "Нужен Debian 12 или новее"
            ;;
        *) die "Поддерживаются только Ubuntu и Debian (обнаружено: $OS_ID)" ;;
    esac
    ok "ОС: $PRETTY_NAME"
}

install_base_packages() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg openssl jq python3 iproute2 dnsutils
}

install_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        systemctl enable --now docker >/dev/null 2>&1 || true
        ok "Docker Compose уже установлен"
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        info "Docker найден, устанавливаю Compose plugin"
        if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
            apt-get install -y docker-compose-v2
        elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
            apt-get install -y docker-compose-plugin
        fi
        if docker compose version >/dev/null 2>&1; then
            systemctl enable --now docker >/dev/null 2>&1 || true
            ok "Docker Compose установлен"
            return
        fi
        die "Docker установлен без Compose plugin. Установите совместимый docker-compose-plugin вручную."
    fi

    info "Устанавливаю Docker из официального репозитория"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    local codename arch
    codename="${VERSION_CODENAME:-}"
    [[ -n "$codename" ]] || die "Не удалось определить codename дистрибутива"
    arch="$(dpkg --print-architecture)"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
        "$arch" "$OS_ID" "$codename" > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    docker compose version >/dev/null 2>&1 || die "Docker Compose не запустился"
    ok "Docker установлен"
}

check_install_target() {
    if [[ -e "$INSTALL_DIR" && ! -f "$MARKER_FILE" ]]; then
        if find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
            die "$INSTALL_DIR уже существует и не управляется RemnaSSH. Данные не изменены."
        fi
    fi

    if command -v docker >/dev/null 2>&1; then
        local existing
        existing="$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^(remnanode|remnassh-caddy)$' || true)"
        if [[ -n "$existing" && ! -f "$MARKER_FILE" ]]; then
            die "Найдены существующие контейнеры ($existing). Автоматическое перезаписывание запрещено."
        fi
    fi
}

check_dns() {
    local resolved4 resolved6 public4 public6 mismatch=0 verified=0
    resolved4="$(dig +short A "$NODE_DOMAIN" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u || true)"
    resolved6="$(dig +short AAAA "$NODE_DOMAIN" 2>/dev/null | grep -E ':' | sort -u || true)"
    [[ -n "$resolved4" || -n "$resolved6" ]] || die "У $NODE_DOMAIN нет A/AAAA-записи"

    public4="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
    public6="$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"

    if [[ -n "$resolved4" && -n "$public4" ]]; then
        verified=1
        grep -Fxq "$public4" <<<"$resolved4" || mismatch=1
    fi
    if [[ -n "$resolved6" ]]; then
        verified=1
        [[ -n "$public6" ]] && grep -Fxiq "$public6" <<<"$resolved6" || mismatch=1
    fi

    if [[ "$verified" -eq 0 ]]; then
        warn "Не удалось определить публичный IP; проверена только разрешимость DNS"
        return
    fi

    if [[ "$mismatch" -ne 0 ]]; then
        warn "DNS A: ${resolved4:-нет}; AAAA: ${resolved6:-нет}"
        warn "Публичный адрес сервера: IPv4=${public4:-нет}, IPv6=${public6:-нет}"
        [[ "$SKIP_DNS_CHECK" == 1 ]] || die "DNS не указывает на этот сервер. Исправьте запись или используйте --skip-dns-check."
    else
        ok "DNS указывает на этот сервер"
    fi
}

port_is_listening() {
    local protocol="$1" port="$2"
    if [[ "$protocol" == tcp ]]; then
        ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .
    else
        ss -H -lun "sport = :$port" 2>/dev/null | grep -q .
    fi
}

check_ports() {
    local conflicts=()
    port_is_listening tcp 80 && conflicts+=("80/tcp")
    port_is_listening tcp 443 && conflicts+=("443/tcp")
    port_is_listening udp 443 && conflicts+=("443/udp")
    port_is_listening tcp "$NODE_PORT" && conflicts+=("$NODE_PORT/tcp")
    port_is_listening tcp "$CADDY_INTERNAL_PORT" && conflicts+=("127.0.0.1:$CADDY_INTERNAL_PORT/tcp")

    if ((${#conflicts[@]})) && [[ ! -f "$MARKER_FILE" ]]; then
        die "Заняты требуемые порты: ${conflicts[*]}"
    fi
    ok "Конфликтов портов не найдено"
}
