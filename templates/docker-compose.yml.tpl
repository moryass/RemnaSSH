name: remnassh-node

x-common: &common
  restart: unless-stopped
  network_mode: host
  logging:
    driver: json-file
    options:
      max-size: 20m
      max-file: "5"

services:
  caddy:
    <<: *common
    image: __CADDY_IMAGE__
    container_name: remnassh-caddy
    hostname: remnassh-caddy
    env_file:
      - .env
    extra_hosts:
      - "${NODE_DOMAIN}:127.0.0.1"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./www:/srv/www:ro
      - ./caddy-data:/data
      - ./caddy-config:/config
      - /dev/shm:/dev/shm:rw
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider --no-check-certificate https://$${NODE_DOMAIN}:$${CADDY_INTERNAL_PORT}/ || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 18
      start_period: 10s

  remnanode:
    <<: *common
    image: __REMNANODE_IMAGE__
    container_name: remnanode
    hostname: remnanode
    cap_add:
      - NET_ADMIN
    env_file:
      - node.env
    volumes:
      - ./caddy-data:/data:ro
      - /dev/shm:/dev/shm:rw
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
