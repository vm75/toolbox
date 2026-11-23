#!/usr/bin/env bash
set -Eeuo pipefail
case "$TARGET" in
  router-aarch64|linux-arm64) arch=arm64 ;;
  linux-armv7) arch=arm; variant=v7 ;;
  linux-amd64) arch=amd64 ;;
  *) exit 2 ;;
esac
docker buildx version
# Build from CURRENT upstream source using upstream's multi-stage image, not a pre-built server binary.
img="toolbox-vaultwarden:${GITHUB_RUN_ID:-local}-$arch"
docker buildx build --load --platform "linux/$arch${variant:+/$variant}" -f "$SRC/docker/Dockerfile.alpine" -t "$img" "$SRC"
container="$(docker create "$img")"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
stage="$WORKSPACE/stage-vaultwarden"
mkdir -p "$stage/opt/bin" "$stage/opt/share/vaultwarden"
docker cp "$container:/vaultwarden" "$stage/opt/bin/vaultwarden"
docker cp "$container:/web-vault/." "$stage/opt/share/vaultwarden/"
version="$(sed -n '/^version = /s/.*"\([^"]*\)".*/\1/p' "$SRC/Cargo.toml" | head -1)"
version="${version:-0.0.0}"
if [[ "$TARGET" == router-aarch64 ]]; then
  # Alpine/MUSL output is intentionally rejected if it needs an Alpine runtime loader.
  bash "$ROOT/scripts/check-router-elf.sh" "$stage/opt/bin/vaultwarden"
  bash "$ROOT/scripts/ipk.sh" vaultwarden "$version-1" "$stage" "$OUT" "Vaultwarden password manager server"
else
  tar -C "$stage" -czf "$OUT/vaultwarden-$version-$TARGET.tgz" opt
fi
