#!/bin/sh
# Send stdin to a saved Pi conversation, or queue an update for a native TUI.
set -eu

conversation=${1:?usage: chat-main <conversation> [agent]}
agent=${2:-main}
case "$conversation$agent" in
    *[!a-zA-Z0-9_-]*) echo 'Invalid conversation or agent id' >&2; exit 1 ;;
esac
container=$agent-chat
note=
if [ "$agent" != main ]; then
    # Worker instructions assume a queued task file, which a chat does not have.
    note='This is a direct chat with the user, not a queued task: there is no task file, so reply in the chat.'
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
# Back off while watch-fs recreates main-chat; it waits for these locks in turn.
until mkdir "$lock" 2>/dev/null && { [ "$agent" != main ] || [ ! -d /run/agent-fs/locks/.reload-main ] || ! rmdir "$lock"; }; do
    sleep 1
done
trap 'rmdir "$lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# A rebuilt image only reaches a chat through a new container.
[ "$(docker inspect -f '{{.State.Running}} {{.Image}}' "$container" 2>/dev/null)" = "true $(docker image inspect -f '{{.Id}}' "agent-$agent")" ] || start-agent "$agent" chat >/dev/null

printf '%s' "$text" | docker exec -i \
    -e "AGENT_FS_CONVERSATION=$conversation" -e "AGENT_FS_NOTE=$note" "$container" sh -c '
        if [ -d /agent/home/.pi/bridge-sessions ] && [ ! -e /agent/home/.pi/channel-sessions ]; then
            mv /agent/home/.pi/bridge-sessions /agent/home/.pi/channel-sessions
        fi
        mkdir -p /agent/home/.pi/channel-sessions
        exec agent-run --print ${AGENT_FS_NOTE:+--append-system-prompt "$AGENT_FS_NOTE"} --session "/agent/home/.pi/channel-sessions/$AGENT_FS_CONVERSATION.jsonl"
    '
