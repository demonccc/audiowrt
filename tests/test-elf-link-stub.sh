#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/runtime.c" <<'EOF'
int audiowrt_fixture_value = 7;
int audiowrt_fixture_function(int value) { return value + 1; }
static int hidden_fixture(void) { return 0; }
EOF

cc -shared -fPIC -Wl,-soname,libaudiowrt-fixture.so.7 \
    -o "$tmp/runtime.so" "$tmp/runtime.c"
strip --strip-all "$tmp/runtime.so"

python3 "$repo_root/scripts/create-elf-link-stub.py" \
    readelf cc "$tmp/runtime.so" "$tmp/libaudiowrt-fixture.so" \
    libaudiowrt-fixture.so.7

readelf -d "$tmp/libaudiowrt-fixture.so" | grep -Fq 'libaudiowrt-fixture.so.7'
nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -Eq ' audiowrt_fixture_function$'
nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -Eq ' audiowrt_fixture_value$'
if nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -q 'hidden_fixture'; then
    echo 'ERROR: non-exported symbol leaked into generated link stub.' >&2
    exit 1
fi

cat > "$tmp/consumer.c" <<'EOF'
extern int audiowrt_fixture_function(int);
extern int audiowrt_fixture_value;
int main(void) {
    return audiowrt_fixture_function(audiowrt_fixture_value);
}
EOF

cc -o "$tmp/consumer" "$tmp/consumer.c" \
    -L"$tmp" -Wl,--no-as-needed -laudiowrt-fixture

echo 'Dynamic ELF link-stub generator tests passed.'
