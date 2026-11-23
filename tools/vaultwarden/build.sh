#!/usr/bin/env bash
set -Eeuo pipefail
stage="$WORKSPACE/stage-vaultwarden"
mkdir -p "$stage/opt/bin" "$stage/opt/share/vaultwarden/web-vault" "$stage/opt/etc/init.d"
version="$(sed -n '/^version = /s/.*"\([^"]*\)".*/\1/p' "$SRC/Cargo.toml" | head -1)"
version="${version:-0.0.0}"
if [[ "$TARGET" == router-aarch64 ]]; then
  # Build for Entware's GLIBC 2.27 with Zig's explicit target ABI.
  # Never repackage Alpine's dynamically linked MUSL executable as an Entware IPK.
  command -v cargo
  command -v zig
  command -v cargo-zigbuild
  rustup target add aarch64-unknown-linux-gnu
  (cd "$SRC" && \
    RUSTFLAGS="-C link-arg=-Wl,--dynamic-linker=/opt/lib/ld-linux-aarch64.so.1" \
    cargo zigbuild --release --target aarch64-unknown-linux-gnu.2.27 \
    --no-default-features --features sqlite,vendored_openssl)
  cp "$SRC/target/aarch64-unknown-linux-gnu/release/vaultwarden" "$stage/opt/bin/"
  bash "$ROOT/scripts/check-router-elf.sh" "$stage/opt/bin/vaultwarden"
  # Use the web-vault digest pinned in the SAME upstream Dockerfile revision.
  web_image="$(sed -nE 's/^FROM --platform=linux\/amd64 (docker.io\/vaultwarden\/web-vault@sha256:[0-9a-f]+) AS vault$/\1/p' "$SRC/docker/Dockerfile.alpine" | head -1)"
  [[ -n "$web_image" ]] || { echo "Pinned web-vault digest not found" >&2; exit 1; }
  docker pull "$web_image"
  container="$(docker create "$web_image")"
  trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
  docker cp "$container:/web-vault/." "$stage/opt/share/vaultwarden/web-vault/"
  cp "$ROOT/tools/vaultwarden/assets/S90vaultwarden" "$stage/opt/etc/init.d/"
  cp "$ROOT/tools/vaultwarden/assets/env.example" "$stage/opt/etc/vaultwarden.env.example"
  bash "$ROOT/scripts/ipk.sh" vaultwarden "$version-1" "$stage" "$OUT" "Vaultwarden password manager server"
else
  case "$TARGET" in
    linux-arm64) platform=linux/arm64 ;;
    linux-armv7) platform=linux/arm/v7 ;;
    linux-amd64) platform=linux/amd64 ;;
    *) exit 2 ;;
  esac
  docker buildx version
  img="toolbox-vaultwarden:${GITHUB_RUN_ID:-local}-${TARGET}"
  docker buildx build --load --platform "$platform" -f "$SRC/docker/Dockerfile.alpine" -t "$img" "$SRC"
  container="$(docker create "$img")"
  trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
  docker cp "$container:/vaultwarden" "$stage/opt/bin/vaultwarden"
  docker cp "$container:/web-vault/." "$stage/opt/share/vaultwarden/web-vault/"
  tar -C "$stage" -czf "$OUT/vaultwarden-$version-$TARGET.tgz" opt
fi
