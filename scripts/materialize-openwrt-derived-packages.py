#!/usr/bin/env python3
"""Materialize AudioWRT derived packages from the selected OpenWrt source context.

The canonical OpenWrt package directory is copied from the exact SDK/feed
selected by the profile. Its source metadata, files and patches stay intact.
Only the recipe body and explicit AudioWRT overlays are supplied by the
AudioWRT package feed.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

PACKAGE_MK = re.compile(r"^\s*include\s+\$\(INCLUDE_DIR\)/package\.mk\s*$")


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ERROR: {message}")


def release_family(version: str) -> str:
    if version == "snapshot":
        return "snapshot"
    match = re.fullmatch(r"(\d+)\.(\d+)(?:\.\d+)?", version)
    if not match:
        fail(f"unsupported OpenWrt version for derived packages: {version}")
    return f"{match.group(1)}.{match.group(2)}"


def parse_manifest(path: Path):
    rows = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = raw.split("|")
        if len(parts) != 5:
            fail(f"{path}:{number}: expected 5 pipe-separated fields")
        package, strategy, origin, canonical_path, delta_dir = (p.strip() for p in parts)
        rows.append((package, strategy, origin, canonical_path, delta_dir))
    return rows


def copy_overlay(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    for item in source.rglob("*"):
        if item.is_dir():
            continue
        relative = item.relative_to(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)


def select_tail(delta: Path, family: str) -> Path:
    release_tail = delta / "releases" / family / "Makefile.tail"
    common_tail = delta / "Makefile.tail"
    if release_tail.is_file():
        return release_tail
    if common_tail.is_file():
        return common_tail
    fail(f"derived package delta has no Makefile.tail: {delta}")


def canonical_preamble(makefile: Path) -> str:
    lines = makefile.read_text(encoding="utf-8").splitlines(keepends=True)
    for index, line in enumerate(lines):
        if PACKAGE_MK.match(line.rstrip("\n")):
            return "".join(lines[:index]).rstrip() + "\n"
    fail(f"canonical package Makefile has no package.mk include: {makefile}")


def materialize(
    sdk: Path,
    feed: Path,
    origin: str,
    canonical_path: str,
    delta_name: str,
    family: str,
    output_root: Path,
):
    if origin == "base":
        canonical = sdk / canonical_path
    elif origin == "packages":
        canonical = sdk / "feeds" / "packages" / canonical_path
    else:
        fail(f"unsupported derived package origin {origin!r} for {delta_name}")

    if not (canonical / "Makefile").is_file():
        fail(f"canonical OpenWrt package is missing: {canonical}")

    delta = feed / delta_name
    if not delta.is_dir():
        fail(f"AudioWRT delta directory is missing: {delta}")
    if (delta / "Makefile").exists():
        fail(
            f"{delta_name} still contains a standalone Makefile; derived packages "
            "must contain only Makefile.tail/overlays"
        )

    tail = select_tail(delta, family)
    destination = output_root / delta_name
    shutil.rmtree(destination, ignore_errors=True)
    shutil.copytree(canonical, destination, symlinks=True)

    canonical_makefile = canonical / "Makefile"
    generated_makefile = destination / "Makefile"
    generated_makefile.write_text(
        canonical_preamble(canonical_makefile)
        + "\n# ---- AudioWRT release-derived recipe body ----\n"
        + f"# Canonical package: {origin}:{canonical_path}\n"
        + f"# AudioWRT delta: {delta_name} ({family})\n\n"
        + tail.read_text(encoding="utf-8").lstrip(),
        encoding="utf-8",
    )

    # Runtime/configuration files are an overlay. Unchanged canonical OpenWrt
    # files remain release-specific because they came from the copied package.
    copy_overlay(delta / "files", destination / "files")
    copy_overlay(delta / "releases" / family / "files", destination / "files")

    # Source patches are additive AudioWRT-only deltas. Upstream OpenWrt patches
    # are already present in the copied canonical package directory.
    for patch_dir in (delta / "patches", delta / "releases" / family / "patches"):
        if not patch_dir.is_dir():
            continue
        for patch in patch_dir.iterdir():
            if not patch.is_file():
                continue
            if not re.match(r"9\d\d-", patch.name):
                fail(
                    f"AudioWRT patch {patch} must use the 9xx namespace; "
                    "OpenWrt-owned patches must not be copied into the feed"
                )
            target = destination / "patches" / patch.name
            if target.exists():
                fail(f"AudioWRT patch collides with canonical OpenWrt patch: {target}")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(patch, target)

    digest = hashlib.sha256(canonical_makefile.read_bytes()).hexdigest()
    metadata = {
        "strategy": "openwrt-derived",
        "origin": origin,
        "canonical_path": canonical_path,
        "canonical_makefile_sha256": digest,
        "delta": delta_name,
        "release_family": family,
        "tail": str(tail.relative_to(feed)),
    }
    (destination / ".audiowrt-origin.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return metadata


def main() -> int:
    if len(sys.argv) != 7:
        print(
            "usage: materialize-openwrt-derived-packages.py "
            "<sdk> <audiowrt-feed> <manifest> <openwrt-version> <output-root> <metadata-json>",
            file=sys.stderr,
        )
        return 2

    sdk, feed, manifest, version, output_root, metadata_file = map(Path, sys.argv[1:])
    family = release_family(version.name if version.name == "snapshot" else str(version))
    # `version` is passed as a string argument; Path is used only by the compact
    # argument unpack above, so recover the literal representation here.
    version_literal = sys.argv[4]
    family = release_family(version_literal)

    rows = parse_manifest(manifest)
    derived = {}
    for package, strategy, origin, canonical_path, delta_dir in rows:
        if strategy != "openwrt-derived":
            continue
        if not all((origin, canonical_path, delta_dir)):
            fail(f"openwrt-derived package {package} has incomplete provenance")
        key = delta_dir
        definition = (origin, canonical_path)
        if key in derived and derived[key] != definition:
            fail(f"derived delta {key} maps to multiple canonical packages")
        derived[key] = definition

    output_root.mkdir(parents=True, exist_ok=True)
    result = {}
    for delta_name, (origin, canonical_path) in sorted(derived.items()):
        result[delta_name] = materialize(
            sdk, feed, origin, canonical_path, delta_name, family, output_root
        )
        print(f"Materialized {delta_name} from {origin}:{canonical_path} ({family})")

    metadata_file.parent.mkdir(parents=True, exist_ok=True)
    metadata_file.write_text(
        json.dumps(
            {"openwrt_version": version_literal, "release_family": family, "packages": result},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
