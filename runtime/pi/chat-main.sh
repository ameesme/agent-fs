#!/bin/sh
# Send stdin to a saved Pi conversation, or queue an update for a native TUI.
set -eu

conversation=${1:?usage: chat-main <conversation>}
case "$conversation" in
    ''|*[!a-zA-Z0-9_-]*) echo 'Invalid conversation id' >&2; exit 1 ;;
esac

text=$(cat)
case "$conversation" in
    native-*)
        # Keep updates on disk while the terminal is closed. Pi consumes them on resume.
        inbox=/data/.inbox/$conversation
        mkdir -p "$inbox"
        key=$(printf '%s' "$text" | sha256sum | cut -d ' ' -f 1)
        temporary=$(mktemp "$inbox/.update.XXXXXX")
        printf '%s' "$text" > "$temporary"
        mv "$temporary" "$inbox/$key.txt"
        exit 0 ;;
esac

# Only one writer may open a saved Pi session at a time.
mkdir -p /run/agent-fs/locks
lock=/run/agent-fs/locks/$conversation
until mkdir "$lock" 2>/dev/null; do sleep 1; done
trap 'rmdir "$lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$text" | docker exec -i \
    -e "AGENT_FS_CONVERSATION=$conversation" main-chat sh -c '
        mkdir -p /agent/home/.pi/bridge-sessions
        exec agent-run --print --session "/agent/home/.pi/bridge-sessions/$AGENT_FS_CONVERSATION.jsonl"
    '
