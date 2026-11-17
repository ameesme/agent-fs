#!/bin/sh
# Send stdin to a saved Pi conversation, or queue an update for a native TUI.
set -eu

conversation=${1:?usage: chat-main <conversation> [agent]}
agent=${2:-main}
case "$conversation$agent" in
    *[!a-zA-Z0-9_-]*) echo 'Invalid conversation or agent id' >&2; exit 1 ;;
esac
container=main-chat
if [ "$agent" != main ]; then
    container=$agent-chat
    [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = true ] || start-agent "$agent" chat
fi

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
lock=/run/agent-fs/locks/$agent-$conversation
until mkdir "$lock" 2>/dev/null; do sleep 1; done
trap 'rmdir "$lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$text" | docker exec -i \
    -e "AGENT_FS_CONVERSATION=$conversation" "$container" sh -c '
        if [ -d /agent/home/.pi/bridge-sessions ] && [ ! -e /agent/home/.pi/channel-sessions ]; then
            mv /agent/home/.pi/bridge-sessions /agent/home/.pi/channel-sessions
        fi
        mkdir -p /agent/home/.pi/channel-sessions
        exec agent-run --print --session "/agent/home/.pi/channel-sessions/$AGENT_FS_CONVERSATION.jsonl"
    '
