#!/usr/bin/env bash

readonly INSTALL_DIR="${REMNASSH_INSTALL_DIR:-/opt/remnanode}"
readonly STATE_FILE="$INSTALL_DIR/state.env"
readonly PROFILE_FILE="$INSTALL_DIR/full-profile.json"
readonly MARKER_FILE="$INSTALL_DIR/.remnassh-managed"
readonly CADDY_IMAGE_DEFAULT="caddy:2.11.4-alpine"
readonly REMNANODE_IMAGE_DEFAULT="remnawave/node:3.4.1"

ASSUME_YES="${ASSUME_YES:-0}"
SKIP_DNS_CHECK="${SKIP_DNS_CHECK:-0}"

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info() { printf '%b[•]%b %s\n' "$BLUE" "$NC" "$*"; }
ok() { printf '%b[✓]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
die() { printf '%b[✗]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

banner() {
    cat <<'EOF'
╔══════════════════════════════════════════════════╗
║                   RemnaSSH                       ║
║   REALITY · XHTTP/Caddy · Hysteria2 · Remnawave ║
╚══════════════════════════════════════════════════╝
EOF
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Нужны права root. Запустите через sudo."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"
}

require_arg() {
    [[ -n "$2" ]] || die "После $1 требуется значение"
}

prompt_if_empty() {
    local name="$1" prompt="$2" value
    if [[ -z "${!name:-}" ]]; then
        [[ -t 0 ]] || die "Не задано значение --${name,,}"
        read -r -p "$prompt: " value
        printf -v "$name" '%s' "$value"
    fi
}

read_multiline_secret() {
    [[ -t 0 ]] || die "Передайте --secret-key-file в неинтерактивном режиме"
    printf '\nВставьте Secret Key ноды. После последней строки нажмите Enter ещё раз:\n'
    NODE_SECRET=""
    local line
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            [[ -n "$NODE_SECRET" ]] && break
            continue
        fi
        NODE_SECRET+="${NODE_SECRET:+$'\n'}$line"
    done
}

random_hex() {
    local bytes="${1:-8}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    else
        od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
    fi
}

validate_domain() {
    local value="$1"
    [[ ${#value} -le 253 ]] || return 1
    [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

validate_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

validate_xhttp_mode() {
    case "$1" in stream-one|stream-up|packet-up|auto) return 0 ;; *) return 1 ;; esac
}

validate_ip_or_cidr() {
    if ! command -v python3 >/dev/null 2>&1; then
        [[ "$1" =~ ^[0-9a-fA-F:.]+(/[0-9]{1,3})?$ ]]
        return
    fi
    python3 - "$1" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    raise SystemExit(1)
PY
}

load_state() {
    [[ -f "$STATE_FILE" ]] || die "Не найден $STATE_FILE. Сначала выполните install."
    # Values are escaped with printf %q and the file is owned by root.
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    SITE_TEMPLATE="${SITE_TEMPLATE:-site-studio.html.tpl}"
}

write_state() {
    local tmp="$INSTALL_DIR/.state.env.tmp"
    {
        printf 'NODE_DOMAIN=%q\n' "$NODE_DOMAIN"
        printf 'ACME_EMAIL=%q\n' "$ACME_EMAIL"
        printf 'PANEL_IP=%q\n' "$PANEL_IP"
        printf 'NODE_PORT=%q\n' "$NODE_PORT"
        printf 'CADDY_INTERNAL_PORT=%q\n' "$CADDY_INTERNAL_PORT"
        printf 'XHTTP_MODE=%q\n' "$XHTTP_MODE"
        printf 'XHTTP_PATH=%q\n' "$XHTTP_PATH"
        printf 'SITE_TEMPLATE=%q\n' "${SITE_TEMPLATE:-site-studio.html.tpl}"
        printf 'REALITY_PRIVATE_KEY=%q\n' "$REALITY_PRIVATE_KEY"
        printf 'REALITY_PUBLIC_KEY=%q\n' "$REALITY_PUBLIC_KEY"
        printf 'REALITY_SHORT_ID=%q\n' "$REALITY_SHORT_ID"
        printf 'CADDY_IMAGE=%q\n' "${CADDY_IMAGE:-$CADDY_IMAGE_DEFAULT}"
        printf 'REMNANODE_IMAGE=%q\n' "${REMNANODE_IMAGE:-$REMNANODE_IMAGE_DEFAULT}"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}
