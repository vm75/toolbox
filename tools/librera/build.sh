#!/usr/bin/env bash
set -Eeuo pipefail
# Java's filename encoding must preserve the Cyrillic dictionary asset names.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
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
mapfile -d '' -t apks < <(find app/build/outputs/apk/fdroid/release -type f -name '*.apk' -print0)
(( ${#apks[@]} > 0 )) || { echo "No Librera F-Droid release APKs found" >&2; exit 1; }
for apk in "${apks[@]}"; do
  case "${apk##*/}" in
    *-arm64.apk|*-arm64-v8a.apk|*-arm64-v8a-*.apk) variant=arm64 ;;
    *-uni.apk|*-universal.apk|*-universal-*.apk) variant=universal ;;
    *) variant="$(printf '%s' "${apk##*/}" | tr -c 'A-Za-z0-9._-' '-')"; variant="${variant%.apk}" ;;
  esac
  dest="$OUT/librera-${APK_VERSION:?missing upstream APK version}-$variant.apk"
  [[ ! -e "$dest" ]] || { echo "Duplicate Librera APK name: $dest" >&2; exit 1; }
  cp -v -- "$apk" "$dest"
done
