#!/usr/bin/env python3
"""Bake selected extension defaults from package-owned templates; no boot writes."""
from pathlib import Path
import shutil
import sys


def prepare(packages_file, feed, output):
    packages = {line.strip() for line in packages_file.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith('#')}
    output.mkdir(parents=True, exist_ok=True)
    templates = feed / 'audiowrt-extensions/files'
    for extension, package, section in (
        ('airplay', 'shairport-sync', 'shairport_sync'),
        ('spotify', 'librespot', 'main'),
    ):
        if f'audiowrt-{extension}' not in packages:
            continue
        lines = [f"config {package} '{section}'"]
        for line in (templates / f'{extension}.settings').read_text().splitlines():
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
        shutil.copyfile(templates / 'mpd.conf', output / 'etc/mpd.conf')


if __name__ == '__main__':
    prepare(*(Path(arg) for arg in sys.argv[1:]))
