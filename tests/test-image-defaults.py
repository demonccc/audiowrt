#!/usr/bin/env python3
"""Check selective, build-time defaults without fetching feeds or building firmware."""
import importlib.util
from pathlib import Path
import tempfile

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('defaults', repo / 'scripts/prepare-image-defaults.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    feed = root / 'feed'
    airplay = feed / 'audiowrt-airplay/files'
    spotify = feed / 'audiowrt-spotify/files'
    mpd = feed / 'audiowrt-mpd/files'
    airplay.mkdir(parents=True)
    spotify.mkdir(parents=True)
    mpd.mkdir(parents=True)
    (airplay / 'airplay.settings').write_text('enabled=1\nname=%H\n')
    (spotify / 'spotify.settings').write_text('enabled=1\nbackend=alsa\n')
    (mpd / 'mpd.conf').write_text('state_file "/tmp/mpd/state"\n')
    packages = root / 'packages'
    packages.write_text('audiowrt-core\n')
    module.prepare(packages, feed, root / 'empty')
    assert list((root / 'empty').iterdir()) == []
    packages.write_text('audiowrt-airplay\naudiowrt-spotify\naudiowrt-mpd\n')
    module.prepare(packages, feed, root / 'image')
    assert "option name '%H'" in (root / 'image/etc/config/shairport-sync').read_text()
    assert "option enabled '1'" in (root / 'image/etc/config/librespot').read_text()
    assert (root / 'image/etc/mpd.conf').read_bytes() == (mpd / 'mpd.conf').read_bytes()
    assert not (root / 'image/etc/uci-defaults').exists()
    packages.write_text('audiowrt-provisioning\n')
    module.prepare(packages, feed, root / 'custom-ip', '10.42.17.1')
    assert (root / 'custom-ip/etc/audiowrt/provisioning-ip').read_text() == '10.42.17.1\n'
    factory = (root / 'custom-ip/etc/uci-defaults/10-audiowrt-factory').read_text()
    assert "hostname='audiowrt'" in factory
    assert "network.lan.proto='dhcp'" in factory
    assert "192.168.1.1" in factory
    assert "wireless." not in factory
print('Build-time module defaults passed')
