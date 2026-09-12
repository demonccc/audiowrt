#!/usr/bin/env python3
"""Reject invalid entries anywhere in the public profile catalog."""
import argparse
import subprocess
import sys
from pathlib import Path


def validate_catalog(root: Path) -> list[str]:
    directory = root / 'profiles'
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('profiles must be a regular directory')
    profiles = []
    for path in sorted(directory.iterdir()):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'{path}: only regular files are allowed (no subdirectories or symlinks)')
        if path.name == 'README.md':
            continue
        if path.suffix != '.yaml':
            raise ValueError(f'{path}: profiles must use the .yaml extension')
        result = subprocess.run(
            [sys.executable, str(root / 'scripts/resolve-audiowrt-profile.py'),
             str(directory), str(root / 'config/flavors'), path.stem],
            capture_output=True, text=True,
        )
        if result.returncode:
            raise ValueError(f'{path.name}: {result.stderr.strip()}')
        profiles.append(path.stem)
    if not profiles:
        raise ValueError('at least one valid profile is required')
    return profiles


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        print(f'Validated {len(validate_catalog(args.root))} profiles.')
    except (ValueError, OSError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
