#!/usr/bin/env bash

readonly PANEL_STATE_FILE="$INSTALL_DIR/panel.env"
readonly PANEL_COOKIE_FILE="$INSTALL_DIR/panel.cookies"
PANEL_SYNCED_PROFILE=""

panel_save_state() {
    local tmp="$PANEL_STATE_FILE.tmp"
    {
        printf 'PANEL_URL=%q\n' "$PANEL_URL"
        printf 'PANEL_TOKEN=%q\n' "$PANEL_TOKEN"
        printf 'PANEL_AUTH_URL=%q\n' "${PANEL_AUTH_URL:-}"
        printf 'PANEL_PROFILE_UUID=%q\n' "${PANEL_PROFILE_UUID:-}"
        printf 'PANEL_NODE_UUID=%q\n' "${PANEL_NODE_UUID:-}"
        printf 'PANEL_TEMPLATE_UUID=%q\n' "${PANEL_TEMPLATE_UUID:-}"
        printf 'PANEL_SQUAD_UUID=%q\n' "${PANEL_SQUAD_UUID:-}"
        printf 'PANEL_ENTRY_REMARK=%q\n' "${PANEL_ENTRY_REMARK:-}"
    } > "$tmp"
    chmod 0600 "$tmp"
    mv -f "$tmp" "$PANEL_STATE_FILE"
}

panel_origin_from_url() {
    local url="$1" rest authority
    case "$url" in
        https://*) rest="${url#https://}"; printf 'https://' ;;
        http://*) rest="${url#http://}"; printf 'http://' ;;
        *) return 1 ;;
    esac
    authority="${rest%%/*}"
    authority="${authority%%\?*}"
    [[ -n "$authority" ]] || return 1
    printf '%s' "$authority"
}

