#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def tree_bytes(root: Path) -> int:
    total = 0
    if not root.exists():
        return total
    for base, dirs, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        for name in files:
            path = base_path / name
            try:
                total += path.lstat().st_size
            except OSError:
                pass
        for name in dirs:
            path = base_path / name
            if path.is_symlink():
                try:
                    total += path.lstat().st_size
                except OSError:
                    pass
    return total


def extract_payload_bytes(apk_bin: Path, apk_path: Path) -> int:
    with tempfile.TemporaryDirectory(prefix="audiowrt-apk-size-") as directory:
        destination = Path(directory)
        result = subprocess.run(
            [
                str(apk_bin),
                "--allow-untrusted",
                "extract",
                "--destination",
                str(destination),
                str(apk_path),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"apk extract failed for {apk_path.name}")
        return tree_bytes(destination)


def find_rootfs(imagebuilder: Path):
    candidates = []
    for path in imagebuilder.glob("build_dir/target-*/root-*"):
        if not path.is_dir():
            continue
        score = 0
        if (path / "lib/apk").exists():
            score += 4
        if (path / "etc/openwrt_release").exists():
            score += 2
        if (path / "usr").exists():
            score += 1
        candidates.append((score, path))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (item[0], str(item[1])), reverse=True)
    return candidates[0][1]


def find_squashfs(imagebuilder: Path):
    candidates = [
        path for path in imagebuilder.glob("build_dir/target-*/linux-*/root.squashfs")
        if path.is_file()
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime_ns)


def parse_query_json(text: str):
    text = text.strip()
    if not text:
        return []
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        rows = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                return []
            if isinstance(item, dict):
                rows.append(item)
        return rows

    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        for key in ("packages", "results", "items"):
            value = data.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
        if "name" in data:
            return [data]
    return []


def parse_human_size(text: str):
    matches = re.findall(
        r"(?im)^\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|KB|MB|GB)\s*$",
        text,
    )
    if not matches:
        return None
    value, unit = matches[-1]
    scale = {
        "B": 1,
        "KiB": 1024,
        "MiB": 1024 ** 2,
        "GiB": 1024 ** 3,
        "KB": 1000,
        "MB": 1000 ** 2,
        "GB": 1000 ** 3,
    }[unit]
    return int(float(value) * scale)


