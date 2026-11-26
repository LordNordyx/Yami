#!/usr/bin/env bash
# Builds the mkxp-z RGSS engine for Android (arm64-v8a) and drops libmain.so
# into app/src/main/jniLibs. Requires: Android NDK (r26+), meson, ninja,
# cmake, python3, a host Ruby (for cross-compiling MRI), bison, autoconf.
#
#   ANDROID_NDK_HOME=/path/to/ndk ./native/build-mkxp.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
API="${ANDROID_API:-26}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
MKXPZ_REPO="${MKXPZ_REPO:-https://github.com/mkxp-z/mkxp-z.git}"
# Pinned commit the patches were written against.
MKXPZ_REF="${MKXPZ_REF:-a8f9d9ee331034b7778d0f6c3a5603de8b87388f}"
WORK="${WORK:-$ROOT/native/.work}"
OUT="$ROOT/app/src/main/jniLibs/arm64-v8a"

[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "Set ANDROID_NDK_HOME"; exit 1; }
mkdir -p "$WORK" "$OUT"

# init + fetch in place: CI restores subprojects/packagecache into this folder first,
# so it may already exist without a .git directory.
mkdir -p "$WORK/mkxp-z"
cd "$WORK/mkxp-z"
if [ ! -d .git ]; then
  git init -q
  git remote add origin "$MKXPZ_REPO"
fi
git fetch -q --depth 1 origin "$MKXPZ_REF"
git checkout -q -f FETCH_HEAD
git clean -fdq -e subprojects/packagecache
for p in "$HERE"/patches/*.patch; do
  echo ">> applying $(basename "$p")"
  git apply --whitespace=nowarn "$p"
done

sed -e "s|@NDK@|$NDK|g" -e "s|@API@|$API|g" \
  "$HERE/android-arm64.cross.in" > "$WORK/android-arm64.cross"

BUILD="$WORK/build-arm64"
if [ ! -f "$BUILD/build.ninja" ]; then
  meson setup "$BUILD" \
    --cross-file "$WORK/android-arm64.cross" \
    --buildtype release \
    -Dstrip=true \
    -Dgfx_backend=gles \
    -Dextra_shaders=enabled \
    -Dangle=disabled \
    -Duse_miniffi=false \
    -Dsteamworks_path= \
    -Ddefault_system=disabled \
    -Dwrap_mode=default
fi
ninja -C "$BUILD"

LIB="$(find "$BUILD" -maxdepth 1 -name 'libmain.so' | head -1)"
[ -f "$LIB" ] || { echo "libmain.so not produced"; exit 1; }
cp "$LIB" "$OUT/libmain.so"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded "$OUT/libmain.so"

# Sanity check: the SDL JNI entry points must be exported, otherwise
# SDLActivity fails with UnsatisfiedLinkError at startup.
NM="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
# Capture once: with pipefail, `nm | grep -q` fails when grep exits early (SIGPIPE).
EXPORTS="$("$NM" -D --defined-only "$OUT/libmain.so")"
echo ">> exported SDL JNI symbols: $(grep -c Java_org_libsdl_app <<<"$EXPORTS" || true)"
fail=0
for sym in Java_org_libsdl_app_SDLActivity_nativeSetupJNI Java_org_libsdl_app_SDLActivity_nativeRunMain \
           Java_org_libsdl_app_SDLAudioManager_nativeSetupJNI Java_org_libsdl_app_SDLControllerManager_nativeSetupJNI SDL_main; do
  if ! grep -q " $sym$" <<<"$EXPORTS"; then
    echo "missing exported symbol: $sym"
    "$NM" "$LIB" 2>/dev/null | grep "$sym" | head -3 || true   # present but hidden?
    fail=1
  fi
done
[ "$fail" = 0 ] || exit 1
echo ">> $OUT/libmain.so ($(du -h "$OUT/libmain.so" | cut -f1))"
