# ubuntu-stereo-receiver

Turns an Ubuntu machine with a USB DAC into an **AirPlay speaker** ("Office Stereo")
with self-healing, so nobody ever has to log in and restart anything.

Built after debugging a real outage (Sep 2026); see "Design notes" for the
failure modes this setup is hardened against.

## How it works

```
Mac/iPhone --AirPlay--> shairport-sync --> ALSA (hw:USB) --> USB DAC --> amplifier
                              |
                           avahi (mDNS advertisement)
                              |
        stereo-watchdog.timer (every 2 min): restarts whatever broke
```

- **shairport-sync** receives AirPlay audio and writes it directly to the USB
  sound card via ALSA (exclusive, bit-perfect S32/44.1kHz).
- **avahi** advertises the receiver on the network so it shows up in the
  AirPlay picker.
- **The watchdog** (systemd timer, every 2 min) fixes: dead services, missing
  mDNS registrations, and registrations wedged by a WiFi reconnect/roam.
- A startup guard blocks shairport from registering before the network is up
  (the classic "device vanished from the picker" bug).

## Install (fresh Ubuntu server)

```bash
sudo apt install -y git
git clone https://github.com/<you>/ubuntu-stereo-receiver.git
cd ubuntu-stereo-receiver
# optional: edit config/settings.conf (speaker name, ALSA device, USB match)
sudo ./install.sh
```

Requirements: Ubuntu with a USB audio device plugged in.

## What gets installed

| File | Purpose |
|---|---|
| `/etc/shairport-sync.conf` | receiver config (from template, name/device substituted) |
| `/etc/stereo-receiver/settings.conf` | shared settings sourced by the watchdog |
| `/usr/local/bin/stereo-watchdog.sh` | self-healing watchdog |
| `/usr/local/bin/wait-for-stereo-network.sh` | shairport ExecStartPre network guard |
| `/etc/systemd/system/shairport-sync.service.d/override.conf` | Restart=always + guard |
| `/etc/systemd/system/stereo-watchdog.{service,timer}` | watchdog units |

`uninstall.sh` removes all of the above (packages stay).

## Troubleshooting

```bash
journalctl -t stereo-watchdog        # what the watchdog caught/fixed
journalctl -u shairport-sync -n 100  # receiver logs
avahi-browse -rt _raop._tcp          # is the receiver advertised?
aplay -l                             # is the USB DAC present?
```

**If the stereo is visible but a Mac can't play to it:** macOS caches AirPlay
endpoints per receiver incarnation. Every time shairport-sync restarts, the Mac
mints a new "Office Stereo" entry and old ones become zombies that fail silently.
Pick another entry with the same name, or reset macOS's audio daemon:

```bash
sudo killall coreaudiod   # on the Mac; takes ~1 second
```

**If the watchdog keeps warning about a missing USB device:** the DAC is
dropping off the bus - reseat or replace the cable, try a different port, and
keep the DAC away from WiFi dongles on the same USB controller.

## Design notes (why it looks like this)

1. **Direct ALSA, no mixing layer.** shairport owns `hw:...` exclusively. If
   you also need local players (Music Assistant etc.) on the same card, route
   them through PipeWire instead of adding takeover scripts - exclusive-open
   handover hooks were removed as fragile.
2. **Registration races are real.** Registering with avahi before the network
   interface is fully up produces a service that exists internally but is
   invisible on the LAN. The ExecStartPre guard plus watchdog check #5 exist
   for this.
3. **Anything that restarts the receiver costs Mac clients a stale endpoint.**
   That's inherent to AirPlay-1; the whole design aims to make restarts rare
   (they only happen after genuine faults, then self-heal).