def installed_packages(apk_bin: Path, rootfs: Path):
    query = subprocess.run(
        [
            str(apk_bin),
            "--root",
            str(rootfs),
            "query",
            "--from",
            "installed",
            "--format",
            "json",
            "--fields",
            "name,version,installed-size",
            "*",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if query.returncode == 0:
        rows = parse_query_json(query.stdout)
        normalized = []
        for row in rows:
            name = row.get("name")
            version = row.get("version", "")
            size = row.get("installed-size")
            if name and isinstance(size, int):
                normalized.append(
                    {"name": str(name), "version": str(version), "installed_bytes": size}
                )
        if normalized:
            return normalized

    manifest = subprocess.run(
        [str(apk_bin), "--root", str(rootfs), "list", "--installed", "--manifest"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if manifest.returncode != 0:
        raise RuntimeError(manifest.stderr.strip() or "unable to list installed packages")

    result = []
    for line in manifest.stdout.splitlines():
        parts = line.split()
        if not parts:
            continue
        name = parts[0]
        version = parts[1] if len(parts) > 1 else ""
        info = subprocess.run(
            [str(apk_bin), "--root", str(rootfs), "info", "--size", name],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        size = parse_human_size(info.stdout) if info.returncode == 0 else None
        result.append(
            {"name": name, "version": version, "installed_bytes": size}
        )
    return result


def human_bytes(value):
    if value is None:
        return "-"
    value = int(value)
    if value < 1024:
        return f"{value} B"
    if value < 1024 ** 2:
        return f"{value / 1024:.1f} KiB"
    return f"{value / 1024 ** 2:.2f} MiB"


def render_table(rows, columns):
    widths = []
    for key, title, formatter in columns:
        width = len(title)
        for row in rows:
            width = max(width, len(formatter(row.get(key))))
        widths.append(width)

    header = "  ".join(
        title.ljust(widths[index])
        for index, (_, title, _) in enumerate(columns)
    )
    separator = "  ".join("-" * width for width in widths)
    lines = [header, separator]
    for row in rows:
        cells = []
        for index, (key, _, formatter) in enumerate(columns):
            text = formatter(row.get(key))
            if key.endswith("bytes"):
                cells.append(text.rjust(widths[index]))
            else:
                cells.append(text.ljust(widths[index]))
        lines.append("  ".join(cells))
    return lines


def main() -> None:
    if len(sys.argv) != 6:
        fail(
            "usage: package-size-report.py "
            "<apk-bin> <local-apks-dir> <imagebuilder-dir> <report.json> <report.txt>"
        )

    apk_bin = Path(sys.argv[1])
    local_apks_dir = Path(sys.argv[2])
    imagebuilder = Path(sys.argv[3])
    json_path = Path(sys.argv[4])
    text_path = Path(sys.argv[5])

    if not apk_bin.is_file():
        fail(f"apk host tool not found: {apk_bin}")

    local_packages = []
    for apk_path in sorted(local_apks_dir.glob("*.apk")):
        try:
            payload_bytes = extract_payload_bytes(apk_bin, apk_path)
            error = None
        except RuntimeError as exc:
            payload_bytes = None
            error = str(exc)
        local_packages.append(
            {
                "file": apk_path.name,
                "apk_bytes": apk_path.stat().st_size,
                "payload_bytes": payload_bytes,
                "error": error,
            }
        )

    rootfs = find_rootfs(imagebuilder)
    installed = []
    rootfs_bytes = None
    installed_error = None
    if rootfs is not None:
        rootfs_bytes = tree_bytes(rootfs)
        try:
            installed = installed_packages(apk_bin, rootfs)
        except RuntimeError as exc:
            installed_error = str(exc)

    squashfs = find_squashfs(imagebuilder)
    squashfs_bytes = squashfs.stat().st_size if squashfs is not None else None

    local_packages.sort(key=lambda row: row["apk_bytes"], reverse=True)
    installed.sort(
        key=lambda row: (
            row["installed_bytes"] is not None,
            row["installed_bytes"] or 0,
        ),
        reverse=True,
    )

    result = {
        "local_audiowrt_packages": local_packages,
        "local_audiowrt_apk_bytes": sum(row["apk_bytes"] for row in local_packages),
        "local_audiowrt_payload_bytes": sum(
            row["payload_bytes"] or 0 for row in local_packages
        ),
        "rootfs": str(rootfs) if rootfs else None,
        "rootfs_file_bytes": rootfs_bytes,
        "installed_packages": installed,
        "installed_package_bytes": sum(
            row["installed_bytes"] or 0 for row in installed
        ),
        "installed_package_count": len(installed),
        "installed_package_error": installed_error,
        "squashfs": str(squashfs) if squashfs else None,
        "squashfs_bytes": squashfs_bytes,
    }

    json_path.parent.mkdir(parents=True, exist_ok=True)
    text_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    lines = ["AudioWRT package size report", ""]
    lines.append("Local AudioWRT APKs")
    if local_packages:
        lines.extend(
            render_table(
                local_packages,
                [
                    ("file", "APK", lambda value: str(value or "")),
                    ("apk_bytes", "APK size", human_bytes),
                    ("payload_bytes", "Payload", human_bytes),
                ],
            )
        )
        lines.append("")
        lines.append(
            "Local APK total: "
            + human_bytes(result["local_audiowrt_apk_bytes"])
            + " compressed APK / "
            + human_bytes(result["local_audiowrt_payload_bytes"])
            + " extracted payload"
        )
    else:
        lines.append("No local AudioWRT APKs found.")

    lines.extend(["", "Installed image packages"])
    if installed:
        lines.extend(
            render_table(
                installed,
                [
                    ("name", "Package", lambda value: str(value or "")),
                    ("version", "Version", lambda value: str(value or "")),
                    ("installed_bytes", "Installed", human_bytes),
                ],
            )
        )
        lines.append("")
        lines.append(
            f"Installed package total: {human_bytes(result['installed_package_bytes'])} "
            f"across {len(installed)} packages"
        )
    elif installed_error:
        lines.append(f"Unable to read installed package sizes: {installed_error}")
    else:
        lines.append("ImageBuilder rootfs is not available yet.")

    lines.extend(
        [
            "",
            f"Rootfs file bytes: {human_bytes(rootfs_bytes)}",
            f"SquashFS bytes: {human_bytes(squashfs_bytes)}",
            "",
            "Note: SquashFS/XZ compresses files together in blocks, so an exact compressed",
            "byte contribution cannot be assigned to each package. APK size, extracted",
            "payload, installed-size metadata and total SquashFS size are reported separately.",
        ]
    )
    text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
