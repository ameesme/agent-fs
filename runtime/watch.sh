#!/bin/sh
# Watch agent folders, build their images and start containers when work arrives.
# Keeps main's chat server running and checks sub-agent queues, so adding a
# folder or task is enough to make it run.
set -eu

mkdir -p /run/agent-fs /data/.builds
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > /run/agent-fs/chat-key
chmod 600 /run/agent-fs/chat-key
docker rm -f main-chat >/dev/null 2>&1 || true

# Optional bridges are separate commands, passed through by Compose.
if [ "$#" -gt 0 ]; then
    "$@" &
fi

base_hash=$(find /agent-base -type f -exec sha256sum {} \; | sort | sha256sum | cut -d ' ' -f 1)

running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

echo 'runtime up; watching /data/agents'
while :; do
    for agent in /data/agents/*; do
        [ -f "$agent/agent.yaml" ] && [ -f "$agent/Dockerfile" ] || continue
        name=${agent##*/}

        # Build lazily so an empty install doesn't need an agent image.
        if [ "$(cat /data/.builds/base 2>/dev/null)" != "$base_hash" ]; then
            docker build -t agent-base /agent-base || break
            printf '%s\n' "$base_hash" > /data/.builds/base
        fi

        mkdir -p "$agent/home/workspace"
        if [ ! -f "$agent/home/memory.md" ]; then
            printf '# memory\n' > "$agent/home/memory.md"
        fi
        if [ "$name" != main ]; then
            for status in backlog todo in-progress blocked done; do
                mkdir -p "$agent/kanban/$status"
            done
        fi

        hash=$({ cat "$agent/Dockerfile"; printf '%s' "$base_hash"; } | sha256sum | cut -d ' ' -f 1)
        if [ "$(cat "/data/.builds/$name" 2>/dev/null)" != "$hash" ]; then
            docker build -t "agent-$name" - < "$agent/Dockerfile" || continue
            printf '%s\n' "$hash" > "/data/.builds/$name"
        fi

        if [ "$name" = main ]; then
            if ! running main-chat; then
                agent-container main || true
            fi
            continue
        fi

        if running "agent-$name"; then
            continue
        fi
        for task in "$agent"/kanban/todo/*.md "$agent"/kanban/in-progress/*.md; do
            [ -f "$task" ] || continue
            agent-container "$name" || true
            break
        done
    done
    sleep 2
done
