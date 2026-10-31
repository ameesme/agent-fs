#!/bin/sh
# Forward allowed Telegram messages to main and send its replies back.
# Uses a saved Pi session per Telegram chat,
# so Telegram stays an optional way to talk to main.
set -eu
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
allowed=$(printf '%s' "${TELEGRAM_CHAT_IDS:-}" | tr -d '[:space:]')
state=/data/.telegram
mkdir -p "$state"
offset=0

telegram() {
    curl -fsS --max-time 70 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/$1" \
        -H 'content-type: application/json' --data "$2"
}

send() {
    send_length=$(printf '%s' "$2" | jq -Rs 'length')
    send_start=0
    while [ "$send_start" -lt "$send_length" ]; do
        send_payload=$(jq -cn --arg chat "$1" --arg text "$2" --argjson start "$send_start" \
            '{chat_id:$chat, text:$text[$start:($start+4000)]}')
        telegram sendMessage "$send_payload" >/dev/null || return 1
        send_start=$((send_start + 4000))
    done
}

echo 'telegram bridge up; only allowlisted chats can send work'
while :; do
    poll=$(printf '{"offset":%s,"timeout":5}' "$offset")
    if ! updates=$(telegram getUpdates "$poll"); then
        sleep 5
        continue
    fi
    for encoded in $(printf '%s' "$updates" | jq -r '.result[]? | @base64'); do
        update=$(printf '%s' "$encoded" | base64 -d)
        offset=$(printf '%s' "$update" | jq '.update_id + 1')
        chat=$(printf '%s' "$update" | jq -r '.message.chat.id // empty')
        text=$(printf '%s' "$update" | jq -r '.message.text // empty')
        [ -n "$chat" ] && [ -n "$text" ] || continue
        case ",$allowed," in
            *,$chat,*) ;;
            *) echo "telegram: ignored chat $chat; add it to TELEGRAM_CHAT_IDS"; continue ;;
        esac
        reset=$(cat "$state/$chat.reset" 2>/dev/null || printf 0)
        case "$text" in
            /reset|/new)
                printf '%s\n' "$((reset + 1))" > "$state/$chat.reset"
                send "$chat" 'fresh conversation' || true
                continue ;;
        esac
        send "$chat" 'on it' || true
        if reply=$(printf '%s' "$text" | chat-main "telegram-$chat-$reset"); then
            send "$chat" "$reply" || true
        else
            send "$chat" 'main unreachable' || true
        fi
    done
    for message in /run/agent-fs/outbox/telegram-*/*.txt; do
        [ -f "$message" ] || continue
        conversation=${message%/*}
        conversation=${conversation##*/}
        chat=${conversation#telegram-}
        chat=${chat%-*}
        case ",$allowed," in
            *,$chat,*) ;;
            *) continue ;;
        esac
        if send "$chat" "$(cat "$message")"; then
            rm "$message"
        fi
    done
done
