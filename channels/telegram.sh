#!/bin/sh
# Forward allowed Telegram messages to main and send replies back.
set -eu
TELEGRAM_BOT_TOKEN=${TELEGRAM_CHAT_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
allowed=$(printf '%s' "${TELEGRAM_CHAT_IDS:-}" | tr -d '[:space:]')
state=/data/.telegram
mkdir -p "$state"
offset=0

telegram() {
    telegram_response=$(curl -fsS --max-time "${3:-70}" "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/$1" \
        -H 'content-type: application/json' --data "$2") || return 1
    printf '%s' "$telegram_response" | jq -ce 'select(.ok == true)'
}

send() {
    # Escape HTML and format basic Markdown in 2000-character chunks.
    send_payloads=$(jq -cn --arg chat "$1" --arg text "$2" '
        range(0; $text | length; 2000) as $start |
        $text[$start:($start+2000)] as $plain |
        ($plain | @html | gsub(
            "```(?:[^\\n`]*\\n)?(?<pre>[\\s\\S]*?)```|`(?<code>[^`\\n]+)`|\\*\\*(?<bold>[^\\n]+?)\\*\\*|\\*(?<italic>[^*\\n]+)\\*|\\[(?<label>[^]\\n]+)\\]\\((?<url>https?://[^)\\s]+)\\)|(?m)^#{1,6} (?<heading>[^\\n]+)$";
            if .pre != null then "<pre>" + .pre + "</pre>"
            elif .code != null then "<code>" + .code + "</code>"
            elif .bold != null then "<b>" + .bold + "</b>"
            elif .italic != null then "<i>" + .italic + "</i>"
            elif .label != null then "<a href=\"" + .url + "\">" + .label + "</a>"
            else "<b>" + .heading + "</b>" end)) as $html |
        {chat_id:$chat, text:$html, parse_mode:"HTML",
         link_preview_options:{is_disabled:true}, plain:$plain}
    ') || return 1
    printf '%s\n' "$send_payloads" | while IFS= read -r send_payload; do
        [ -n "$send_payload" ] || continue
        formatted=$(printf '%s' "$send_payload" | jq 'del(.plain)')
        if ! telegram sendMessage "$formatted" >/dev/null; then
            # A formatting rejection must not lose the reply.
            plain=$(printf '%s' "$send_payload" | jq '.text = .plain | del(.plain, .parse_mode)')
            telegram sendMessage "$plain" >/dev/null || exit 1
        fi
    done
}

transcribe() (
    key=${TELEGRAM_TRANSCRIPTION_API_KEY:-${OPENAI_API_KEY:-}}
    if [ -z "$key" ]; then
        for credentials in /data/shared/.env /data/agents/main/.env; do
            [ -f "$credentials" ] || continue
            value=$(awk '/^OPENAI_API_KEY=/ {sub(/^OPENAI_API_KEY=/, ""); key=$0} END {print key}' "$credentials")
            [ -z "$value" ] || key=$value
        done
    fi
    [ -n "$key" ] || { echo 'Voice notes need OPENAI_API_KEY or TELEGRAM_TRANSCRIPTION_API_KEY configured.'; exit 1; }
    size=$(printf '%s' "$1" | jq '.message | (.voice // .audio).file_size // 0')
    [ "$size" -le 20000000 ] || { echo 'Please send a recording under 20 MB.'; exit 1; }
    file=$(printf '%s' "$1" | jq -c '.message | (.voice // .audio) | {file_id}')
    metadata=$(telegram getFile "$file" 30) || { echo 'Could not download that recording.'; exit 1; }
    path=$(printf '%s' "$metadata" | jq -er '.result.file_path') || exit 1
    extension=${path##*.}
    case "$extension" in
        oga) extension=ogg ;;
        flac|mp3|mp4|mpeg|mpga|m4a|ogg|wav|webm) ;;
        *) echo 'Please send a voice note or an OGG, MP3, M4A, WAV, FLAC, MP4 or WebM recording.'; exit 1 ;;
    esac
    temporary=$(mktemp -d)
    trap 'rm -rf "$temporary"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if ! curl -fsS --max-time 60 --max-filesize 20000000 \
        "https://api.telegram.org/file/bot$TELEGRAM_BOT_TOKEN/$path" -o "$temporary/audio.$extension" 2>/dev/null; then
        echo 'Could not download that recording. Please try again.'; exit 1
    fi
    if result=$(curl -fsS --max-time 120 https://api.openai.com/v1/audio/transcriptions \
        -H "Authorization: Bearer $key" \
        --form-string "model=${TELEGRAM_TRANSCRIPTION_MODEL:-gpt-transcribe}" \
        -F "file=@$temporary/audio.$extension" 2>/dev/null) && \
        transcript=$(printf '%s' "$result" | jq -er '.text | select(type == "string" and test("\\S"))'); then
        printf '%s\n' "$transcript"
    else
        echo 'Could not transcribe that recording. Please try again or send text.'; exit 1
    fi
)

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
commands='{"commands":[{"command":"start","description":"Show how to chat with main"},{"command":"help","description":"Show commands and voice note help"},{"command":"new","description":"Start a fresh conversation"},{"command":"reset","description":"Reset the current conversation"}]}'
telegram setMyCommands "$commands" >/dev/null || echo 'telegram: could not register commands' >&2
bot_username=$(telegram getMe '{}' | jq -r '.result.username // empty') || bot_username=
help='Send a message or voice note to chat with main. Audio recordings are transcribed using OpenAI and handled in this conversation. Replies support **bold**, *italics*, links and code.

/new — start a fresh conversation
/reset — same as /new
/help — show this help
/start — show this help

Voice notes need an OpenAI API key configured on the server.'
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
        [ -n "$chat" ] || continue
        case ",$allowed," in
            *,$chat,*) ;;
            *) echo "telegram: ignored chat $chat; add it to TELEGRAM_CHAT_IDS"; continue ;;
        esac
        command=${text%% *}
        case "$command" in
            /*@*)
                [ "${command#*@}" = "$bot_username" ] || continue
                command=${command%@*} ;;
        esac
        reset=$(cat "$state/$chat.reset" 2>/dev/null || printf 0)
        case "$command" in
            /start|/help)
                send "$chat" "$help" || true
                continue ;;
            /reset|/new)
                printf '%s\n' "$((reset + 1))" > "$state/$chat.reset"
                send "$chat" 'fresh conversation' || true
                continue ;;
            /*)
                send "$chat" 'Unknown command. Use /help to see available commands.' || true
                continue ;;
        esac
        audio=$(printf '%s' "$update" | jq -r '.message | (.voice // .audio // {}).file_id // empty')
        if [ -n "$audio" ]; then
            start_typing "$chat"
            if transcript=$(transcribe "$update"); then
                send "$chat" "💬 *“${transcript}”*" || true
                caption=$(printf '%s' "$update" | jq -r '.message.caption // empty')
                text=$transcript
                if [ -n "$caption" ]; then
                    text="$caption

$transcript"
                fi
            else
                stop_typing
                send "$chat" "$transcript" || true
                continue
            fi
            stop_typing
        fi
        [ -n "$text" ] || continue
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
