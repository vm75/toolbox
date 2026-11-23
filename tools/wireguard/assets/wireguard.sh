#!/bin/sh
# keep it as sh script!

SELF=$(readlink -f "$0")
cd $(dirname "${SELF}")

case $1 in
  start)
    ./wg-quick up wg0
    ;;
  stop|kill)
    ./wg-quick down wg0
    ;;
  restart)
    ./wg-quick down wg0
    sleep 1
    ./wg-quick up wg0
    ;;
  *)
    scriptName=$(basename ${SELF})
    echo "Usage: ${scriptName} {start|stop|restart}"
    exit 1
    ;;
esac
