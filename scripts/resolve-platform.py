#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: resolve-platform.py <tmp/.targetinfo> <platform>")

    metadata_path = Path(sys.argv[1])
    platform = sys.argv[2]
    wanted_profile = f"DEVICE_{platform}"

    if not metadata_path.is_file():
        fail(f"OpenWrt target metadata not found: {metadata_path}")

    current_target = None
    current_default_packages = []
    current_profile = None
    current_profile_name = None
    current_profile_packages = []
    matches = []
    all_profiles = []

    def flush_profile() -> None:
        nonlocal current_profile, current_profile_name, current_profile_packages
        if current_profile:
            all_profiles.append(current_profile.removeprefix("DEVICE_"))
            if current_profile == wanted_profile and current_target:
                if "/" in current_target:
                    target, subtarget = current_target.split("/", 1)
                else:
                    target, subtarget = current_target, "generic"
                matches.append(
                    {
                        "platform": platform,
                        "profile_id": current_profile,
                        "name": current_profile_name or platform,
                        "target": target,
                        "subtarget": subtarget,
                        "target_id": current_target,
                        "profile_packages": sorted(set(current_profile_packages)),
                        "default_packages": sorted(set(current_default_packages)),
                    }
                )
        current_profile = None
        current_profile_name = None
        current_profile_packages = []

    for raw_line in metadata_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if line.startswith("Target: "):
            flush_profile()
            current_target = line.split(":", 1)[1].strip()
            current_default_packages = []
        elif line.startswith("Default-Packages: "):
            current_default_packages = line.split(":", 1)[1].strip().split()
        elif line.startswith("Target-Profile: "):
            flush_profile()
            current_profile = line.split(":", 1)[1].strip()
        elif line.startswith("Target-Profile-Name: ") and current_profile:
            current_profile_name = line.split(":", 1)[1].strip()
        elif line.startswith("Target-Profile-Packages: ") and current_profile:
            current_profile_packages = line.split(":", 1)[1].strip().split()
        elif line == "@@":
            flush_profile()

    flush_profile()

    if not matches:
        needle = platform.lower()
        suggestions = sorted({p for p in all_profiles if needle in p.lower()})[:10]
        hint = ""
        if suggestions:
            hint = " Similar OpenWrt profiles: " + ", ".join(suggestions)
        fail(f"platform '{platform}' was not found in this OpenWrt ref.{hint}")

    if len(matches) > 1:
        locations = ", ".join(m["target_id"] for m in matches)
        fail(f"platform '{platform}' is ambiguous across OpenWrt targets: {locations}")

    json.dump(matches[0], sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
