#!/bin/sh
# Home Assistant adapter; the core runtime stays unchanged.
set -eu
# Home Assistant owns shared credentials; agent-specific .env files still win.
if [ ! -f /data/.agent-fs-initialized ]; then
    (cd /etc/agent-fs-defaults && find . -type f) | while IFS= read -r file; do
        mkdir -p "/data/${file%/*}"
        if [ ! -e "/data/$file" ]; then
            cp "/etc/agent-fs-defaults/$file" "/data/$file"
        fi
    done
    touch /data/.agent-fs-initialized
fi

# Docker env files are single-line KEY=value entries. Never evaluate values as shell.
(
    umask 077
    jq -er '
    (.environment // []) | map(
        if (.name | test("^[A-Za-z_][A-Za-z0-9_]*$")) and
           (.value | type == "string" and (test("[\r\n]") | not))
        then .name + "=" + .value
        else error("Environment entries need a valid name and a single-line value")
        end
    ) | join("\n")
    ' /data/options.json > /data/shared/.env.tmp
    mv /data/shared/.env.tmp /data/shared/.env
)

TELEGRAM_BOT_TOKEN=$(jq -r '.telegram_bot_token // ""' /data/options.json)
TELEGRAM_CHAT_IDS=$(jq -r '.telegram_chat_ids // ""' /data/options.json)
export TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_IDS
set --
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    if [ -z "$TELEGRAM_CHAT_IDS" ]; then
        echo 'Set telegram_chat_ids before enabling Telegram.' >&2
        exit 1
    fi
    set -- sh /channels/telegram.sh
fi

exec boot.sh "$@"
