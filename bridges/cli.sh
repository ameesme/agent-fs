#!/bin/sh
# Connect your terminal to main's chat server, keeping follow-ups together.
# Provides a local chat prompt without another service to configure; main
# handles the conversation and delegates work to sub-agents.
set -eu

chat_url=http://127.0.0.1:8083/v1/chat/completions
session=cli-$(date +%s)-$$
reset=0
trap 'printf "\n"; exit 0' INT TERM

printf 'Waiting for main (the first build can take a while)...\n'
until [ -s /run/agent-fs/chat-key ] && curl -s --connect-timeout 2 --max-time 2 \
    -o /dev/null http://127.0.0.1:8083/; do
    sleep 2
done
printf 'Chat with main. /reset starts fresh, /quit exits.\n\n'

while printf 'you> ' && IFS= read -r text; do
    case "$text" in
        /quit|/exit) break ;;
        /reset|/new)
            reset=$((reset + 1))
            printf 'Fresh conversation.\n\n'
            continue ;;
        '') continue ;;
    esac
    body=$(jq -cn --arg text "$text" '{model:"root",messages:[{role:"user",content:$text}]}')
    if reply=$(curl -fsS --max-time 1260 "$chat_url" -H 'content-type: application/json' \
        -H "authorization: Bearer $(cat /run/agent-fs/chat-key)" \
        -H "x-conversation-id: $session-$reset" --data "$body"); then
        printf '%s\n' "$reply" | jq -r '"main> " + (.choices[0].message.content // "(empty reply)")'
    else
        printf 'Could not reach main. Check docker compose logs and try again.\n'
    fi
    printf '\n'
done
