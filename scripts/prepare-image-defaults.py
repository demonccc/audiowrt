#!/usr/bin/env python3
"""Bake AudioWRT factory/package defaults into the image."""
from pathlib import Path
import shutil
import sys


def prepare(packages_file, feed, output, provisioning_ip="192.168.77.1"):
    packages = {line.strip() for line in packages_file.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith('#')}
    output.mkdir(parents=True, exist_ok=True)
    for module, package, section in (
        ('airplay', 'shairport-sync', 'shairport_sync'),
        ('spotify', 'librespot', 'main'),
    ):
        if f'audiowrt-{module}' not in packages:
            continue
        lines = [f"config {package} '{section}'"]
        settings = feed / f'audiowrt-{module}' / 'files' / f'{module}.settings'
        for line in settings.read_text().splitlines():
            if not line:
                continue
            key, value = line.split('=', 1)
            value = value.replace("'", "'\\''")
            lines.append(f"\toption {key} '{value}'")
        target = output / 'etc/config' / package
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('\n'.join(lines) + '\n')
    if 'audiowrt-mpd' in packages:
        (output / 'etc').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(feed / 'audiowrt-mpd/files/mpd.conf', output / 'etc/mpd.conf')

    if 'audiowrt-provisioning' in packages:
        target = output / 'etc/uci-defaults/10-audiowrt-factory'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("""#!/bin/sh
# AudioWRT factory network state:
#   hostname audiowrt
#   LAN DHCP client only
#   no WAN
#   no persistent Wi-Fi configuration
# The setup AP is created later by provisioning entirely at runtime.

uci -q set 'system.@system[0].hostname=audiowrt' || true

uci -q set network.lan.proto='dhcp' || true
uci -q delete network.lan.ipaddr 2>/dev/null || true
uci -q delete network.lan.netmask 2>/dev/null || true
uci -q delete network.lan.ip6assign 2>/dev/null || true
uci -q delete network.lan.gateway 2>/dev/null || true
uci -q delete network.lan.dns 2>/dev/null || true

# Factory image has no WAN interfaces.
uci -q delete network.wan 2>/dev/null || true
uci -q delete network.wan6 2>/dev/null || true

# LAN is a client, never a DHCP server.
if [ -f /etc/config/dhcp ] && uci -q get dhcp.lan >/dev/null 2>&1; then
    uci -q set dhcp.lan.ignore='1' || true
fi
uci -q delete dhcp.wan 2>/dev/null || true

# Remove every stock/persistent wifi-iface. Keep wifi-device hardware sections:
# provisioning resolves the PHY from them but creates its AP only in RAM.
for section in $(uci -q show wireless 2>/dev/null |
    sed -n "s/^wireless\.\([^.=]*\)=wifi-iface.*/\1/p"); do
    uci -q delete "wireless.$section" 2>/dev/null || true
done

uci -q commit system || true
uci -q commit network || true
[ ! -f /etc/config/dhcp ] || uci -q commit dhcp || true
[ ! -f /etc/config/wireless ] || uci -q commit wireless || true
return 0
""")
        target.chmod(0o755)
    if 'audiowrt-provisioning' in packages:
        target = output / 'etc/audiowrt/provisioning-ip'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(provisioning_ip + '\n')


if __name__ == '__main__':
    if len(sys.argv) not in (4, 5):
        raise SystemExit('usage: prepare-image-defaults.py PACKAGES FEED OUTPUT [PROVISIONING_IP]')
    prepare(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
            sys.argv[4] if len(sys.argv) == 5 else '192.168.77.1')
