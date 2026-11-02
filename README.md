# RemnaSSH

Установщик Remnawave Node для Ubuntu и Debian. Поднимает четыре подключения на одном публичном порту:

- VLESS RAW + REALITY + Vision — `443/tcp`;
- VLESS XHTTP + TLS — `443/tcp`;
- VLESS gRPC + TLS — `443/tcp`;
- Hysteria2 + TLS — `443/udp`.

Caddy обслуживает обычные HTTPS-запросы и передаёт XHTTP/gRPC-трафик в Xray через отдельные Unix sockets. Основные подключения используют `80/tcp`, `443/tcp`, `443/udp`; порт Node API доступен только с IP панели.

Дополнительно установщик создаёт постоянные алиасы `8443/tcp`, `2053/tcp` и `8443/udp` на основной порт `443`. Они дают запас при точечной портовой фильтрации, но не заменяют ноды в разных подсетях. Порты можно изменить параметрами `--alt-tcp-ports` и `--alt-udp-ports` или отключить значением `none`.

## Требования

- Ubuntu 22.04/24.04+ или Debian 12+;
- root-доступ;
- домен с A/AAAA-записью на сервер;
- созданная нода в Remnawave и её Secret Key;
- на время первого выпуска сертификата CDN-прокси должен быть отключён.

Установщик включает UFW, сохраняет доступ к текущему SSH-порту, открывает `80/tcp`, `443/tcp`, `443/udp` и разрешает порт Node API только с адреса панели. Внешний firewall в панели хостинг-провайдера при его наличии настраивается отдельно.

## Установка

Одной командой открывается интерактивное меню:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/moryass/RemnaSSH/main/install.sh)
```

В меню выберите установку ноды. Установщик запросит домен, email, IP панели и Secret Key. Если команда запущена не от root, будет использован `sudo`.
На установленном сервере эта же команда открывает управление нодой: обновление, диагностику, перезапуск, логи, резервные копии и проверку VPN.

Установка из клонированного репозитория:

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

Пример со своими резервными портами:

```bash
sudo bash install.sh install \
  --alt-tcp-ports 8443,2053 \
  --alt-udp-ports 8443
