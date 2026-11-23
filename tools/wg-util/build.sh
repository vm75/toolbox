#!/usr/bin/env bash
set -Eeuo pipefail
case "$TARGET" in linux-amd64) export GOARCH=amd64 ;; linux-arm64) export GOARCH=arm64 ;; linux-armv7) export GOARCH=arm GOARM=7 ;; esac
export GOOS=linux CGO_ENABLED=0
cd "$SRC"
go build -trimpath -ldflags="-s -w" -o "$OUT/wg-util" .
