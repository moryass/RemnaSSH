[Unit]
Description=RemnaSSH alternate port aliases
Wants=network-online.target
After=network-online.target ufw.service firewalld.service docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/remnassh-port-aliases start
ExecStop=/usr/local/sbin/remnassh-port-aliases stop
ExecReload=/usr/local/sbin/remnassh-port-aliases start

[Install]
WantedBy=multi-user.target
