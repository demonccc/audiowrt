#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import json
import re
import sys
import urllib.request
from html import unescape
from urllib.parse import urljoin

OPENWRT_DOWNLOADS = "https://downloads.openwrt.org/releases"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def resolve_artifact(base_url: str, release: str, target: str, subtarget: str, artifact: str) -> str:
    try:
        with urllib.request.urlopen(base_url) as response:
            listing = response.read().decode("utf-8")
    except OSError as exc:
        fail(f"could not read OpenWrt downloads directory: {base_url}: {exc}")

    release_re, target_re, subtarget_re = map(re.escape, (release, target, subtarget))
    if artifact == "sdk":
        pattern = rf'href="([^"]*openwrt-sdk-{release_re}-{target_re}-{subtarget_re}_[^"]+\.Linux-x86_64\.tar\.zst)"'
    elif artifact == "imagebuilder":
        pattern = rf'href="([^"]*openwrt-imagebuilder-{release_re}-{target_re}-{subtarget_re}\.Linux-x86_64\.tar\.zst)"'
    else:
        fail(f"unsupported artifact type: {artifact}")

    matches = list(dict.fromkeys(unescape(value) for value in re.findall(pattern, listing)))
    if len(matches) != 1:
        fail(f"expected one {artifact} for {release}/{target}/{subtarget}, found {len(matches)}")
    return urljoin(base_url, matches[0])


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: resolve-openwrt-artifacts.py <release> <target> <subtarget>")

    release = sys.argv[1]
    if release.startswith("v"):
        release = release[1:]
    if not re.fullmatch(r"\d+\.\d+\.\d+", release):
        fail("release must be an exact final release such as 25.12.5")

    target, subtarget = sys.argv[2], sys.argv[3]
    base_url = f"{OPENWRT_DOWNLOADS}/{release}/targets/{target}/{subtarget}/"
    result = {
        "release": release,
        "target": target,
        "subtarget": subtarget,
        "base_url": base_url,
        "sdk_url": resolve_artifact(base_url, release, target, subtarget, "sdk"),
        "imagebuilder_url": resolve_artifact(base_url, release, target, subtarget, "imagebuilder"),
        "feeds_buildinfo_url": urljoin(base_url, "feeds.buildinfo"),
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
