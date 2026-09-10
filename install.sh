#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/preflight.sh
source "$SCRIPT_DIR/lib/preflight.sh"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"
# shellcheck source=lib/firewall.sh
source "$SCRIPT_DIR/lib/firewall.sh"
# shellcheck source=lib/diagnostics.sh
source "$SCRIPT_DIR/lib/diagnostics.sh"

usage() {
    cat <<'EOF'
RemnaSSH — Remnawave multi-protocol node installer

Usage:
  sudo bash install.sh install [options]
  sudo bash install.sh generate
  sudo bash install.sh status
  sudo bash install.sh diagnostics
  sudo bash install.sh update

Install options:
  --domain DOMAIN             Domain whose A/AAAA record points to this server
  --email EMAIL               Email for Let's Encrypt
  --panel-ip IP_OR_CIDR       Panel address allowed to reach NODE_PORT
  --node-port PORT            Remnawave Node API port (default: 2222)
  --caddy-port PORT           Loopback-only Caddy HTTPS port (default: 8443)
  --xhttp-mode MODE           stream-one, stream-up, packet-up or auto
  --secret-key-file FILE      File containing the Remnawave Node secret key
  --skip-dns-check            Do not require DNS/public-IP equality
  --yes                       Do not ask for final confirmation
  -h, --help                  Show this help

The installer supports Ubuntu 22.04/24.04+ and Debian 12+.
EOF
}

parse_install_args() {
    while (($#)); do
        case "$1" in
            --domain) require_arg "$1" "${2:-}"; NODE_DOMAIN="$2"; shift 2 ;;
            --email) require_arg "$1" "${2:-}"; ACME_EMAIL="$2"; shift 2 ;;
            --panel-ip) require_arg "$1" "${2:-}"; PANEL_IP="$2"; shift 2 ;;
            --node-port) require_arg "$1" "${2:-}"; NODE_PORT="$2"; shift 2 ;;
            --caddy-port) require_arg "$1" "${2:-}"; CADDY_INTERNAL_PORT="$2"; shift 2 ;;
            --xhttp-mode) require_arg "$1" "${2:-}"; XHTTP_MODE="$2"; shift 2 ;;
            --secret-key-file) require_arg "$1" "${2:-}"; SECRET_KEY_FILE="$2"; shift 2 ;;
            --skip-dns-check) export SKIP_DNS_CHECK=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Неизвестный аргумент: $1" ;;
        esac
    done
}

