#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        print("usage: image-size-report.py <artifact-dir> <report.json> <report.txt>", file=sys.stderr)
        raise SystemExit(2)

    artifact_dir = Path(sys.argv[1])
    json_path = Path(sys.argv[2])
    text_path = Path(sys.argv[3])

    suffixes = (".bin", ".img", ".img.gz", ".ubi", ".itb")
    images = []
    for path in sorted(artifact_dir.iterdir()):
        if not path.is_file() or not path.name.endswith(suffixes):
            continue
        size = path.stat().st_size
        images.append(
            {
                "file": path.name,
                "bytes": size,
                "mib": round(size / 1024 / 1024, 3),
            }
        )

    result = {"images": images}
    json_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    lines = ["AudioWRT image size report", ""]
    if not images:
        lines.append("No firmware image files were found.")
    else:
        for image in images:
            lines.append(f"{image['file']}: {image['bytes']} bytes ({image['mib']:.3f} MiB)")
    lines.extend(
        [
            "",
            "OpenWrt performs the authoritative device image-size check during the build.",
            "If a selected feature set exceeds the device image limit, the build fails instead of producing an oversized image.",
        ]
    )
    text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    if not images:
        print(
            "ERROR: ImageBuilder completed without producing any firmware image files.",
            file=sys.stderr,
        )
        raise SystemExit(3)


if __name__ == "__main__":
    main()
