#!/usr/bin/env bash
# Logic tests that need no Android toolchain:
#  - Ruby runtime + map optimizer (against mkxp-z's real RPG module source)
#  - RGSS archive extractor (v1 + v3), round-trip against a Python encoder
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mkxp-z's RPG module (RPG::Map, RPG::Tileset, ...) is embedded as a C array.
SRC="$ROOT/native/.work/mkxp-z"
if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 https://github.com/mkxp-z/mkxp-z.git "$TMP/mkxp-z"
  SRC="$TMP/mkxp-z"
fi
python3 - "$SRC/binding/module_rpg1.rb.xxd" "$TMP/rpg1.rb" <<'PY'
import re, sys
nums = re.findall(r'0x([0-9a-fA-F]{2})', open(sys.argv[1]).read())
open(sys.argv[2], 'wb').write(bytes(int(n, 16) for n in nums).rstrip(b'\0'))
PY

echo "== Ruby runtime & optimizer"
RPG1="$TMP/rpg1.rb" WORK="$TMP/rt" ruby "$HERE/ruby/test.rb" | grep -v '^\[yami\]'
for args in "full xp" "full ess" "panoramic ess"; do
  echo "== widescreen $args"
  mkdir -p "$TMP/w"; WORK="$TMP/w" ruby "$HERE/ruby/wide.rb" $args | grep -v '^\[yami\]'
done

echo "== Win32API compatibility"
( cd "$TMP" && LC_ALL=C.UTF-8 ruby "$HERE/ruby/win32.rb" | grep -v '^\[yami' )

echo "== RGSS archives"
( cd "$TMP" && python3 "$HERE/archive/mk.py" \
  && javac -d cls "$ROOT/app/src/main/java/com/lordnordyx/yami/optimize/RgssArchive.java" "$HERE/archive/T.java" \
  && LC_ALL=C.UTF-8 java -Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8 -cp cls T \
  && diff -r ref out-a.rgssad && diff -r ref out-a.rgss3a && echo "archives: ALL PASS" )
