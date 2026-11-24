#!/usr/bin/env bash
set -Eeuo pipefail
[[ -n "${ANDROID_KEYSTORE_FILE:-}" && -r "$ANDROID_KEYSTORE_FILE" ]] || {
  echo "Set ANDROID_KEYSTORE_FILE for signed Cryptomator APKs" >&2; exit 1;
}
cd "$SRC"
./gradlew --no-daemon assembleApkstoreRelease \
  "-PRELEASE_STORE_FILE=$ANDROID_KEYSTORE_FILE" \
  "-PRELEASE_STORE_PASSWORD=${RELEASE_STORE_PASSWORD:?missing RELEASE_STORE_PASSWORD}" \
  "-PRELEASE_KEY_ALIAS=${RELEASE_KEY_ALIAS:?missing RELEASE_KEY_ALIAS}" \
  "-PRELEASE_KEY_PASSWORD=${RELEASE_KEY_PASSWORD:?missing RELEASE_KEY_PASSWORD}"
# Gradle uses the presentation module name for its APK. Publish a stable app name.
mapfile -d '' -t apks < <(find presentation/build/outputs/apk/apkstore/release -type f -name '*.apk' -print0)
if (( ${#apks[@]} != 1 )); then
  echo "Expected exactly one Cryptomator APK Store release APK, found ${#apks[@]}" >&2
  exit 1
fi
cp -v -- "${apks[0]}" "$OUT/cryptomator.apk"
