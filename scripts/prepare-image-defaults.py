#!/usr/bin/env python3
"""Bake package defaults and the selected provisioning IP into the image."""
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
        target = output / 'etc/audiowrt/provisioning-ip'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(provisioning_ip + '\n')


if __name__ == '__main__':
    if len(sys.argv) not in (4, 5):
        raise SystemExit('usage: prepare-image-defaults.py PACKAGES FEED OUTPUT [PROVISIONING_IP]')
    prepare(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
            sys.argv[4] if len(sys.argv) == 5 else '192.168.77.1')
