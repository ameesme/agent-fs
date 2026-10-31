#!/bin/sh
# Forward allowed Telegram messages to main and send its replies back.
# Uses the same chat server as the CLI, with a conversation per Telegram chat,
# so Telegram stays an optional way to talk to main.
set -eu
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
allowed=$(printf '%s' "${TELEGRAM_CHAT_IDS:-}" | tr -d '[:space:]')
chat_url=http://127.0.0.1:8083/v1/chat/completions
state=/run/telegram
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
        telegram sendMessage "$send_payload" >/dev/null || true
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
                send "$chat" 'fresh conversation'
                continue ;;
        esac
        send "$chat" 'on it'
        body=$(jq -cn --arg text "$text" '{model:"root",messages:[{role:"user",content:$text}]}')
        if reply=$(curl -fsS --max-time 1260 "$chat_url" -H 'content-type: application/json' \
            -H "authorization: Bearer $(cat /run/agent-fs/chat-key)" \
            -H "x-conversation-id: telegram-$chat-$reset" --data "$body"); then
            send "$chat" "$(printf '%s' "$reply" | jq -r '.choices[0].message.content // "(empty reply)"')"
        else
            send "$chat" 'main unreachable'
        fi
    done
done
