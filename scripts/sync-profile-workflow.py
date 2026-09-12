#!/usr/bin/env python3
"""Keep the GitHub Actions profile dropdown in sync with profile YAML files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


BEGIN = "          # BEGIN GENERATED PROFILE OPTIONS"
END = "          # END GENERATED PROFILE OPTIONS"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    workflow = root / ".github/workflows/build-audiowrt.yml"
    profiles = sorted(path.stem for path in (root / "profiles").glob("*.yaml"))
    if not profiles:
        raise SystemExit("ERROR: no AudioWRT YAML profiles found")

    text = workflow.read_text(encoding="utf-8")
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise SystemExit("ERROR: generated profile option markers are missing or duplicated")
    before, remainder = text.split(BEGIN, 1)
    _, after = remainder.split(END, 1)
    generated = BEGIN + "\n" + "\n".join(f"          - {profile}" for profile in profiles) + "\n" + END
    expected = before + generated + after

    if args.check:
        if text != expected:
            print("ERROR: GitHub Actions profile choices are stale.", file=sys.stderr)
            print("Run: python3 scripts/sync-profile-workflow.py", file=sys.stderr)
            return 1
        print(f"GitHub Actions profile choices match {len(profiles)} YAML profiles.")
        return 0

    workflow.write_text(expected, encoding="utf-8")
    print(f"Updated GitHub Actions with {len(profiles)} profile choices.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
