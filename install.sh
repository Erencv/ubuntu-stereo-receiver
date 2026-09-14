#!/usr/bin/env bash
# Install the AirPlay stereo receiver stack on an Ubuntu machine.
# Usage: sudo ./install.sh
# Edit config/settings.conf first if your speaker name or USB device differs.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo ./install.sh" >&2
    exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config/settings.conf
source "$DIR/config/settings.conf"

echo "==> Installing packages (shairport-sync, avahi, alsa-utils)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq shairport-sync avahi-daemon avahi-utils alsa-utils

echo "==> Validating USB audio device ('$USB_MATCH')"
if aplay -l | grep -q "$USB_MATCH"; then
    aplay -l | grep "$USB_MATCH"
else
    echo "WARNING: no audio device matching '$USB_MATCH' found - plug it in and rerun if needed. Continuing."
fi

if [[ -f /etc/shairport-sync.conf ]]; then
    BAK="/etc/shairport-sync.conf.bak.$(date +%Y%m%d-%H%M%S)"
    echo "==> Backing up existing config to $BAK"
    cp /etc/shairport-sync.conf "$BAK"
fi

echo "==> Deploying configuration (name: '$SERVICE_NAME', device: $ALSA_DEVICE)"
mkdir -p /etc/stereo-receiver /etc/systemd/system/shairport-sync.service.d
cp "$DIR/config/settings.conf" /etc/stereo-receiver/settings.conf
sed -e "s|@SERVICE_NAME@|$SERVICE_NAME|" -e "s|@ALSA_DEVICE@|$ALSA_DEVICE|" \
    "$DIR/config/shairport-sync.conf.tmpl" > /etc/shairport-sync.conf
install -m 755 "$DIR/scripts/wait-for-stereo-network.sh" /usr/local/bin/
install -m 755 "$DIR/scripts/stereo-watchdog.sh" /usr/local/bin/
cp "$DIR/config/shairport-sync.service.d_override.conf" /etc/systemd/system/shairport-sync.service.d/override.conf
cp "$DIR/config/stereo-watchdog.service" "$DIR/config/stereo-watchdog.timer" /etc/systemd/system/

# Anything else that might hold the sound card open (we learned this the hard way)
systemctl disable --now squeezelite 2>/dev/null || true

echo "==> Enabling services"
systemctl daemon-reload
systemctl enable --now avahi-daemon
systemctl restart shairport-sync
systemctl enable --now stereo-watchdog.timer
sleep 3

echo "==> Verification"
echo "    shairport-sync: $(systemctl is-active shairport-sync)"
echo "    watchdog timer: $(systemctl is-active stereo-watchdog.timer)"
if avahi-browse -rt _raop._tcp 2>/dev/null | grep -q "$SERVICE_NAME"; then
    echo "OK: '$SERVICE_NAME' is live on the network. Select it in the AirPlay picker."
else
    echo "WARNING: '$SERVICE_NAME' not advertised yet - check: journalctl -u shairport-sync -n 50"
fi
