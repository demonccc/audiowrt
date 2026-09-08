#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_targets(path: Path):
    targets = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 1)
        if len(parts) != 2 or not all(parts):
            fail(f"invalid package-build-targets entry on line {number}")
        package, target = parts
        if package in targets:
            fail(f"duplicate package-build-targets entry: {package}")
        targets[package] = target
    return targets


def normalize_dependency(token: str) -> str:
    token = token.strip().lstrip("+@")
    if ":" in token:
        token = token.rsplit(":", 1)[1]
    token = token.lstrip("+@")
    return re.split(r"[<>= ]", token, maxsplit=1)[0]


def load_dependencies(path: Path):
    dependencies = {}
    current = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw.startswith("Package:"):
            current = raw.split(":", 1)[1].strip()
            dependencies.setdefault(current, [])
            continue
        if current and raw.startswith("Depends:"):
            value = raw.split(":", 1)[1].strip()
            for token in value.split():
                dependency = normalize_dependency(token)
                if dependency and dependency not in dependencies[current]:
                    dependencies[current].append(dependency)
    return dependencies


def main() -> None:
    if len(sys.argv) < 4:
        fail(
            "usage: resolve-package-build-targets.py "
            "<package-build-targets> <packageinfo> <root> [<root> ...]"
        )

    targets_path = Path(sys.argv[1])
    packageinfo_path = Path(sys.argv[2])
    roots = sys.argv[3:]

    if not targets_path.is_file():
        fail(f"package build target map not found: {targets_path}")
    if not packageinfo_path.is_file():
        fail(f"OpenWrt package metadata not found: {packageinfo_path}")

    targets = load_targets(targets_path)
    dependencies = load_dependencies(packageinfo_path)
    selected = []
    state = {}

    def visit(package: str, chain):
        if package not in targets:
            return
        marker = state.get(package, 0)
        if marker == 2:
            return
        if marker == 1:
            fail("AudioWRT package dependency cycle: " + " -> ".join([*chain, package]))

        state[package] = 1
        for dependency in dependencies.get(package, []):
            visit(dependency, [*chain, package])
        state[package] = 2
        selected.append(package)

    for root in roots:
        visit(root, [])

    if not selected:
        fail("none of the requested firmware packages are AudioWRT-owned build roots")

    for package in selected:
        print(f"{package}|{targets[package]}")


if __name__ == "__main__":
    main()
