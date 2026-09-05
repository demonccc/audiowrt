#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import json
import sys
from pathlib import Path


def load_list(path: Path) -> list[str]:
    values = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            values.append(line)
    return values


def main() -> None:
    if len(sys.argv) != 3:
        print("ERROR: usage: check-usb.py <platform.json> <usb-host-packages>", file=sys.stderr)
        raise SystemExit(2)

    metadata_path = Path(sys.argv[1])
    allowlist_path = Path(sys.argv[2])

    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    profile_packages = set(metadata.get("profile_packages", []))
    usb_host_packages = set(load_list(allowlist_path))
    detected = sorted(profile_packages & usb_host_packages)

    print(f"Platform: {metadata['platform']}")
    print(f"OpenWrt target: {metadata['target_id']}")
    print(f"Device: {metadata['name']}")

    if not detected:
        print(
            "ERROR: USB host capability could not be confirmed from the selected "
            "OpenWrt device profile.",
            file=sys.stderr,
        )
        print(
            "AudioWRT requires a usable USB host interface and refuses to build "
            "when USB support is missing or unknown.",
            file=sys.stderr,
        )
        print(
            "Resolved device packages: "
            + (" ".join(sorted(profile_packages)) if profile_packages else "<none>"),
            file=sys.stderr,
        )
        raise SystemExit(3)

    print("USB host capability: confirmed")
    print("USB evidence: " + " ".join(detected))


if __name__ == "__main__":
    main()
