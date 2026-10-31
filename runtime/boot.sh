#!/bin/sh
# Boot agentFS: prepare shared folders and Git, then start the folder watcher.
# Runs Docker inside the main container so agents get their own containers
# without needing access to the host's Docker socket.
set -eu

dockerd-entrypoint.sh dockerd --host=unix:///var/run/docker.sock --data-root /data/docker &

mkdir -p /data/agents /data/shared/files
chmod 1777 /data/shared/files
cp /etc/agent-fs.gitignore /data/.gitignore

git config --global --add safe.directory /data
if [ ! -d /data/.git ]; then
    git -C /data init -q
    git -C /data add -A
    git -C /data -c user.name=main -c user.email=main@agent-fs.local \
        commit -q -m "init: agent filesystem"
fi

until docker info >/dev/null 2>&1; do
    sleep 1
done

exec watch-fs "$@"
