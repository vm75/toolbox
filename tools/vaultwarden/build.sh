#!/usr/bin/env bash
set -Eeuo pipefail
stage="$WORKSPACE/stage-vaultwarden"
mkdir -p "$stage/opt/libexec/vaultwarden" "$stage/opt/bin" \
  "$stage/opt/share/vaultwarden/web-vault" "$stage/opt/etc/init.d" \
  "$stage/opt/share/doc/vaultwarden"
version="${VW_VERSION:?Missing resolved Vaultwarden version}"
export VW_VERSION
if [[ "$TARGET" == entware-aarch64 || "$TARGET" == entware-armv7 ]]; then
  # Select a supported glibc 2.27 ABI and the correct Entware /opt interpreter.
  case "$TARGET" in
    entware-aarch64)
      rust_target=aarch64-unknown-linux-gnu
      interpreter=/opt/lib/ld-linux-aarch64.so.1
      ;;
    entware-armv7)
      # Entware armv7sf-k3.2 has a soft-float ABI and Linux 3.2.
      # Rust armv7-unknown-linux-gnueabi requires Linux 4.15+, so use
      # arm-unknown-linux-gnueabi (ARMv6, Linux 3.2+), runnable on ARMv7.
      rust_target=arm-unknown-linux-gnueabi
      interpreter=/opt/lib/ld-linux.so.3
      ;;
  esac
  command -v cargo-zigbuild
  python3 -m ziglang version
  # Do this INSIDE the upstream checkout: its rust-toolchain.toml selects
  # Rust 1.100.0; installing rust-std on the runner's default toolchain
  # resulted in E0463 ("can't find crate for core").
  (
    cd "$SRC"
    echo "Active Vaultwarden Rust toolchain: $(rustup show active-toolchain)"
    rustup target add "$rust_target"
    rustlib="$(rustc --print sysroot)/lib/rustlib/$rust_target/lib"
    compgen -G "$rustlib/libcore-*.rlib" >/dev/null || {
      echo "Missing $rust_target Rust std in active toolchain: $rustlib" >&2
      exit 1
    }
    RUSTFLAGS="-C link-arg=-Wl,--dynamic-linker=$interpreter" \
      cargo zigbuild --locked --release --target "$rust_target.2.27" \
        --no-default-features --features sqlite,vendored_openssl
  )
  install -m 0755 "$SRC/target/$rust_target/release/vaultwarden" \
    "$stage/opt/libexec/vaultwarden/vaultwarden"
  bash "$ROOT/scripts/check-router-elf.sh" "$stage/opt/libexec/vaultwarden/vaultwarden"
  # Matching upstream web-vault digest, rather than a floating 'latest' image.
  web_image="$(sed -nE 's/^FROM --platform=linux\/amd64 (docker.io\/vaultwarden\/web-vault@sha256:[0-9a-f]+) AS vault$/\1/p' "$SRC/docker/Dockerfile.alpine" | head -1)"
  [[ -n "$web_image" ]] || { echo "Pinned web-vault digest not found" >&2; exit 1; }
  docker pull "$web_image"
  container="$(docker create "$web_image")"
  trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
  docker cp "$container:/web-vault/." "$stage/opt/share/vaultwarden/web-vault/"
  cp "$ROOT/tools/vaultwarden/assets/S90vaultwarden" "$stage/opt/etc/init.d/"
  cp "$ROOT/tools/vaultwarden/assets/env.example" "$stage/opt/etc/vaultwarden.env.example"
else
  case "$TARGET" in
    linux-arm64) platform=linux/arm64 ;;
    linux-armv7) platform=linux/arm/v7 ;;
    linux-amd64) platform=linux/amd64 ;;
    *) exit 2 ;;
  esac
  docker buildx version
  img="toolbox-vaultwarden:${GITHUB_RUN_ID:-local}-${TARGET}"
  docker buildx build --load --platform "$platform" --build-arg "VW_VERSION=$version" -f "$SRC/docker/Dockerfile.alpine" -t "$img" "$SRC"
  container="$(docker create "$img")"
  trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
  docker cp "$container:/vaultwarden" "$stage/opt/libexec/vaultwarden/vaultwarden"
  docker cp "$container:/web-vault/." "$stage/opt/share/vaultwarden/web-vault/"
fi
for license in LICENSE LICENSE.txt COPYING; do
  if [[ -f "$SRC/$license" ]]; then
    cp "$SRC/$license" "$stage/opt/share/doc/vaultwarden/$license"
  fi
done
# Keep config/data out of /opt/bin; the same wrapper works via init.d or interactively.
cat > "$stage/opt/bin/vaultwarden" <<'WRAPPER'
#!/bin/sh
export WEB_VAULT_FOLDER="${WEB_VAULT_FOLDER:-/opt/share/vaultwarden/web-vault}"
export DATA_FOLDER="${DATA_FOLDER:-/opt/var/lib/vaultwarden}"
[ -d "$DATA_FOLDER" ] || mkdir -p "$DATA_FOLDER" || exit 1
[ ! -f /opt/etc/vaultwarden.env ] || export ENV_FILE=/opt/etc/vaultwarden.env
exec /opt/libexec/vaultwarden/vaultwarden "$@"
WRAPPER
chmod 755 "$stage/opt/bin/vaultwarden"
if [[ "$TARGET" == entware-aarch64 || "$TARGET" == entware-armv7 ]]; then
  bash "$ROOT/scripts/ipk.sh" vaultwarden "$version-1" "$stage" "$OUT" "Vaultwarden password manager server"
else
  tar -C "$stage" -czf "$OUT/vaultwarden-$version-$TARGET.tgz" opt
fi
