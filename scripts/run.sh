#!/usr/bin/env bash
# Select a prepared build environment; leave tool-specific work in scripts/build.sh.
set -Eeuo pipefail
[[ $# -ge 2 && $# -le 3 ]] || { echo "Usage: scripts/run.sh TOOL TARGET [UPSTREAM_REF]" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tool="$1" target="$2" ref="${3:-}"

# Checking patches requires git, not an SDK or a cross-compiler.
if [[ "${TOOLBOX_PREPARE_ONLY:-0}" == 1 ]]; then
  exec bash scripts/build.sh "$tool" "$target" "$ref"
fi

# Only the expensive environments get their own images. No platform matrix.
case "$tool:$target" in
  nginx:entware-aarch64|btop:entware-aarch64)
    builder=entware-aarch64
    tag=v3
    ;;
  nginx:entware-armv7|btop:entware-armv7)
    builder=entware-armv7
    tag=v2
    ;;
  librera:android-arm64|cryptomator:android-arm64|mupdf:android-arm64)
    builder=android
    tag=ndk-r27d
    ;;
  *)
    exec bash scripts/build.sh "$tool" "$target" "$ref"
    ;;
esac

: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY to owner/repo for GHCR image pulls}"
image="ghcr.io/${GITHUB_REPOSITORY,,}/$builder:$tag"
echo "Using builder image: $image"
if ! docker pull "$image"; then
  echo "::error::Missing builder image $image. Run the manual 'Build toolbox images' workflow first." >&2
  exit 1
fi

args=(docker run --rm --user builder
  --mount "type=bind,source=$ROOT,target=/workspace"
  --workdir /workspace
  --env "TOOLBOX_JOBS=${TOOLBOX_JOBS:-4}"
  --env "TOOLBOX_MUPDF_REF=${TOOLBOX_MUPDF_REF:-}")

if [[ "$builder" == entware-aarch64 || "$builder" == entware-armv7 ]]; then
  # Both Entware images pre-build the matching nginx toolchain here.
  # ARMv7 is not Android: never require a keystore for router builds.
  args+=(--env TOOLBOX_NGINX_CACHE=/opt/nginx-entware)
elif [[ "$builder" == android && "$tool" != mupdf ]]; then
  # The keystore is mounted read-only at build time, never baked into an image.
  [[ -s "${ANDROID_KEYSTORE_FILE:-}" ]] || {
    echo "Android keystore missing; see docs/android-signing.md" >&2
    exit 1
  }
  for key in RELEASE_STORE_PASSWORD RELEASE_KEY_ALIAS RELEASE_KEY_PASSWORD; do
    [[ -n "${!key:-}" ]] || { echo "Missing Android signing variable $key" >&2; exit 1; }
    args+=(--env "$key" --env "ORG_GRADLE_PROJECT_$key")
  done
  args+=(--mount "type=bind,source=$ANDROID_KEYSTORE_FILE,target=/run/secrets/android-release.p12,readonly"
    --env ANDROID_KEYSTORE_FILE=/run/secrets/android-release.p12
    --env RELEASE_STORE_FILE=/run/secrets/android-release.p12
    --env ORG_GRADLE_PROJECT_RELEASE_STORE_FILE=/run/secrets/android-release.p12)
fi

exec "${args[@]}" "$image" bash scripts/build.sh "$tool" "$target" "$ref"
