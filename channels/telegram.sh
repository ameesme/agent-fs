#!/bin/sh
# Forward allowed Telegram messages to main and send its replies back.
# Uses a saved Pi session per Telegram chat,
# so Telegram stays an optional way to talk to main.
set -eu
TELEGRAM_BOT_TOKEN=${TELEGRAM_CHAT_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
allowed=$(printf '%s' "${TELEGRAM_CHAT_IDS:-}" | tr -d '[:space:]')
state=/data/.telegram
mkdir -p "$state"
offset=0

telegram() {
    curl -fsS --max-time "${3:-70}" "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/$1" \
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

typing_pid=
stop_typing() {
    [ -n "$typing_pid" ] || return 0
    kill "$typing_pid" 2>/dev/null || true
    wait "$typing_pid" 2>/dev/null || true
    typing_pid=
}
trap 'stop_typing' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_typing() {
    typing_payload=$(jq -cn --arg chat "$1" '{chat_id:$chat, action:"typing"}')
    (
        typing_child=
        trap '[ -z "$typing_child" ] || { kill "$typing_child" 2>/dev/null || true; wait "$typing_child" 2>/dev/null || true; }' EXIT
        trap 'exit 0' INT TERM
        while :; do
            telegram sendChatAction "$typing_payload" 5 &
            typing_child=$!
            wait "$typing_child" || true
            # Telegram clears chat actions after five seconds or on a reply.
            sleep 4 &
            typing_child=$!
            wait "$typing_child" || true
        done
    ) >/dev/null 2>&1 &
    typing_pid=$!
}

echo 'telegram channel up; only allowlisted chats can send work'
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
        start_typing "$chat"
        if reply=$(printf '%s' "$text" | chat-main "telegram-$chat-$reset"); then
            stop_typing
            send "$chat" "$reply" || true
        else
            stop_typing
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
