#!/bin/sh
# keep it as sh script!

SELF=$(readlink -f "$0")
cd $(dirname "${SELF}")

./vaultwarden "$@"
