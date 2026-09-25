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
# AudioWRT factory defaults. Apply only while the device still has OpenWrt's
# untouched factory identity/network values; never overwrite user settings.

hostname="$(uci -q get 'system.@system[0].hostname' 2>/dev/null || true)"
case "$hostname" in
    ''|OpenWrt|openwrt)
        uci -q set 'system.@system[0].hostname=audiowrt' || true
        ;;
esac

lan_proto="$(uci -q get network.lan.proto 2>/dev/null || true)"
lan_ip="$(uci -q get network.lan.ipaddr 2>/dev/null || true)"
if [ "$lan_proto" = 'static' ] && [ "$lan_ip" = '192.168.1.1' ]; then
    uci -q set network.lan.proto='dhcp' || true
    uci -q delete network.lan.ipaddr 2>/dev/null || true
    uci -q delete network.lan.netmask 2>/dev/null || true
    uci -q delete network.lan.ip6assign 2>/dev/null || true
    uci -q delete network.lan.gateway 2>/dev/null || true
    uci -q delete network.lan.dns 2>/dev/null || true

    if [ -f /etc/config/dhcp ] && uci -q get dhcp.lan >/dev/null 2>&1; then
        uci -q set dhcp.lan.ignore='1' || true
    fi
fi

# Wireless factory state intentionally remains untouched. OpenWrt keeps the
# radios disabled; AudioWRT provisioning temporarily owns exactly one PHY.
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
