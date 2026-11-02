[Unit]
Description=Keep RemnaSSH alternate port aliases active

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=30s
Persistent=true
Unit=remnassh-port-aliases-refresh.service

[Install]
WantedBy=timers.target
