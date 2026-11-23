#!/usr/bin/env bash
set -Eeuo pipefail
case "$TARGET" in linux-amd64) export GOARCH=amd64 ;; linux-arm64) export GOARCH=arm64 ;; linux-armv7) export GOARCH=arm GOARM=7 ;; esac
export GOOS=linux CGO_ENABLED=0
stage="$WORKSPACE/stage-wireguard"
mkdir -p "$stage/wireguard"
(cd "$SRC" && go build -trimpath -ldflags="-s -w" -o "$stage/wireguard/wireguard-go" .)
(cd "$WORKSPACE/source/wg-util" && go build -trimpath -ldflags="-s -w" -o "$stage/wireguard/wg-util" .)
cp "$ROOT/tools/wireguard/assets/"* "$stage/wireguard/"
tar -C "$stage" -czf "$OUT/wireguard-$TARGET.tgz" wireguard
