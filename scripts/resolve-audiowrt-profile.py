#!/usr/bin/env python3
"""Resolve an AudioWRT YAML device profile and composable flavor files."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
PROFILE_ID = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
VALID_STATUSES = {"reference", "tested", "candidate", "community"}
GITHUB_USER = re.compile(r"^(?!-)(?!.*--)[A-Za-z0-9-]{1,39}(?<!-)$")
PROFILE_KEYS = {
    "schema_version", "status", "maintainer_github", "openwrt_profile",
    "target", "subtarget", "squashfs_block_size", "packages_add", "packages_remove",
}
FLAVOR_KEYS = {"schema_version", "include", "packages_add", "packages_remove"}
FLAVOR_FRAGMENTS = {"common", "minimal"}
LEGACY_FLAVOR_ALIASES = {
    "minimal-usb-bluetooth-audio": "minimal-usb-audio-bluetooth",
    "usb-bluetooth-audio": "usb-audio-bluetooth",
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_small_yaml(path: Path, allowed_keys: set[str], list_keys: set[str]) -> dict[str, object]:
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
                fail(f"invalid YAML list item at {path}:{number}")
            assert isinstance(data[current_list], list)
            data[current_list].append(item)
            continue
        if raw_line[0].isspace() or ":" not in raw_line:
            fail(f"invalid top-level YAML entry at {path}:{number}")
        key, raw_value = raw_line.split(":", 1)
        key, raw_value = key.strip(), raw_value.strip()
        if key not in allowed_keys:
            fail(f"unknown key {key!r} at {path}:{number}")
        if key in data:
            fail(f"duplicate key {key!r} at {path}:{number}")
        if not raw_value:
            if key not in list_keys:
                fail(f"empty scalar value at {path}:{number}")
            data[key] = []
            current_list = key
        elif raw_value == "[]":
            if key not in list_keys:
                fail(f"{key} cannot be an array at {path}:{number}")
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
    return data


def read_profile_yaml(path: Path) -> dict[str, object]:
    data = read_small_yaml(path, PROFILE_KEYS, {"packages_add", "packages_remove"})
    missing = sorted((PROFILE_KEYS - {"squashfs_block_size"}) - data.keys())
    if missing:
        fail(f"missing profile keys in {path}: {', '.join(missing)}")
    return data


def require_string(value: object, field: str, pattern: re.Pattern[str] = IDENTIFIER) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        fail(f"{field} must be a valid identifier")
    return value


def identifier_list(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"{field} must be an array")
    if len(value) != len(set(value)):
        fail(f"{field} contains duplicates")
    for item in value:
        if not IDENTIFIER.fullmatch(item):
            fail(f"invalid identifier {item!r} in {field}")
    return value


def package_list(value: object, field: str) -> list[str]:
    return identifier_list(value, field)


def append_unique(target: list[str], values: list[str]) -> None:
    for value in values:
        if value not in target:
            target.append(value)


def apply_override(base_add: list[str], base_remove: list[str], own_add: list[str], own_remove: list[str]) -> tuple[list[str], list[str]]:
    add = [p for p in base_add if p not in own_remove]
    remove = [p for p in base_remove if p not in own_add]
    append_unique(add, own_add)
    append_unique(remove, own_remove)
    return add, remove


def read_flavor(path: Path) -> tuple[list[str], list[str], list[str]]:
    if not path.is_file():
        fail(f"missing flavor file: {path}")
    data = read_small_yaml(path, FLAVOR_KEYS, {"include", "packages_add", "packages_remove"})
    if data.get("schema_version") != 1:
        fail(f"flavor schema_version must be 1 in {path}")
    missing = sorted(FLAVOR_KEYS - data.keys())
    if missing:
        fail(f"missing flavor keys in {path}: {', '.join(missing)}")
    includes = identifier_list(data.get("include"), f"{path}:include")
    add = package_list(data.get("packages_add"), f"{path}:packages_add")
    remove = package_list(data.get("packages_remove"), f"{path}:packages_remove")
    overlap = sorted(set(add) & set(remove))
    if overlap:
        fail(f"flavor {path.stem} directly adds and removes: {', '.join(overlap)}")
    return includes, add, remove


def resolve_flavor(flavors_dir: Path, name: str, stack: tuple[str, ...] = ()) -> tuple[list[str], list[str]]:
    if name in stack:
        fail(f"flavor include cycle: {' -> '.join((*stack, name))}")
    includes, own_add, own_remove = read_flavor(flavors_dir / f"{name}.yaml")
    inherited_add: list[str] = []
    inherited_remove: list[str] = []
    for include in includes:
        inc_add, inc_remove = resolve_flavor(flavors_dir, include, (*stack, name))
        append_unique(inherited_add, inc_add)
        append_unique(inherited_remove, inc_remove)

    resolved_add, resolved_remove = apply_override(inherited_add, inherited_remove, own_add, own_remove)
    overlap = sorted(set(resolved_add) & set(resolved_remove))
    if overlap:
        fail(
            f"flavor {name} inherits conflicting package directives: {', '.join(overlap)}; "
            "resolve each conflict explicitly in this flavor's packages_add or packages_remove"
        )
    return resolved_add, resolved_remove


def infer_flavor(flavors_dir: Path, without_version: str) -> tuple[str, str]:
    selectable = sorted(
        (path.stem for path in flavors_dir.glob("*.yaml") if path.stem not in FLAVOR_FRAGMENTS),
        key=len,
        reverse=True,
    )
    candidates = [(name, name) for name in selectable]
    candidates.extend((legacy, canonical) for legacy, canonical in LEGACY_FLAVOR_ALIASES.items() if canonical in selectable)
    candidates.sort(key=lambda pair: len(pair[0]), reverse=True)
    for token, canonical in candidates:
        if without_version.endswith(f"-{token}"):
            device_id = without_version[: -(len(token) + 1)]
            require_string(device_id, "device ID", PROFILE_ID)
            return canonical, device_id
    fail("profile ID must contain a selectable flavor before its version")


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
    if data.get("schema_version") != 1:
        fail("profile schema_version must be 1")

    version_match = re.search(r"-(snapshot|\d+\.\d+\.\d+)$", args.profile_id)
    if not version_match:
        fail("profile ID must end with an OpenWrt release or -snapshot")
    openwrt_version = version_match.group(1)
    without_version = args.profile_id[: version_match.start()]
    flavor, device_id = infer_flavor(args.flavors_dir, without_version)
    openwrt_source = "snapshot" if openwrt_version == "snapshot" else "release"

    status = data.get("status")
    if not isinstance(status, str) or status not in VALID_STATUSES:
        fail(f"status must be one of: {', '.join(sorted(VALID_STATUSES))}")
    maintainer_github = data.get("maintainer_github")
    if not isinstance(maintainer_github, str) or not GITHUB_USER.fullmatch(maintainer_github):
        fail("maintainer_github must be a valid GitHub username without @")

    openwrt_profile = require_string(data.get("openwrt_profile"), "openwrt_profile")
    target = require_string(data.get("target"), "target")
    subtarget = require_string(data.get("subtarget"), "subtarget")
    squashfs_block_size = data.get("squashfs_block_size", "default")
    if not isinstance(squashfs_block_size, str) or squashfs_block_size not in {"default", "256", "512", "1024"}:
        fail("squashfs_block_size must be default, 256, 512 or 1024")

    device_add = package_list(data.get("packages_add"), "packages_add")
    device_remove = package_list(data.get("packages_remove"), "packages_remove")
    overlap = sorted(set(device_add) & set(device_remove))
    if overlap:
        fail(f"device package overrides both add and remove: {', '.join(overlap)}")

    flavor_add, flavor_remove = resolve_flavor(args.flavors_dir, flavor)
    resolved_add, resolved_remove = apply_override(flavor_add, flavor_remove, device_add, device_remove)
    overlap = sorted(set(resolved_add) & set(resolved_remove))
    if overlap:
        fail(f"resolved profile both adds and removes: {', '.join(overlap)}")

    json.dump({
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
        "squashfs_block_size": squashfs_block_size,
        "packages_add": resolved_add,
        "packages_remove": resolved_remove,
    }, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
