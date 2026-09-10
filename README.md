# RemnaSSH

Установщик Remnawave Node для Ubuntu и Debian. Поднимает три подключения на одном публичном порту:

- VLESS RAW + REALITY + Vision — `443/tcp`;
- VLESS XHTTP + TLS — `443/tcp`;
- Hysteria2 + TLS — `443/udp`.

Caddy обслуживает обычные HTTPS-запросы и передаёт XHTTP-трафик в Xray через Unix socket. Снаружи нужны только `80/tcp`, `443/tcp`, `443/udp` и порт Node API, доступный с IP панели.

## Требования

- Ubuntu 22.04/24.04+ или Debian 12+;
- root-доступ;
- домен с A/AAAA-записью на сервер;
- созданная нода в Remnawave и её Secret Key;
- на время первого выпуска сертификата CDN-прокси должен быть отключён.

Установщик включает UFW, сохраняет доступ к текущему SSH-порту, открывает `80/tcp`, `443/tcp`, `443/udp` и разрешает порт Node API только с адреса панели. Внешний firewall в панели хостинг-провайдера при его наличии настраивается отдельно.

## Установка

```bash
git clone https://github.com/moryass/RemnaSSH.git
cd RemnaSSH
sudo bash install.sh install
```

Для установки без вопросов:

```bash
sudo bash install.sh install \
  --domain node.example.com \
  --email admin@example.com \
  --panel-ip 203.0.113.10/32 \
  --secret-key-file /root/remnawave-node-secret.txt \
  --yes
```

После установки готовый профиль будет находиться в `/opt/remnanode/full-profile.json`, а параметры подключений — в `/opt/remnanode/connection-settings.txt`.

Для обычных HTTPS-запросов установщик выбирает один из встроенных сайтов-заглушек. Выбранный шаблон сохраняется при повторной установке.

## Настройка панели

1. Создайте Config Profile и вставьте содержимое `/opt/remnanode/full-profile.json`.
2. Назначьте профиль ноде и включите три inbound.
3. Добавьте inbound в нужный Internal Squad.
4. Создайте Hosts с параметрами ниже.

### VLESS RAW REALITY

- Address: IP или домен ноды
- Port: `443`
- Security: `reality`
- SNI: домен ноды
- Fingerprint: `chrome`
- Flow: `xtls-rprx-vision`
- Public Key и Short ID: из `connection-settings.txt`

### VLESS XHTTP

- Address: домен ноды
- Port: `443`
- Security: `tls`
- SNI/Host: домен ноды
- ALPN: `h2`
- Path и Mode: из `connection-settings.txt`
- Fingerprint: `chrome`

### Hysteria2

- Address/SNI: домен ноды
- Port: `443`
- TLS verification: включена
- ALPN: `h3`

Для Hysteria2 в качестве пароля используется UUID пользователя.

## Команды

```bash
sudo remnassh status
sudo remnassh diagnostics
sudo remnassh update
sudo remnassh generate
```

Конфигурация хранится в `/opt/remnanode`. Caddy автоматически обновляет TLS-сертификат, Xray перечитывает его без ручного перезапуска.

Private networks и BitTorrent блокируются правилами профиля. Остальной разрешённый трафик выходит напрямую с IP сервера.
