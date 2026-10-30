#!/bin/sh
set -e

dockerd-entrypoint.sh --data-root /data/docker &

cd /seed
find . -type f | while read -r f; do
  [ -e "/data/$f" ] || { mkdir -p "/data/$(dirname "$f")"; cp "/seed/$f" "/data/$f"; }
done
cd /

for a in /data/agents/*/; do
  mkdir -p "$a/home/workspace" "$a/kanban/backlog" "$a/kanban/todo" \
           "$a/kanban/in-progress" "$a/kanban/blocked" "$a/kanban/done"
  [ -f "$a/home/memory.md" ] || echo "# memory" > "$a/home/memory.md"
done
mkdir -p /data/shared/files /data/shared/skills-proposed
# every agent runs under its own uid, so the handoff dirs are shared like /tmp
chmod 1777 /data/shared/files /data/shared/skills-proposed /data/agents/orchestrator/kanban/backlog

git config --global --add safe.directory /data
if [ ! -d /data/.git ]; then
  git -C /data init -q
  git -C /data add -A
  git -C /data -c user.name=orchestrator -c user.email=orchestrator@agent-fs.local \
    commit -q -m "init: seeded agent definitions"
fi

until docker info >/dev/null 2>&1; do sleep 1; done

exec python3 /usr/local/bin/watcher.py
