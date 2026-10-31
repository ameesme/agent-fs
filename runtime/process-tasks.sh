#!/bin/sh
# Process a sub-agent's queue inside its container, one task at a time.
# Claims each task before calling Docker Agent and blocks unfinished work,
# so interrupted or failed runs do not silently disappear or get retried.
set -eu

kanban=/agent/kanban

# A restart must not silently repeat a task's side effects.
for task in "$kanban"/in-progress/*.md; do
    [ -f "$task" ] || continue
    printf '\n## Result\nInterrupted by a container restart. Review before retrying.\n' >> "$task"
    mv "$task" "$kanban/blocked/${task##*/}"
done

# Timestamped filenames put older tasks first. New arrivals run on the next pass.
for queued in "$kanban"/todo/*.md; do
    [ -f "$queued" ] || continue
    name=${queued##*/}
    task=$kanban/in-progress/$name
    mv "$queued" "$task" 2>/dev/null || continue

    printf '=== %s\n' "$name"
    docker-agent run --exec /agent/agent.yaml --yolo -- "$(cat "$task")" || true
    [ -f "$task" ] || continue

    # File-only agents save a completed copy; agents with a shell can move it.
    if [ -f "$kanban/done/$name" ] || [ -f "$kanban/blocked/$name" ]; then
        rm "$task"
    else
        printf '\n## Result\nAgent exited without filing the task.\n' >> "$task"
        mv "$task" "$kanban/blocked/$name"
    fi
done
