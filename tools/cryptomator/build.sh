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
find presentation/build/outputs/apk -type f -name '*release*.apk' -exec cp -v {} "$OUT/" \;
find "$OUT" -maxdepth 1 -name '*.apk' | grep -q .
