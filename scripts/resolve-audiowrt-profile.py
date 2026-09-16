#!/usr/bin/env python3
"""Resolve an AudioWRT device profile and its package groups."""

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
    "target", "subtarget", "squashfs_block_size", "package_groups",
    "packages_add", "packages_remove",
}
GROUP_KEYS = {"schema_version", "packages_add", "packages_remove"}


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


def identifier_list(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"{field} must be an array")
    if len(value) != len(set(value)):
        fail(f"{field} contains duplicates")
    for item in value:
        if not IDENTIFIER.fullmatch(item):
            fail(f"invalid identifier {item!r} in {field}")
    return value


def read_profile(path: Path) -> dict[str, object]:
    data = read_small_yaml(path, PROFILE_KEYS, {"package_groups", "packages_add", "packages_remove"})
    missing = sorted((PROFILE_KEYS - {"squashfs_block_size"}) - data.keys())
    if missing:
        fail(f"missing profile keys in {path}: {', '.join(missing)}")
    if data.get("schema_version") != 1:
        fail("profile schema_version must be 1")
    return data


def read_group(path: Path) -> tuple[list[str], list[str]]:
    if not path.is_file():
        fail(f"missing package group: {path.stem}")
    data = read_small_yaml(path, GROUP_KEYS, {"packages_add", "packages_remove"})
    if data.get("schema_version") != 1:
        fail(f"package group schema_version must be 1 in {path}")
    missing = sorted(GROUP_KEYS - data.keys())
    if missing:
        fail(f"missing package group keys in {path}: {', '.join(missing)}")
    add = identifier_list(data.get("packages_add"), f"{path}:packages_add")
    remove = identifier_list(data.get("packages_remove"), f"{path}:packages_remove")
    overlap = sorted(set(add) & set(remove))
    if overlap:
        fail(f"package group {path.stem} both adds and removes: {', '.join(overlap)}")
    return add, remove


def apply_overlay(base_add: list[str], base_remove: list[str], add: list[str], remove: list[str]) -> tuple[list[str], list[str]]:
    resolved_add = [p for p in base_add if p not in remove]
    resolved_remove = [p for p in base_remove if p not in add]
    for package in add:
        if package not in resolved_add:
            resolved_add.append(package)
    for package in remove:
        if package not in resolved_remove:
            resolved_remove.append(package)
    return resolved_add, resolved_remove


def require_string(value: object, field: str, pattern: re.Pattern[str] = IDENTIFIER) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        fail(f"{field} must be a valid identifier")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profiles_dir", type=Path)
    parser.add_argument("groups_dir", type=Path)
    parser.add_argument("profile_id")
    args = parser.parse_args()

    if not PROFILE_ID.fullmatch(args.profile_id):
        fail("profile ID must contain only lowercase letters, digits, dots and hyphens")

    profile_path = args.profiles_dir / f"{args.profile_id}.yaml"
    if not profile_path.is_file():
        available = sorted(path.stem for path in args.profiles_dir.glob("*.yaml"))
        suffix = f" Available profiles: {', '.join(available)}" if available else ""
        fail(f"unknown AudioWRT profile: {args.profile_id}.{suffix}")

    data = read_profile(profile_path)
    version_match = re.search(r"-(snapshot|\d+\.\d+\.\d+)$", args.profile_id)
    if not version_match:
        fail("profile ID must end with an OpenWrt release or -snapshot")
    openwrt_version = version_match.group(1)
    openwrt_source = "snapshot" if openwrt_version == "snapshot" else "release"

    status = data.get("status")
    if not isinstance(status, str) or status not in VALID_STATUSES:
        fail(f"status must be one of: {', '.join(sorted(VALID_STATUSES))}")
    maintainer = data.get("maintainer_github")
    if not isinstance(maintainer, str) or not GITHUB_USER.fullmatch(maintainer):
        fail("maintainer_github must be a valid GitHub username without @")

    groups = identifier_list(data.get("package_groups"), "package_groups")
    if "common" in groups:
        fail("common is applied automatically and must not be listed in package_groups")

    resolved_add: list[str] = []
    resolved_remove: list[str] = []
    for group_name in ["common", *groups]:
        group_add, group_remove = read_group(args.groups_dir / f"{group_name}.yaml")
        resolved_add, resolved_remove = apply_overlay(resolved_add, resolved_remove, group_add, group_remove)

    profile_add = identifier_list(data.get("packages_add"), "packages_add")
    profile_remove = identifier_list(data.get("packages_remove"), "packages_remove")
    overlap = sorted(set(profile_add) & set(profile_remove))
    if overlap:
        fail(f"profile both adds and removes: {', '.join(overlap)}")
    resolved_add, resolved_remove = apply_overlay(resolved_add, resolved_remove, profile_add, profile_remove)

    squashfs_block_size = data.get("squashfs_block_size", "default")
    if not isinstance(squashfs_block_size, str) or squashfs_block_size not in {"default", "256", "512", "1024"}:
        fail("squashfs_block_size must be default, 256, 512 or 1024")

    json.dump({
        "schema_version": 1,
        "id": args.profile_id,
        "status": status,
        "maintainer_github": maintainer,
        "package_groups": groups,
        "openwrt_source": openwrt_source,
        "openwrt_version": openwrt_version,
        "openwrt_profile": require_string(data.get("openwrt_profile"), "openwrt_profile"),
        "target": require_string(data.get("target"), "target"),
        "subtarget": require_string(data.get("subtarget"), "subtarget"),
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
