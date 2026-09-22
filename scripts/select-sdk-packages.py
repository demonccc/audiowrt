#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

"""Re-enable selected AudioWRT package symbols after SDK defconfig."""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <sdk-config> <package> [package ...]", file=sys.stderr)
        return 2

    config_path = Path(sys.argv[1])
    packages = list(dict.fromkeys(sys.argv[2:]))
    selected = {f"CONFIG_PACKAGE_{package}" for package in packages}
    lines = config_path.read_text().splitlines()

    # Remove active and Kconfig-generated disabled forms so each selected
    # package has one authoritative value after dependency pruning.
    lines = [
        line
        for line in lines
        if not any(
            line.startswith(f"{symbol}=") or line == f"# {symbol} is not set"
            for symbol in selected
        )
    ]
    lines.extend(f"{symbol}=m" for symbol in sorted(selected))
    config_path.write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
