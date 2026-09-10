{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "VLESS_RAW_REALITY",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "127.0.0.1:__CADDY_INTERNAL_PORT__",
          "serverNames": ["__DOMAIN__"],
          "privateKey": "__REALITY_PRIVATE_KEY__",
          "minClientVer": "1.8.1",
          "shortIds": ["__REALITY_SHORT_ID__"]
        }
      }
    },
    {
      "tag": "VLESS_XHTTP_CADDY",
      "listen": "/dev/shm/remnassh-xhttp.sock,0666",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "mode": "__XHTTP_MODE__",
          "path": "__XHTTP_PATH__"
        }
      }
    },
    {
      "tag": "HYSTERIA2_TLS",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "hysteria",
      "settings": {
        "version": 2,
        "clients": []
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "hysteria",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h3"],
          "minVersion": "1.3",
          "maxVersion": "1.3",
          "rejectUnknownSni": true,
          "certificates": [
            {
              "usage": "encipherment",
              "oneTimeLoading": false,
              "certificateFile": "/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/__DOMAIN__/__DOMAIN__.crt",
              "keyFile": "/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/__DOMAIN__/__DOMAIN__.key"
            }
          ]
        },
        "hysteriaSettings": {
          "version": 2,
          "auth": "",
          "udpIdleTimeout": 60
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "DIRECT",
      "protocol": "freedom"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "BLOCK"
      }
    ]
  }
}
