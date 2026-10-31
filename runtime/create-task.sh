#!/bin/sh
# Create a Markdown task from a title and a request passed through stdin.
# Adds an id and metadata, then moves the finished file into the queue so
# the runtime never picks up a half-written request.
set -eu

queue=${1:?usage: create-task <kanban-dir> <title>   (task body on stdin)}
title=${2:?usage: create-task <kanban-dir> <title>   (task body on stdin)}

id="task-$(date -u +%Y%m%d-%H%M%S)-$$"
temporary=$queue/.$id.md.tmp
task=$queue/$id.md
trap 'rm -f "$temporary"' EXIT

{
    printf '%s\n' '---' \
        "id: $id" \
        "created: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "created_by: ${AGENT_NAME:-user}" \
        "priority: ${PRIORITY:-normal}"
    if [ -n "${PARENT:-}" ]; then
        printf 'parent: %s\n' "$PARENT"
    fi
    if [ -n "${GROUP:-}" ]; then
        printf 'group: %s\n' "$GROUP"
    fi
    printf '%s\n' '---' "# $title" ''
    cat
} > "$temporary"

mv "$temporary" "$task"
printf '%s\n' "$task"