collect_settings() {
    local cli_domain="${NODE_DOMAIN:-}" cli_email="${ACME_EMAIL:-}" cli_panel_ip="${PANEL_IP:-}"
    local cli_node_port="${NODE_PORT:-}" cli_caddy_port="${CADDY_INTERNAL_PORT:-}" cli_xhttp_mode="${XHTTP_MODE:-}"
    if [[ -f "$STATE_FILE" ]]; then
        load_state
        info "Найдены сохранённые настройки в $STATE_FILE"
    fi

    NODE_DOMAIN="${cli_domain:-${NODE_DOMAIN:-}}"
    ACME_EMAIL="${cli_email:-${ACME_EMAIL:-}}"
    PANEL_IP="${cli_panel_ip:-${PANEL_IP:-}}"
    NODE_PORT="${cli_node_port:-${NODE_PORT:-2222}}"
    CADDY_INTERNAL_PORT="${cli_caddy_port:-${CADDY_INTERNAL_PORT:-8443}}"
    XHTTP_MODE="${cli_xhttp_mode:-${XHTTP_MODE:-stream-one}}"

    prompt_if_empty NODE_DOMAIN "Домен ноды"
    prompt_if_empty ACME_EMAIL "Email для Let's Encrypt"
    prompt_if_empty PANEL_IP "IP/CIDR панели Remnawave"

    NODE_DOMAIN="${NODE_DOMAIN,,}"
    validate_domain "$NODE_DOMAIN" || die "Некорректный домен: $NODE_DOMAIN"
    validate_email "$ACME_EMAIL" || die "Некорректный email: $ACME_EMAIL"
    validate_port "$NODE_PORT" || die "Некорректный NODE_PORT: $NODE_PORT"
    validate_port "$CADDY_INTERNAL_PORT" || die "Некорректный внутренний порт Caddy: $CADDY_INTERNAL_PORT"
    [[ "$NODE_PORT" != "$CADDY_INTERNAL_PORT" ]] || die "NODE_PORT и внутренний порт Caddy должны отличаться"
    validate_xhttp_mode "$XHTTP_MODE" || die "Некорректный XHTTP mode: $XHTTP_MODE"
    validate_ip_or_cidr "$PANEL_IP" || die "Некорректный IP/CIDR панели: $PANEL_IP"

    if [[ -n "${SECRET_KEY_FILE:-}" ]]; then
        [[ -f "$SECRET_KEY_FILE" ]] || die "Файл ключа не найден: $SECRET_KEY_FILE"
        NODE_SECRET="$(<"$SECRET_KEY_FILE")"
    elif [[ -f "$INSTALL_DIR/secret-key" ]]; then
        NODE_SECRET="$(<"$INSTALL_DIR/secret-key")"
    else
        read_multiline_secret
    fi
    [[ -n "$NODE_SECRET" ]] || die "Secret Key не может быть пустым"

    XHTTP_PATH="${XHTTP_PATH:-/api/v3/$(random_hex 8)/video_stream.mp4}"
    REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(random_hex 8)}"
    if [[ -z "${SITE_TEMPLATE:-}" ]]; then
        local -a site_templates=(site-journal.html.tpl site-studio.html.tpl site-workshop.html.tpl)
        SITE_TEMPLATE="${site_templates[RANDOM % ${#site_templates[@]}]}"
    fi
}

confirm_install() {
    printf '\n'
    info "Будет установлена схема:"
    printf '  VLESS RAW + REALITY  : 443/tcp\n'
    printf '  VLESS XHTTP + TLS    : 443/tcp -> Caddy -> Unix socket\n'
    printf '  Hysteria2 + TLS      : 443/udp\n'
    printf '  Remnawave Node API   : %s/tcp, доступ только с %s\n' "$NODE_PORT" "$PANEL_IP"
    printf '  Домен                 : %s\n' "$NODE_DOMAIN"
    printf '  XHTTP path            : %s\n\n' "$XHTTP_PATH"

    if [[ "$ASSUME_YES" != 1 ]]; then
        read -r -p "Продолжить? [y/N]: " answer
        [[ "$answer" =~ ^[YyДд]$ ]] || die "Отменено пользователем"
    fi
}

install_stack() {
    require_root
    detect_os
    install_base_packages
    validate_ip_or_cidr "$PANEL_IP" || die "Некорректный IP/CIDR панели: $PANEL_IP"
    check_install_target
    check_dns
    check_ports
    confirm_install
    install_docker
    prepare_directories
    install_runtime_files
    generate_reality_keys
    write_secret
    write_state
    render_stack
    validate_rendered_files
    configure_firewall
    start_stack
    validate_xray_profile
    install_command
    print_result
}

generate_profile() {
    require_root
    load_state
    require_command docker
    generate_reality_keys
    write_state
    render_profile
    validate_xray_profile_if_certificate_exists
    ok "Профиль обновлён: $PROFILE_FILE"
}

update_stack() {
    require_root
    load_state
    require_command docker
    cd "$INSTALL_DIR"
    docker compose pull
    docker compose up -d --remove-orphans
    diagnostics || true
}

main() {
    local command="${1:-install}"
    [[ $# -eq 0 ]] || shift

    case "$command" in
        install)
            parse_install_args "$@"
            banner
            require_root
            collect_settings
            install_stack
            ;;
        generate) generate_profile ;;
        status) status_report ;;
        diagnostics|doctor) diagnostics ;;
        update) update_stack ;;
        -h|--help|help) usage ;;
        *) usage; die "Неизвестная команда: $command" ;;
    esac
}

main "$@"
