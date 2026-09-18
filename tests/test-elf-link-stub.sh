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

readelf -d "$tmp/libaudiowrt-fixture.so" | grep -Fq "libaudiowrt-fixture.so.7"
nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -Eq " audiowrt_fixture_function$"
nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -Eq " audiowrt_fixture_value$"
if nm -D --defined-only "$tmp/libaudiowrt-fixture.so" | grep -q "hidden_fixture"; then
    echo "ERROR: non-exported symbol leaked into generated link stub." >&2
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

# OpenWrt's stripped MIPS shared libraries expose _init/_fini in .dynsym.
# Those names are supplied by the target CRT (crti.o) during stub linking and
# must not be mirrored into the generated C source.
cat > "$tmp/fake-readelf" <<'EOF'
#!/usr/bin/env sh
cat <<'DYN'
Symbol table for image contains 5 entries:
   Num:    Value  Size Type    Bind   Vis      Ndx Name
     1: 00000000     0 FUNC    GLOBAL DEFAULT    8 _init
     2: 00000000     0 FUNC    GLOBAL DEFAULT    8 _fini
     3: 00000000     4 OBJECT  GLOBAL DEFAULT   10 audiowrt_fixture_value
     4: 00000000    16 FUNC    GLOBAL DEFAULT    8 audiowrt_fixture_function
DYN
EOF
chmod +x "$tmp/fake-readelf"

python3 "$repo_root/scripts/create-elf-link-stub.py" \
    "$tmp/fake-readelf" cc "$tmp/runtime.so" \
    "$tmp/libaudiowrt-filtered.so" libaudiowrt-filtered.so.1

if nm -D --defined-only "$tmp/libaudiowrt-filtered.so" | grep -Eq " (_init|_fini)$"; then
    echo "ERROR: CRT-owned _init/_fini leaked into generated link stub." >&2
    exit 1
fi
nm -D --defined-only "$tmp/libaudiowrt-filtered.so" | grep -Eq " audiowrt_fixture_function$"
nm -D --defined-only "$tmp/libaudiowrt-filtered.so" | grep -Eq " audiowrt_fixture_value$"

echo "Dynamic ELF link-stub generator tests passed."
