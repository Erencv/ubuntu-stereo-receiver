#!/bin/sh
# Block shairport-sync start until avahi is active and a default route exists.
# Prevents registering into the void while WiFi/DHCP is still coming up,
# which leaves the service advertised internally but invisible on the wire.
i=0
while [ "$i" -lt 60 ]; do
    if systemctl -q is-active avahi-daemon && ip route show default 2>/dev/null | grep -q .; then
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
echo "stereo: network/avahi not ready after 60s; letting systemd retry" >&2
exit 1
