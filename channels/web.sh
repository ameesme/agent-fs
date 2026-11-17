#!/bin/sh
# Web channel: serve per-agent chat and agent files, then run any further channel.
set -eu

httpd -p "${WEB_PORT:-8080}" -h /channels/web
[ "$#" -eq 0 ] || exec "$@"