panel_set_endpoint() {
    local value="$1" origin
    [[ "$value" =~ ^https?://[^[:space:]\"\\]+$ ]] || die "Некорректная ссылка панели"
    origin="$(panel_origin_from_url "$value")" || die "Не удалось определить домен панели"
    PANEL_URL="$origin"
    if [[ "${value%/}" != "$origin" ]]; then
        PANEL_AUTH_URL="$value"
    else
        PANEL_AUTH_URL=""
    fi
}

panel_authorize_cookie() {
    local config
    [[ -n "${PANEL_AUTH_URL:-}" ]] || return 1
    [[ "$PANEL_AUTH_URL" =~ ^https?://[^[:space:]\"\\]+$ ]] || return 1
    PANEL_URL="$(panel_origin_from_url "$PANEL_AUTH_URL")" || return 1
    config="$(mktemp)"
    printf 'url = "%s"\n' "$PANEL_AUTH_URL" > "$config"
    : > "$PANEL_COOKIE_FILE"
    chmod 0600 "$config" "$PANEL_COOKIE_FILE"
    if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 45 --max-redirs 8 \
        --user-agent 'Mozilla/5.0 RemnaSSH' --config "$config" \
        --cookie "$PANEL_COOKIE_FILE" --cookie-jar "$PANEL_COOKIE_FILE" \
        -o /dev/null; then
        rm -f -- "$config"
        warn "Не удалось пройти secret-ссылку авторизации"
        return 1
    fi
    rm -f -- "$config"
    if ! awk -F '\t' 'NF >= 7 && $7 != "" {found=1} END {exit !found}' "$PANEL_COOKIE_FILE"; then
        warn "Ссылка открылась, но cookie авторизации не получена"
        return 1
    fi
    ok "Cookie-защита панели пройдена" >&2
}

panel_api() {
    local method="$1" path="$2" data="${3:-}"
    local retried="${4:-0}" headers response status reason
    local -a cookie_args=()
    headers="$(mktemp)"
    response="$(mktemp)"
    [[ -s "$PANEL_COOKIE_FILE" ]] && cookie_args=(--cookie "$PANEL_COOKIE_FILE")
    {
        printf 'Authorization: Bearer %s\n' "$PANEL_TOKEN"
        printf 'Accept: application/json\n'
        printf 'Content-Type: application/json\n'
    } > "$headers"
    chmod 0600 "$headers"

    if [[ -n "$data" ]]; then
        if ! status="$(printf '%s' "$data" | curl -sS --connect-timeout 10 --max-time 90 \
            -X "$method" "$PANEL_URL$path" -H "@$headers" "${cookie_args[@]}" --data-binary @- \
            -o "$response" -w '%{http_code}')"; then
            rm -f -- "$headers" "$response"
            warn "Панель недоступна: $PANEL_URL"
            return 1
        fi
    elif ! status="$(curl -sS --connect-timeout 10 --max-time 90 \
        -X "$method" "$PANEL_URL$path" -H "@$headers" "${cookie_args[@]}" \
        -o "$response" -w '%{http_code}')"; then
        rm -f -- "$headers" "$response"
        warn "Панель недоступна: $PANEL_URL"
        return 1
    fi
    rm -f -- "$headers"

    reason=""
    [[ "$status" == 2* ]] || reason="HTTP $status"
    if [[ -z "$reason" ]] && ! jq -e . "$response" >/dev/null 2>&1; then
        reason="вместо JSON получена страница авторизации"
    fi
    if [[ -n "$reason" && "$retried" == 0 && -n "${PANEL_AUTH_URL:-}" ]]; then
        rm -f -- "$response"
        if panel_authorize_cookie; then
            panel_api "$method" "$path" "$data" 1
            return
        fi
        return 1
    fi
    if [[ -n "$reason" ]]; then
        warn "API Remnawave: $reason — $(tr '\n' ' ' < "$response" | cut -c1-500)"
        rm -f -- "$response"
        return 1
    fi
    cat "$response"
    rm -f -- "$response"
}

panel_load_credentials() {
    local endpoint response new_endpoint new_token
    if [[ -f "$PANEL_STATE_FILE" ]]; then
        # Файл создаётся установщиком и доступен только root.
        # shellcheck source=/dev/null
        source "$PANEL_STATE_FILE"
    fi
    if [[ -z "${PANEL_URL:-}" && -z "${PANEL_AUTH_URL:-}" ]]; then
        read -r -s -p "Secret-ссылка входа или обычный URL панели: " endpoint
        printf '\n'
        panel_set_endpoint "$endpoint"
    elif [[ -n "${PANEL_AUTH_URL:-}" ]]; then
        PANEL_URL="$(panel_origin_from_url "$PANEL_AUTH_URL")" || die "Некорректная сохранённая auth-ссылка"
    fi
    PANEL_URL="${PANEL_URL%/}"
    [[ "$PANEL_URL" =~ ^https?://[^/]+(:[0-9]+)?$ ]] || die "Некорректный URL панели: $PANEL_URL"

    if [[ -z "${PANEL_TOKEN:-}" ]]; then
        read -r -s -p "API-токен Remnawave: " PANEL_TOKEN
        printf '\n'
    fi
    [[ -n "$PANEL_TOKEN" ]] || die "API-токен не задан"

    if [[ -n "${PANEL_AUTH_URL:-}" && ! -s "$PANEL_COOKIE_FILE" ]]; then
        panel_authorize_cookie || true
    fi
    if ! response="$(panel_api GET /api/config-profiles)"; then
        warn "Авторизация панели не сработала"
        read -r -s -p "Новая secret-ссылка/URL или Enter, чтобы оставить текущую: " new_endpoint
        printf '\n'
        [[ -z "$new_endpoint" ]] || panel_set_endpoint "$new_endpoint"
        [[ "$PANEL_URL" =~ ^https?://[^/]+(:[0-9]+)?$ ]] || die "Некорректный URL панели: $PANEL_URL"
        [[ -z "${PANEL_AUTH_URL:-}" ]] || panel_authorize_cookie || true
        read -r -s -p "Новый API-токен Remnawave или Enter, чтобы оставить текущий: " new_token
        printf '\n'
        [[ -z "$new_token" ]] || PANEL_TOKEN="$new_token"
        [[ -n "$PANEL_TOKEN" ]] || die "API-токен не задан"
        response="$(panel_api GET /api/config-profiles)" || die "Не удалось авторизоваться в API панели"
    fi
    jq -e '.response.configProfiles | type == "array"' <<<"$response" >/dev/null ||
        die "Панель вернула неожиданный ответ"
    panel_save_state
}

panel_profile_name() {
    local name="RemnaSSH ${NODE_DOMAIN%%.*}"
    printf '%s' "${name:0:30}"
}

panel_sync_profile() {
    local profiles name profile_uuid body response profile
    profiles="$(panel_api GET /api/config-profiles)" || return 1
    name="$(panel_profile_name)"
    profile_uuid=""
    if [[ -n "${PANEL_PROFILE_UUID:-}" ]]; then
        profile_uuid="$(jq -r --arg uuid "$PANEL_PROFILE_UUID" '.response.configProfiles[] | select(.uuid == $uuid) | .uuid' <<<"$profiles" | head -n 1)"
    fi
    if [[ -z "$profile_uuid" ]]; then
        profile_uuid="$(jq -r --arg name "$name" '.response.configProfiles[] | select(.name == $name) | .uuid' <<<"$profiles" | head -n 1)"
    fi

    if [[ -n "$profile_uuid" ]]; then
        body="$(jq -n --arg uuid "$profile_uuid" --arg name "$name" --slurpfile config "$PROFILE_FILE" \
            '{uuid:$uuid,name:$name,config:$config[0]}')"
        response="$(panel_api PATCH /api/config-profiles "$body")" || return 1
        ok "Config Profile обновлён: $name" >&2
    else
        body="$(jq -n --arg name "$name" --slurpfile config "$PROFILE_FILE" \
            '{name:$name,config:$config[0]}')"
        response="$(panel_api POST /api/config-profiles "$body")" || return 1
        profile_uuid="$(jq -r '.response.uuid // empty' <<<"$response")"
        [[ -n "$profile_uuid" ]] || return 1
        ok "Config Profile создан: $name" >&2
    fi
    PANEL_PROFILE_UUID="$profile_uuid"
    panel_save_state

    profiles="$(panel_api GET /api/config-profiles)" || return 1
    profile="$(jq -c --arg uuid "$profile_uuid" '.response.configProfiles[] | select(.uuid == $uuid)' <<<"$profiles")"
    [[ -n "$profile" ]] || die "Созданный профиль не найден при повторной проверке"
    PANEL_SYNCED_PROFILE="$profile"
}

panel_select_node() {
    local nodes="$1" selected="" public_ip="" choice index=1
    local -a entries=()
    mapfile -t entries < <(jq -c '.response[]' <<<"$nodes")
    ((${#entries[@]})) || die "В панели нет нод"

    if [[ -n "${PANEL_NODE_UUID:-}" ]]; then
        selected="$(jq -r --arg uuid "$PANEL_NODE_UUID" '.response[] | select(.uuid == $uuid) | .uuid' <<<"$nodes" | head -n 1)"
    fi
    if [[ -z "$selected" ]]; then
        selected="$(jq -r --arg address "$NODE_DOMAIN" '.response[] | select(.address == $address) | .uuid' <<<"$nodes" | head -n 1)"
    fi
    if [[ -z "$selected" ]]; then
        public_ip="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
        [[ -z "$public_ip" ]] || selected="$(jq -r --arg address "$public_ip" '.response[] | select(.address == $address) | .uuid' <<<"$nodes" | head -n 1)"
    fi
    if [[ -n "$selected" ]]; then
        printf '%s' "$selected"
        return
    fi
    if ((${#entries[@]} == 1)); then
        jq -r '.uuid' <<<"${entries[0]}"
        return
    fi

    printf '\nВыберите ноду в панели:\n' >&2
    for entry in "${entries[@]}"; do
        printf '  %d. %s — %s:%s\n' "$index" \
            "$(jq -r '.name' <<<"$entry")" "$(jq -r '.address' <<<"$entry")" "$(jq -r '.port' <<<"$entry")" >&2
        ((index++))
    done
    read -r -p "Номер ноды: " choice >&2
    [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#entries[@]})) || die "Некорректный номер ноды"
    jq -r '.uuid' <<<"${entries[choice-1]}"
}

panel_assign_profile() {
    local profile="$1" nodes node_uuid body
    local -a inbound_uuids=()
    nodes="$(panel_api GET /api/nodes)" || return 1
    node_uuid="$(panel_select_node "$nodes")"
    mapfile -t inbound_uuids < <(jq -r '.inbounds[].uuid' <<<"$profile")
    ((${#inbound_uuids[@]} == 4)) || die "В профиле ожидалось четыре inbound, найдено ${#inbound_uuids[@]}"
    body="$(printf '%s\n' "${inbound_uuids[@]}" | jq -R . | jq -s --arg uuid "$node_uuid" --arg profile "$PANEL_PROFILE_UUID" \
        '{uuid:$uuid,configProfile:{activeConfigProfileUuid:$profile,activeInbounds:.}}')"
    panel_api PATCH /api/nodes "$body" >/dev/null || return 1
    PANEL_NODE_UUID="$node_uuid"
    panel_save_state
    ok "Профиль назначен ноде"
}

panel_select_squad() {
    local squads="$1" selected="" choice index=1
    local -a entries=()
    mapfile -t entries < <(jq -c '.response.internalSquads[]' <<<"$squads")
    ((${#entries[@]})) || return 1
    if [[ -n "${PANEL_SQUAD_UUID:-}" ]]; then
        selected="$(jq -r --arg uuid "$PANEL_SQUAD_UUID" '.response.internalSquads[] | select(.uuid == $uuid) | .uuid' <<<"$squads" | head -n 1)"
    fi
    if [[ -n "$selected" ]]; then
        printf '%s' "$selected"
        return
    fi
    if ((${#entries[@]} == 1)); then
        jq -r '.uuid' <<<"${entries[0]}"
        return
    fi

    printf '\nВыберите Internal Squad для новых inbound:\n' >&2
    for entry in "${entries[@]}"; do
        printf '  %d. %s\n' "$index" "$(jq -r '.name' <<<"$entry")" >&2
        ((index++))
    done
    printf '  0. Не добавлять в Squad сейчас\n' >&2
    read -r -p "Номер группы: " choice >&2
    [[ "$choice" =~ ^[0-9]+$ ]] || die "Некорректный номер группы"
    ((choice == 0)) && return 1
    ((choice <= ${#entries[@]})) || die "Некорректный номер группы"
    jq -r '.uuid' <<<"${entries[choice-1]}"
}

panel_update_squad() {
    local profile="$1" squads squad_uuid squad body
    squads="$(panel_api GET /api/internal-squads)" || return 1
    if ! squad_uuid="$(panel_select_squad "$squads")"; then
        warn "Inbound не добавлены в Internal Squad"
        return 0
    fi
    squad="$(jq -c --arg uuid "$squad_uuid" '.response.internalSquads[] | select(.uuid == $uuid)' <<<"$squads")"
    body="$(jq -n --arg uuid "$squad_uuid" \
        --argjson current "$(jq '[.inbounds[].uuid]' <<<"$squad")" \
        --argjson added "$(jq '[.inbounds[].uuid]' <<<"$profile")" \
        '{uuid:$uuid,inbounds:(($current + $added) | unique)}')"
    panel_api PATCH /api/internal-squads "$body" >/dev/null || return 1
    PANEL_SQUAD_UUID="$squad_uuid"
    panel_save_state
    ok "Inbound добавлены в Internal Squad"
}

panel_sync_template() {
    local templates name="RemnaSSH Balancer" uuid="" body response
    templates="$(panel_api GET /api/subscription-templates)" || return 1
    if [[ -n "${PANEL_TEMPLATE_UUID:-}" ]]; then
        uuid="$(jq -r --arg uuid "$PANEL_TEMPLATE_UUID" '.response.templates[] | select(.uuid == $uuid and .templateType == "XRAY_JSON") | .uuid' <<<"$templates" | head -n 1)"
    fi
    if [[ -z "$uuid" ]]; then
        uuid="$(jq -r --arg name "$name" '.response.templates[] | select(.name == $name and .templateType == "XRAY_JSON") | .uuid' <<<"$templates" | head -n 1)"
    fi
    if [[ -z "$uuid" ]]; then
        body="$(jq -n --arg name "$name" '{name:$name,templateType:"XRAY_JSON"}')"
        response="$(panel_api POST /api/subscription-templates "$body")" || return 1
        uuid="$(jq -r '.response.uuid // empty' <<<"$response")"
        [[ -n "$uuid" ]] || return 1
    fi
    body="$(jq -n --arg uuid "$uuid" --arg name "$name" --slurpfile template "$BALANCER_FILE" \
        '{uuid:$uuid,name:$name,templateJson:$template[0]}')"
    panel_api PATCH /api/subscription-templates "$body" >/dev/null || return 1
    PANEL_TEMPLATE_UUID="$uuid"
    panel_save_state
    ok "XRAY_JSON-шаблон балансировщика синхронизирован"
}

panel_inbound_uuid() {
    local profile="$1" tag="$2"
    jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .uuid' <<<"$profile" | head -n 1
}

panel_host_body() {
    local inbound_uuid="$1" remark="$2" port="$3" path="$4" alpn="$5"
    local hidden="$6" template_uuid="$7" group_tag="$8" host_header="$9"
    local security_layer="${10:-DEFAULT}" excluded_types="${11:-[]}"
    local description="${NODE_DOMAIN%%.*}"
    [[ "$hidden" == true ]] || description="$remark"
    jq -n \
        --arg profile "$PANEL_PROFILE_UUID" --arg inbound "$inbound_uuid" \
        --arg remark "$remark" --arg address "$NODE_DOMAIN" --argjson port "$port" \
        --arg path "$path" --arg sni "$NODE_DOMAIN" --arg host "$host_header" --arg alpn "$alpn" \
        --arg node "$PANEL_NODE_UUID" --arg template "$template_uuid" --arg tag "$group_tag" \
        --arg description "$description" --arg security "$security_layer" \
        --argjson hidden "$hidden" --argjson excluded "$excluded_types" \
        '{inbound:{configProfileUuid:$profile,configProfileInboundUuid:$inbound},remark:$remark,
          address:$address,port:$port,path:(if $path == "" then null else $path end),sni:$sni,
          host:(if $host == "" then null else $host end),alpn:(if $alpn == "" then null else $alpn end),
          fingerprint:"chrome",isDisabled:false,securityLayer:$security,tags:[$tag],nodes:[$node],
          isHidden:$hidden,serverDescription:($description[0:30]),
          excludeFromSubscriptionTypes:$excluded,
          xrayJsonTemplateUuid:(if $template == "" then null else $template end)}'
}

panel_upsert_host() {
    local hosts="$1" body="$2" remark tag uuid request inbound port hidden template
    remark="$(jq -r '.remark' <<<"$body")"
    tag="$(jq -r '.tags[0]' <<<"$body")"
    inbound="$(jq -r '.inbound.configProfileInboundUuid' <<<"$body")"
    port="$(jq -r '.port' <<<"$body")"
    hidden="$(jq -r '.isHidden' <<<"$body")"
    template="$(jq -r '.xrayJsonTemplateUuid // empty' <<<"$body")"
    uuid="$(jq -r --arg tag "$tag" --arg inbound "$inbound" --argjson port "$port" \
        --argjson hidden "$hidden" --arg template "$template" '
        .response[] |
        select(.tags | index($tag)) |
        select(
          (if $template != "" then
             (.isHidden == false and (.xrayJsonTemplateUuid // "") != "")
           else
             (.isHidden == $hidden and .port == $port and
              .inbound.configProfileInboundUuid == $inbound)
           end)
        ) | .uuid' <<<"$hosts" | head -n 1)"
    if [[ -n "$uuid" ]]; then
        request="$(jq --arg uuid "$uuid" '. + {uuid:$uuid}' <<<"$body")"
        panel_api PATCH /api/hosts "$request" >/dev/null || return 1
    else
        panel_api POST /api/hosts "$body" >/dev/null || return 1
    fi
    ok "Host синхронизирован: $remark"
}

panel_detect_entry_remark() {
    local public_ip response country flag
    [[ -z "${PANEL_ENTRY_REMARK:-}" ]] || return 0

    public_ip="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
    if [[ -n "$public_ip" ]]; then
        response="$(curl -fsS --connect-timeout 5 --max-time 15 \
            "https://ipwho.is/${public_ip}?lang=ru&fields=success,country,country_code,city,flag" 2>/dev/null || true)"
        if jq -e '.success == true' >/dev/null 2>&1 <<<"$response"; then
            country="$(jq -r '.country // empty' <<<"$response")"
            flag="$(jq -r '.flag.emoji // empty' <<<"$response")"
        fi
    fi

    if [[ -n "${country:-}" ]]; then
        PANEL_ENTRY_REMARK="${flag:+$flag }$country"
        ok "Определена локация входной ноды: $PANEL_ENTRY_REMARK" >&2
        panel_save_state
    else
        PANEL_ENTRY_REMARK="${NODE_DOMAIN%%.*}"
        warn "Не удалось определить локацию; входная нода названа $PANEL_ENTRY_REMARK" >&2
    fi
}

panel_sync_hosts() {
    local profile="$1" hosts short group_tag reality xhttp grpc hysteria body port
    short="${NODE_DOMAIN%%.*}"
    short="${short:0:12}"
    group_tag="REMNASSH:${PANEL_NODE_UUID:0:8}"
    group_tag="${group_tag^^}"
    reality="$(panel_inbound_uuid "$profile" VLESS_RAW_REALITY)"
    xhttp="$(panel_inbound_uuid "$profile" VLESS_XHTTP_CADDY)"
    grpc="$(panel_inbound_uuid "$profile" VLESS_GRPC_CADDY)"
    hysteria="$(panel_inbound_uuid "$profile" HYSTERIA2_TLS)"
    [[ -n "$reality" && -n "$xhttp" && -n "$grpc" && -n "$hysteria" ]] || die "Не удалось сопоставить inbound профиля"
    hosts="$(panel_api GET /api/hosts)" || return 1
    panel_detect_entry_remark

    body="$(panel_host_body "$reality" "$PANEL_ENTRY_REMARK" 443 "" "" false "$PANEL_TEMPLATE_UUID" \
        "$group_tag" "" DEFAULT '["XRAY_BASE64","MIHOMO","STASH","CLASH","SINGBOX"]')"
    panel_upsert_host "$hosts" "$body" || return 1
    body="$(panel_host_body "$xhttp" "p3-xhttp-$short" 443 "$XHTTP_PATH" h2 true "" "$group_tag" "$NODE_DOMAIN" TLS)"
    panel_upsert_host "$hosts" "$body" || return 1
    body="$(panel_host_body "$grpc" "p4-grpc-$short" 443 "$GRPC_SERVICE_NAME" h2 true "" "$group_tag" "$NODE_DOMAIN" TLS)"
    panel_upsert_host "$hosts" "$body" || return 1
    body="$(panel_host_body "$reality" "p1-vless-$short" 443 "" "" true "" "$group_tag" "")"
    panel_upsert_host "$hosts" "$body" || return 1
    body="$(panel_host_body "$hysteria" "p2-hysteria-$short" 443 "" h3 true "" "$group_tag" "" TLS)"
    panel_upsert_host "$hosts" "$body" || return 1

    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        body="$(panel_host_body "$xhttp" "p3-xhttp-$short-$port" "$port" "$XHTTP_PATH" h2 true "" "$group_tag" "$NODE_DOMAIN" TLS)"
        panel_upsert_host "$hosts" "$body" || return 1
        body="$(panel_host_body "$grpc" "p4-grpc-$short-$port" "$port" "$GRPC_SERVICE_NAME" h2 true "" "$group_tag" "$NODE_DOMAIN" TLS)"
        panel_upsert_host "$hosts" "$body" || return 1
        body="$(panel_host_body "$reality" "p1-vless-$short-$port" "$port" "" "" true "" "$group_tag" "")"
        panel_upsert_host "$hosts" "$body" || return 1
    done < <(tr ',' '\n' <<<"$ALT_TCP_PORTS")
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        body="$(panel_host_body "$hysteria" "p2-hysteria-$short-$port" "$port" "" h3 true "" "$group_tag" "" TLS)"
        panel_upsert_host "$hosts" "$body" || return 1
    done < <(tr ',' '\n' <<<"$ALT_UDP_PORTS")
}

panel_verify_sync() {
    local profiles nodes hosts templates group_tag count
    profiles="$(panel_api GET /api/config-profiles)" || return 1
    nodes="$(panel_api GET /api/nodes)" || return 1
    hosts="$(panel_api GET /api/hosts)" || return 1
    templates="$(panel_api GET /api/subscription-templates)" || return 1
    group_tag="REMNASSH:${PANEL_NODE_UUID:0:8}"
    group_tag="${group_tag^^}"
    jq -e --arg uuid "$PANEL_PROFILE_UUID" '.response.configProfiles[] | select(.uuid == $uuid)' <<<"$profiles" >/dev/null
    jq -e --arg node "$PANEL_NODE_UUID" --arg profile "$PANEL_PROFILE_UUID" \
        '.response[] | select(.uuid == $node and .configProfile.activeConfigProfileUuid == $profile)' <<<"$nodes" >/dev/null
    jq -e --arg uuid "$PANEL_TEMPLATE_UUID" '.response.templates[] | select(.uuid == $uuid)' <<<"$templates" >/dev/null
    count="$(jq -r --arg tag "$group_tag" '[.response[] | select(.tags | index($tag))] | length' <<<"$hosts")"
    ((count >= 5)) || die "В панели найдено только $count управляемых Hosts"
    ok "Проверка панели пройдена: профиль, нода, шаблон и $count Hosts"
}

panel_sync() {
    require_root
    load_state
    install_runtime_files
    require_command curl
    require_command jq
    [[ -s "$PROFILE_FILE" && -s "$BALANCER_FILE" ]] || die "Сначала сгенерируйте профиль ноды"
    panel_load_credentials
    local profile
    panel_sync_profile || die "Не удалось синхронизировать Config Profile"
    profile="$PANEL_SYNCED_PROFILE"
    panel_assign_profile "$profile" || die "Не удалось назначить профиль ноде"
    panel_update_squad "$profile" || die "Не удалось обновить Internal Squad"
    panel_sync_template || die "Не удалось синхронизировать XRAY_JSON-шаблон"
    panel_sync_hosts "$profile" || die "Не удалось синхронизировать Hosts"
    panel_verify_sync
    ok "RemnaSSH полностью синхронизирован с панелью Remnawave"
}

offer_panel_sync() {
    local answer
    [[ "$ASSUME_YES" != 1 && -t 0 ]] || return 0
    printf '\n'
    read -r -p "Создать профиль, Hosts и балансировщик в панели Remnawave? [Y/n]: " answer
    [[ ! "${answer,,}" =~ ^(n|no|н|нет)$ ]] || return 0
    panel_sync
}
