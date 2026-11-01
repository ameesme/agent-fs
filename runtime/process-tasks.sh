#!/bin/sh
# Process a sub-agent's queue inside its container, one task at a time.
# Claims each task before calling Pi and blocks unfinished work,
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
    # Keep a fresh session per attempt, grouped by task in the persistent home.
    sessions=/agent/home/.pi/task-sessions/${name%.md}
    mkdir -p "$sessions"
    agent-run --print --session-dir "$sessions" < "$task" || true
    [ -f "$task" ] || continue

    # File-only agents save a completed copy; agents with a shell can move it.
    if [ -f "$kanban/done/$name" ] || [ -f "$kanban/blocked/$name" ]; then
        rm "$task"
    else
        printf '\n## Result\nAgent exited without filing the task.\n' >> "$task"
        mv "$task" "$kanban/blocked/$name"
    fi
done
