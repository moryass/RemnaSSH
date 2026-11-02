#!/usr/bin/env bash

set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$repo_dir"
work="$(mktemp -d)"
export REMNASSH_INSTALL_DIR="$work"
mkdir -p "$work/tool"

printf '%s\n' \
    'NODE_DOMAIN=node.example.com' \
    'XHTTP_PATH=/api/v3/test/video_stream.mp4' \
    'XHTTP_MODE=stream-one' \
    'GRPC_SERVICE_NAME=grpc_test' \
    'ALT_TCP_PORTS=8443,2053' \
    'ALT_UDP_PORTS=8443' > "$work/state.env"
printf '%s\n' \
    'PANEL_TOKEN=test-token' \
    'PANEL_AUTH_URL=http://127.0.0.1:18080/auth/login?caddy=test-secret' \
    'PANEL_ENTRY_REMARK=🇸🇪\ Швеция' > "$work/panel.env"
jq -n '{inbounds:[
    {tag:"VLESS_RAW_REALITY"},
    {tag:"VLESS_XHTTP_CADDY"},
    {tag:"HYSTERIA2_TLS"},
    {tag:"VLESS_GRPC_CADDY"}
]}' > "$work/full-profile.json"
cp "$repo_dir/templates/happ-balancer.json" "$work/happ-balancer.json"

# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/render.sh
source "$repo_dir/lib/render.sh"
# shellcheck source=lib/panel.sh
source "$repo_dir/lib/panel.sh"
panel_sync
panel_sync

state="$(curl -fsS http://127.0.0.1:18080/state)"
jq -e '
    (.profiles | length) == 1 and
    (.templates | length) == 1 and
    (.hosts | length) == 12 and
    .nodes[0].configProfile.activeConfigProfileUuid == "11111111-1111-4111-8111-111111111111" and
    (.squads[0].inbounds | length) == 4 and
    ([.hosts[] | select(.isHidden == false)] | length) == 1 and
    ([.hosts[] | select(.isHidden == false)][0].remark) == "🇸🇪 Швеция" and
    ([.hosts[] | select(.isHidden == false)][0].inbound.configProfileInboundUuid) == "55555555-5555-4555-8555-000000000001" and
    ([.hosts[] | select(.isHidden == false)][0].excludeFromSubscriptionTypes | length) == 5 and
    ([.hosts[]] | all(.fingerprint == "firefox")) and
    ([.hosts[] | select(.remark | startswith("p3-xhttp"))] | all(.securityLayer == "TLS")) and
    ([.hosts[] | select(.remark | startswith("p4-grpc"))] | all(.securityLayer == "TLS")) and
    ([.hosts[] | select(.remark | startswith("p2-hysteria"))] | all(.securityLayer == "TLS")) and
    ([.hosts[] | select(.remark | startswith("p1-vless"))] | all(.securityLayer == "DEFAULT"))
' <<<"$state" >/dev/null
