#!/usr/bin/env bash
# Remove the stereo receiver deployment (packages are left installed).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo ./uninstall.sh" >&2
    exit 1
fi

systemctl disable --now stereo-watchdog.timer 2>/dev/null || true
rm -f /etc/systemd/system/stereo-watchdog.service /etc/systemd/system/stereo-watchdog.timer
rm -rf /etc/systemd/system/shairport-sync.service.d
rm -f /usr/local/bin/stereo-watchdog.sh /usr/local/bin/wait-for-stereo-network.sh
rm -rf /etc/stereo-receiver
systemctl daemon-reload

echo "Removed watchdog, config drop-in and scripts."
echo "shairport-sync is still installed (stop it with: systemctl disable --now shairport-sync)."
echo "Original config backups, if any, remain at /etc/shairport-sync.conf.bak.*"
