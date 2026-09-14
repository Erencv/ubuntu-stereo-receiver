#!/bin/sh
# Self-healing watchdog for the AirPlay stereo receiver.
# Runs every 2 minutes from stereo-watchdog.timer.
# Only acts (and only logs) when something is actually broken.
# Settings come from /etc/stereo-receiver/settings.conf.
LOG() { logger -t stereo-watchdog "$*"; }

[ -f /etc/stereo-receiver/settings.conf ] && . /etc/stereo-receiver/settings.conf
SERVICE_NAME="${SERVICE_NAME:-Office Stereo}"
USB_MATCH="${USB_MATCH:-Scarlett}"

# 1. Is the USB DAC present? If not, this is physical - do nothing.
if ! aplay -l 2>/dev/null | grep -q "$USB_MATCH"; then
    logger -t stereo-watchdog "WARN: audio device matching '$USB_MATCH' not present on USB; check cable/port. No action taken."
    exit 0
fi

# 2. mDNS responder alive?
if ! systemctl -q is-active avahi-daemon; then
    LOG "avahi-daemon down - restarting"
    systemctl restart avahi-daemon
    sleep 3
fi

# 3. Receiver alive?
if ! systemctl -q is-active shairport-sync; then
    LOG "shairport-sync down - restarting"
    systemctl restart shairport-sync
    exit 0
fi

# 4. Receiver registered with avahi?
if ! avahi-browse -rt _raop._tcp 2>/dev/null | grep -q "$SERVICE_NAME"; then
    LOG "AirPlay registration missing - restarting shairport-sync"
    systemctl restart shairport-sync
    exit 0
fi

# 5. Did a network interface flap recently (WiFi roam/reconnect)? A carrier
#    bounce can leave the mDNS registration dead on the wire while it still
#    looks fine locally. Runs as root, so the avahi journal is readable.
if journalctl -u avahi-daemon --since "-180 sec" --no-pager 2>/dev/null | grep -qiE "multicast group|for mDNS"; then
    LOG "network interface flap detected - re-registering (restarting shairport-sync)"
    systemctl restart shairport-sync
fi
