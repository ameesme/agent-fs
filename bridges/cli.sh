#!/bin/sh
# Open Pi's native terminal UI for main; the extension delivers queued task updates.
set -eu

printf 'Waiting for main (the first build can take a while)...\n'
until [ "$(docker inspect -f '{{.State.Running}}' main-chat 2>/dev/null)" = true ]; do
    sleep 2
done

exec docker exec -it -e AGENT_FS_NATIVE=1 main-chat agent-run "$@"
