#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
root-package|target/root
child-package|target/child
provider-package|target/provider
unrelated-package|target/unrelated
source-package|target/source
EOF

cat > "$tmp/packageinfo" <<'EOF'
Package: root-package
Depends: +child-package +virtual-capability
Package: child-package
Depends: +libc
Package: provider-package
Provides: virtual-capability
Package: unrelated-package
Depends: +libc
Build-Depends: build-tool/host
Package: source-package
Depends: +virtual-capability +kmod-example +libpthread
EOF

python3 "$repo_root/scripts/resolve-package-build-targets.py" \
    "$tmp/targets" "$tmp/packageinfo" root-package \
    --providers provider-package > "$tmp/build-targets"

grep -qx 'child-package|target/child' "$tmp/build-targets"
grep -qx 'provider-package|target/provider' "$tmp/build-targets"
grep -qx 'root-package|target/root' "$tmp/build-targets"
if grep -q '^unrelated-package|' "$tmp/build-targets"; then
    echo 'ERROR: unrelated package entered the resolved build closure.' >&2
    exit 1
fi

python3 "$repo_root/scripts/resolve-source-build-dependencies.py" \
    "$tmp/targets" "$tmp/packageinfo" source-package \
    --providers provider-package > "$tmp/source-deps"

grep -qx 'build-tool' "$tmp/source-deps"
if grep -Eq '^(virtual-capability|provider-package|kmod-example|libpthread)$' "$tmp/source-deps"; then
    echo 'ERROR: provider, kernel, or toolchain runtime dependency leaked into source dependencies.' >&2
    cat "$tmp/source-deps" >&2
    exit 1
fi

printf 'Generic package resolver contracts passed.\n'