```

После установки профиль ноды будет находиться в `/opt/remnanode/full-profile.json`, готовый Happ-балансировщик — в `/opt/remnanode/happ-balancer.json`, а параметры подключений — в `/opt/remnanode/connection-settings.txt`.

Для обычных HTTPS-запросов установщик выбирает один из встроенных сайтов-заглушек. Выбранный шаблон сохраняется при повторной установке.

## Синхронизация с панелью

Создайте в Remnawave API-токен с правами чтения и изменения Config Profiles, Nodes, Internal Squads, Hosts и Subscription Templates. Затем откройте меню и выберите `Синхронизировать с панелью Remnawave` или выполните:

```bash
sudo remnassh panel-sync
```

Сайт-заглушка выбирается случайно из пяти вариантов: корпоративный сайт, библиотека, бухгалтерская компания, документация или status-page. Сменить его можно в меню либо командой:

```bash
sudo remnassh site
```

Если панель открывается только после secret-ссылки, вставьте эту ссылку целиком: домен будет определён автоматически, а полученная cookie сохранится в `/opt/remnanode/panel.cookies`. Отдельно потребуется API-токен самой Remnawave. Для панели без cookie-защиты укажите обычный URL.

После авторизации скрипт предложит выбрать ноду и Internal Squad, затем автоматически:

- создаст или обновит Config Profile с четырьмя inbound;
- назначит профиль и все inbound выбранной ноде;
- добавит inbound в выбранный Internal Squad;
- создаст XRAY_JSON-шаблон `RemnaSSH Balancer`;
- создаст входной Host с флагом и русским названием страны, скрытые Hosts всех транспортов и копии для резервных портов;
- повторно запросит объекты из панели и проверит результат.

UUID созданных объектов и реквизиты API сохраняются в `/opt/remnanode/panel.env` с доступом только для root. Повторная синхронизация обновляет существующие объекты и не создаёт копии.

Видимый Host служит входом только для `XRAY_JSON`: он привязан к REALITY, а остальные форматы подписки его не получают. Сам балансировщик подключает скрытые XHTTP, gRPC, REALITY и Hysteria2 Hosts по общему тегу. Для XHTTP и gRPC в Host принудительно указывается TLS, поскольку на сервере TLS завершается в Caddy перед передачей во внутренние Unix-сокеты.

Все создаваемые Hosts используют uTLS fingerprint `firefox`. Повторный `panel-sync` обновляет fingerprint у ранее созданных Hosts.

Ниже приведены параметры для ручной настройки, если API-интеграция не используется.

## Ручная настройка панели

1. Создайте Config Profile и вставьте содержимое `/opt/remnanode/full-profile.json`.
2. Назначьте профиль ноде и включите четыре inbound.
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

### VLESS gRPC

- Address: домен ноды
- Port: `443`
- Security: `tls`
- SNI/Authority: домен ноды
- ALPN: `h2`
- Service Name: из `connection-settings.txt`
- Fingerprint: `chrome`

### Hysteria2

- Address/SNI: домен ноды
- Port: `443`
- TLS verification: включена
- ALPN: `h3`

Для Hysteria2 в качестве пароля используется UUID пользователя.

## Балансировщик Happ

Файл `/opt/remnanode/happ-balancer.json` предназначен для Xray JSON Template в Remnawave. Он использует следующий порядок переключения:

1. XHTTP + TLS;
2. gRPC + TLS (аварийный транспорт для сетей, где XHTTP фильтруется);
3. REALITY + Vision;
4. Hysteria2 + TLS.

Remark каждого скрытого Host должен начинаться с соответствующего префикса:

- `p4-grpc` — gRPC;
- `p3-xhttp` — XHTTP;
- `p1-vless` — REALITY;
- `p2-hysteria` — Hysteria2.

Hosts, которые должны автоматически добавляться в балансировщик, создаются скрытыми (`HIDDEN`). Можно добавить несколько нод в каждую группу. `leastLoad` выбирает доступный Host с подходящей задержкой, а `burstObservatory` выполняет три проверки каждую минуту. Российские домены и IP направляются напрямую, BitTorrent блокируется без утечки реального адреса.

Для реальной устойчивости основные ноды должны находиться у разных хостинг-провайдеров и желательно в разных ASN. Несколько протоколов на одном заблокированном IP не заменяют резервную ноду.

Для каждого транспорта можно создать дополнительный Host с тем же доменом, SNI, путём и тегом, но с резервным портом. TCP Hosts используют `8443` или `2053`, Hysteria2 — `8443/udp`. Если у провайдера VPS включён внешний firewall, эти порты необходимо открыть и там: локальный UFW/firewalld установщик настраивает автоматически. Systemd-таймер каждые пять минут проверяет и восстанавливает правила перенаправления после перезагрузки firewall.

## Команды

```bash
sudo remnassh
sudo remnassh status
sudo remnassh diagnostics
sudo remnassh update
sudo remnassh restart
sudo remnassh logs
sudo remnassh generate
sudo remnassh backup
sudo remnassh backups
sudo remnassh panel-sync
sudo remnassh restore latest
sudo remnassh restore /opt/remnanode/backups/remnassh-DATE.tar.gz
sudo remnassh probe /root/happ-client.json
```

Конфигурация хранится в `/opt/remnanode`. Caddy автоматически обновляет TLS-сертификат, Xray перечитывает его без ручного перезапуска.

`restore` сначала проверяет структуру архива и создаёт страховочную копию текущего состояния. В бэкап входят конфигурация, сайт и данные Caddy с сертификатами. `probe` запускает переданный клиентский Xray JSON во временном контейнере и делает реальный HTTPS-запрос через локальный SOCKS-порт `10808`; это проверяет весь путь от клиента до выхода в интернет, а не только состояние контейнеров. Обновление из меню сначала загружает актуальную версию RemnaSSH, затем обновляет Node и конфигурацию. Если новый Node/Caddy не запускается или не проходит диагностику, возвращаются предыдущие образы.

Если ядро поддерживает BBR, установщик включает BBR с очередью `fq`, MTU probing и TCP keepalive. UDP-буферы увеличиваются до 40 MiB для стабильной работы Hysteria2 на быстрых соединениях. Перед обновлением контейнеров автоматически создаётся резервная копия конфигурации.

Private networks и BitTorrent блокируются правилами профиля. Остальной разрешённый трафик выходит напрямую с IP сервера.
