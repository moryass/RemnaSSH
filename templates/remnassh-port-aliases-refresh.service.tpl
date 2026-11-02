[Unit]
Description=Refresh RemnaSSH alternate port aliases
After=network-online.target ufw.service firewalld.service docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/remnassh-port-aliases start
