#!/usr/bin/env python3
"""Resolve an AudioWRT YAML device profile and its reusable flavor."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
PROFILE_ID = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
VALID_STATUSES = {"reference", "tested", "candidate", "community"}
GITHUB_USER = re.compile(r"^(?!-)(?!.*--)[A-Za-z0-9-]{1,39}(?<!-)$")
PROFILE_KEYS = {
    "schema_version",
    "status",
    "maintainer_github",
    "openwrt_profile",
    "target",
    "subtarget",
    "packages_add",
    "packages_remove",
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_packages(path: Path) -> list[str]:
    if not path.is_file():
        fail(f"missing flavor package file: {path}")
    packages = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if len(packages) != len(set(packages)):
        fail(f"duplicate package in {path}")
    for package in packages:
        if not IDENTIFIER.fullmatch(package):
            fail(f"invalid package name {package!r} in {path}")
    return packages


def read_profile_yaml(path: Path) -> dict[str, object]:
    """Read the intentionally small, safe YAML subset used by profile files."""
    data: dict[str, object] = {}
    current_list: str | None = None
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        if raw_line.startswith("  - "):
            if current_list is None:
                fail(f"unexpected YAML list item at {path}:{number}")
            item = raw_line[4:].strip()
            if not item or ":" in item or "#" in item:
                fail(f"invalid package list item at {path}:{number}")
            assert isinstance(data[current_list], list)
            data[current_list].append(item)
            continue
        if raw_line[0].isspace() or ":" not in raw_line:
            fail(f"invalid top-level YAML entry at {path}:{number}")
        key, raw_value = raw_line.split(":", 1)
        key, raw_value = key.strip(), raw_value.strip()
        if key not in PROFILE_KEYS:
            fail(f"unknown profile key {key!r} at {path}:{number}")
        if key in data:
            fail(f"duplicate profile key {key!r} at {path}:{number}")
        if not raw_value:
            if key not in {"packages_add", "packages_remove"}:
                fail(f"empty scalar value at {path}:{number}")
            data[key] = []
            current_list = key
        elif raw_value == "[]":
            data[key] = []
            current_list = None
        elif key == "schema_version" and raw_value.isdigit():
            data[key] = int(raw_value)
            current_list = None
        else:
            if "#" in raw_value:
                fail(f"inline YAML comments are not supported at {path}:{number}")
            data[key] = raw_value
            current_list = None
    missing = sorted(PROFILE_KEYS - data.keys())
    if missing:
        fail(f"missing profile keys in {path}: {', '.join(missing)}")
    return data


def require_string(value: object, field: str, pattern: re.Pattern[str] = IDENTIFIER) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        fail(f"{field} must be a valid identifier")
    return value


def package_list(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"{field} must be an array of package names")
    if len(value) != len(set(value)):
        fail(f"{field} contains duplicate packages")
    for package in value:
        if not IDENTIFIER.fullmatch(package):
            fail(f"invalid package name {package!r} in {field}")
    return value


def merge(base: list[str], additions: list[str], removals: list[str]) -> list[str]:
    result = [package for package in base if package not in removals]
    for package in additions:
        if package not in result:
            result.append(package)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profiles_dir", type=Path)
    parser.add_argument("flavors_dir", type=Path)
    parser.add_argument("profile_id")
    args = parser.parse_args()

    if not PROFILE_ID.fullmatch(args.profile_id):
        fail("profile ID must contain only lowercase letters, digits, dots and hyphens")

    profile_path = args.profiles_dir / f"{args.profile_id}.yaml"
    if not profile_path.is_file():
        available = sorted(path.stem for path in args.profiles_dir.glob("*.yaml"))
        suffix = f" Available profiles: {', '.join(available)}" if available else ""
        fail(f"unknown AudioWRT profile: {args.profile_id}.{suffix}")

    data = read_profile_yaml(profile_path)
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        fail("profile schema_version must be 1")
    version_match = re.search(r"-(snapshot|\d+\.\d+\.\d+)$", args.profile_id)
    if not version_match:
        fail("profile ID must end with an OpenWrt release or -snapshot")
    openwrt_version = version_match.group(1)
    without_version = args.profile_id[: version_match.start()]
    flavor = next(
        (candidate for candidate in ("minimal", "standard", "full") if without_version.endswith(f"-{candidate}")),
        None,
    )
    if flavor is None:
        fail("profile ID must contain a minimal, standard or full flavor before its version")
    device_id = without_version[: -(len(flavor) + 1)]
    require_string(device_id, "device ID", PROFILE_ID)
    openwrt_source = "snapshot" if openwrt_version == "snapshot" else "release"

    status = data.get("status")
    if status not in VALID_STATUSES:
        fail(f"status must be one of: {', '.join(sorted(VALID_STATUSES))}")
    maintainer_github = data.get("maintainer_github")
    if not isinstance(maintainer_github, str) or not GITHUB_USER.fullmatch(maintainer_github):
        fail("maintainer_github must be a valid GitHub username without @")

    openwrt_profile = require_string(data.get("openwrt_profile"), "openwrt_profile")
    target = require_string(data.get("target"), "target")
    subtarget = require_string(data.get("subtarget"), "subtarget")

    device_add = package_list(data.get("packages_add"), "packages_add")
    device_remove = package_list(data.get("packages_remove"), "packages_remove")
    overlap = sorted(set(device_add) & set(device_remove))
    if overlap:
        fail(f"device package overrides both add and remove: {', '.join(overlap)}")

    flavor_dir = args.flavors_dir / flavor
    flavor_add = read_packages(flavor_dir / "packages.add")
    flavor_remove = read_packages(flavor_dir / "packages.remove")
    flavor_overlap = sorted(set(flavor_add) & set(flavor_remove))
    if flavor_overlap:
        fail(f"flavor {flavor} both adds and removes: {', '.join(flavor_overlap)}")

    resolved_add = merge(flavor_add, device_add, device_remove)
    resolved_remove = merge(flavor_remove, device_remove, device_add)
    overlap = sorted(set(resolved_add) & set(resolved_remove))
    if overlap:
        fail(f"resolved profile both adds and removes: {', '.join(overlap)}")

    json.dump(
        {
            "schema_version": 1,
            "id": args.profile_id,
            "device": device_id,
            "status": status,
            "maintainer_github": maintainer_github,
            "flavor": flavor,
            "openwrt_source": openwrt_source,
            "openwrt_version": openwrt_version,
            "openwrt_profile": openwrt_profile,
            "target": target,
            "subtarget": subtarget,
            "packages_add": resolved_add,
            "packages_remove": resolved_remove,
        },
        sys.stdout,
        indent=2,
        sort_keys=True,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
