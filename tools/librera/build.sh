#!/usr/bin/env bash
set -Eeuo pipefail
export LIBRERA_MUPDF_DIR="$WORKSPACE/source/mupdf"
export LIBRERA_NDK_DIR="${LIBRERA_NDK_DIR:-${ANDROID_NDK_HOME:-}}"
[[ -x "$LIBRERA_NDK_DIR/ndk-build" ]] || { echo "Install Android NDK and set LIBRERA_NDK_DIR" >&2; exit 1; }
export LIBRERA_ABIS="arm64-v8a"
export LIBRERA_NATIVE_JOBS="${TOOLBOX_JOBS:-4}"
cd "$SRC"
bash Builder/link_to_mupdf_fork.sh
./gradlew --no-daemon updateFDroid
# The upstream fork's Gradle task produces an ARM64 and a universal F-Droid APK.
./gradlew --no-daemon :app:assembleFdroidRelease
find app/build/outputs/apk/fdroid/release -name '*.apk' -exec cp -v {} "$OUT/" \;
find "$OUT" -maxdepth 1 -name '*.apk' | grep -q .
