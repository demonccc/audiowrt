#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import json
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: resolve-features.py <features.map> <features>")

    map_path = Path(sys.argv[1])
    requested_raw = sys.argv[2].strip()
    if not map_path.is_file():
        fail(f"feature map not found: {map_path}")

    catalog = []
    seen = set()
    for number, raw_line in enumerate(map_path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("|", 2)
        if len(fields) != 3 or not all(fields):
            fail(f"invalid feature-map entry on line {number}")
        feature, package, description = fields
        if feature in seen:
            fail(f"duplicate feature in map: {feature}")
        seen.add(feature)
        catalog.append({"id": feature, "package": package, "description": description})

    tokens = [token for token in re.split(r"[\s,]+", requested_raw) if token]
    if "all" in tokens:
        if len(tokens) != 1:
            fail("FEATURES=all cannot be combined with other feature names")
        selected_ids = {entry["id"] for entry in catalog}
    else:
        selected_ids = set(tokens)

    known = {entry["id"] for entry in catalog}
    unknown = sorted(selected_ids - known)
    if unknown:
        fail("unknown AudioWRT feature(s): " + ", ".join(unknown))

    selected = [entry for entry in catalog if entry["id"] in selected_ids]
    result = {
        "requested": requested_raw,
        "features": selected,
        "packages": [entry["package"] for entry in selected],
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
