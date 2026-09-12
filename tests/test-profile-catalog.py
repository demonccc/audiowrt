#!/usr/bin/env python3
"""Exercise catalog rejection and dropdown updates using isolated repositories."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    for directory in ('scripts', 'profiles', 'config', '.github'):
        shutil.copytree(source / directory, root / directory)
    profile = root / 'profiles/tplink-tl-wdr4300-v1-minimal-25.12.5.yaml'
    original = profile.read_text()

    def run(script, *args, valid=True):
        result = subprocess.run([sys.executable, str(root / 'scripts' / script), *args], capture_output=True, text=True)
        assert (result.returncode == 0) == valid, result.stdout + result.stderr

    run('validate-profile-catalog.py')
    for content in (
        original.replace('maintainer_github: demonccc\n', ''),
        original + 'unexpected: value\n',
        original + 'status: candidate\n',
        original.replace('maintainer_github: demonccc', 'maintainer_github: @invalid'),
        original.replace('schema_version: 1', 'schema_version: 2'),
        original.replace('status: reference', 'status: []'),
        original.replace('packages_add: []', 'packages_add:\n  - test\n  - test'),
        original.replace('packages_add: []', 'packages_add:\n  - test').replace('packages_remove: []', 'packages_remove:\n  - test'),
    ):
        profile.write_text(content)
        run('validate-profile-catalog.py', valid=False)
    profile.write_text(original)
    for name in ('bad.yaml', 'device-other-25.12.5.yaml', 'device-minimal-25.yaml', 'device--minimal-25.12.5.yaml', 'device-minimal-25.12.5.yml', 'notes.txt'):
        bad = root / 'profiles' / name
        bad.write_text(original)
        run('validate-profile-catalog.py', valid=False)
        bad.unlink()
    nested = root / 'profiles/nested'
    nested.mkdir()
    run('validate-profile-catalog.py', valid=False)
    nested.rmdir()
    link = root / 'profiles/link-minimal-25.12.5.yaml'
    link.symlink_to(profile.name)
    run('validate-profile-catalog.py', valid=False)
    link.unlink()
    added = root / 'profiles/example-device-full-snapshot.yaml'
    added.write_text(original)
    run('sync-profile-workflow.py', '--check', valid=False)
    run('sync-profile-workflow.py')
    run('sync-profile-workflow.py', '--check')
    workflow = root / '.github/workflows/build-audiowrt.yml'
    assert '          - example-device-full-snapshot' in workflow.read_text()
    # Removing the current default must also repair its value.
    profile.unlink()
    added.unlink()
    run('sync-profile-workflow.py')
    run('sync-profile-workflow.py', '--check')
    assert 'default: tplink-tl-wdr4300-v1-minimal-25.12.5' not in workflow.read_text()
    assert '          - example-device-full-snapshot' not in workflow.read_text()
print('Profile catalog rejection and dropdown lifecycle tests passed.')
