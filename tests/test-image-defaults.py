#!/usr/bin/env python3
"""Check selective, build-time defaults without fetching feeds or building firmware."""
import importlib.util
import os
from pathlib import Path
import subprocess
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
    factory = root / 'custom-ip/etc/uci-defaults/10-audiowrt-factory'
    assert factory.is_file()

    fakebin = root / 'fakebin'
    fakebin.mkdir()
    log = root / 'uci.log'
    uci = fakebin / 'uci'
    uci.write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$UCI_LOG"
[ "$1" != "-q" ] || shift
if [ "$1" = get ] && [ "$2" = 'system.@system[0].hostname' ]; then
    printf '%s\\n' "$FAKE_HOSTNAME"
elif [ "$1" = get ] && [ "$2" = network.lan.proto ]; then
    printf '%s\\n' "$FAKE_LAN_PROTO"
elif [ "$1" = get ] && [ "$2" = network.lan.ipaddr ]; then
    printf '%s\\n' "$FAKE_LAN_IP"
elif [ "$1" = set ] || [ "$1" = delete ]; then
    exit 0
else
    exit 1
fi
""")
    uci.chmod(0o755)

    env = dict(os.environ, PATH=str(fakebin) + ':' + os.environ['PATH'],
               UCI_LOG=str(log), FAKE_HOSTNAME='OpenWrt',
               FAKE_LAN_PROTO='static', FAKE_LAN_IP='192.168.1.1')
    subprocess.run(['sh', '-eu', '-c', f'. "{factory}"'], env=env, check=True)
    actions = log.read_text()
    assert "set system.@system[0].hostname=audiowrt" in actions
    assert "set network.lan.proto=dhcp" in actions
    assert "delete network.lan.ipaddr" in actions
    assert "wireless" not in actions

    log.write_text('')
    env.update(FAKE_HOSTNAME='living-room', FAKE_LAN_PROTO='static',
               FAKE_LAN_IP='10.0.0.20')
    subprocess.run(['sh', '-eu', '-c', f'. "{factory}"'], env=env, check=True)
    actions = log.read_text()
    assert "set " not in actions
    assert "delete " not in actions
print('Build-time module defaults passed')
