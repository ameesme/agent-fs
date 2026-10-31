#!/bin/sh
# Start one agent with shared defaults and its own credentials, files and skills.
# Both main's chat environment and sub-agent workers use this setup so permissions
# and mounts stay consistent wherever an agent is started.
set -eu

name=${1:?usage: start-agent <name>}
agent=/data/agents/$name
image=agent-$name
container=$image
if [ "$name" = main ]; then
    container=main-chat
fi

user=$(docker image inspect -f '{{.Config.User}}' "$image")
user=${user:-0}
uid=${user%%:*}
gid=${user#*:}
if [ "$name" != main ]; then
    chown -R "$uid:$gid" "$agent/kanban"
fi
if [ "$(stat -c %u "$agent/home")" != "$uid" ]; then
    chown -R "$uid:$gid" "$agent/home"
fi
chown "$uid:$gid" "$agent/home/memory.md"

docker rm -f "$container" >/dev/null 2>&1 || true
set -- -d --name "$container" -e "AGENT_NAME=$name"
if [ -f /data/shared/.env ]; then
    set -- "$@" --env-file /data/shared/.env
fi
if [ -f "$agent/.env" ]; then
    set -- "$@" --env-file "$agent/.env"
fi
set -- "$@" -v "$agent/home:/agent/home" \
    -v "$agent/agent.json:/agent/agent.json:ro"
if [ -f "$agent/soul.md" ]; then
    set -- "$@" -v "$agent/soul.md:/agent/soul.md:ro"
fi

if [ "$name" = main ]; then
    set -- "$@" -v /data:/data \
        -e GIT_AUTHOR_NAME=main -e GIT_COMMITTER_NAME=main \
        -e GIT_AUTHOR_EMAIL=main@agent-fs.local -e GIT_COMMITTER_EMAIL=main@agent-fs.local
else
    set -- "$@" -v "$agent/kanban:/agent/kanban" \
        -v "$agent/kanban/backlog:/agent/kanban/backlog:ro" \
        -v /data/shared/files:/shared/files -v /data/shared/requests:/shared/requests \
        -v /data/shared/skills-proposed:/shared/skills-proposed
fi

for skill in /data/shared/skills/* "$agent"/skills/*; do
    [ -f "$skill/SKILL.md" ] || continue
    skill_name=${skill##*/}
    case "$skill" in
        /data/shared/*) [ ! -f "$agent/skills/$skill_name/SKILL.md" ] || continue ;;
    esac
    set -- "$@" -v "$skill:/agent/home/.agents/skills/$skill_name:ro"
done

if [ "$name" = main ]; then
    # CLI and bridge invocations share main's mounts but keep separate Pi sessions.
    set -- "$@" --entrypoint sleep
    docker run "$@" "$image" infinity
else
    docker run "$@" "$image"
fi
