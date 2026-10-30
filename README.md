# agent-fs

A multi-agent POC in one Docker container. An orchestrator plans, sub-agents run in their own
containers inside it, and every task is a markdown file in a kanban folder. Spec: [docs/PLAN.md](docs/PLAN.md).

## Run it

```sh
cp .env.example .env     # put your ANTHROPIC_API_KEY in it
docker compose up --build
```

First boot seeds `/data` (a named volume) from the image, builds `agent-base`, `agent-code` and
`agent-mail` in the container's own Docker daemon, and starts the watcher.

Throw a task at it:

```sh
curl -X POST localhost:8080 -H 'x-task-title: say hi' --data 'Write hello.txt in the workspace.'
```

That writes a task into the orchestrator's `todo/`. The watcher notices within a couple of seconds
and starts the orchestrator container, which plans and hands work to `code` or `mail`.

Without a key the plumbing still runs: the task gets claimed, the model call fails, and the loop
files the task in `blocked/`. `docker compose exec agents docker run --rm --entrypoint docker-agent
agent-code doctor /agent/agent.yaml` says which credentials an agent is missing. The host-side
checks on the mount table and `newtask` are `python3 test_agent_fs.py`.

Poke around:

```sh
docker compose exec agents sh -c 'ls /data/agents/code/kanban/*'
docker compose exec agents docker ps -a         # the inner daemon
docker compose exec agents docker logs agent-code
```

## How it works

- **main container** (`docker:dind`, privileged) runs `dockerd --data-root /data/docker`, the
  watcher, and an HTTP task endpoint on 8080.
- **watcher** (`watcher.py`, stdlib only) builds images when a Dockerfile changes, starts an agent
  container when its `todo/` is non-empty, and drops a review task on the orchestrator when a
  sub-agent finishes.
- **agent container** runs `agent-loop`: claim the oldest task (`mv todo/x in-progress/x`), run
  `docker-agent run --exec`, repeat until `todo/` is empty, then exit. No idle containers.
- **agent** finishes a task by filling in `## Result` and moving the file to `done/` (or `blocked/`),
  per the `kanban` skill.

Task files, kanban rules and the mount table are all in the spec. The short version: an agent can
write its own `home/`, its own `in-progress|blocked|done`, `/shared/files` and `/shared/requests`,
and nothing else.

## Layout

```
Dockerfile compose.yaml entrypoint.sh watcher.py   # the main container
seed/                                              # copied into /data on first boot
├── base/{Dockerfile,agent-loop,newtask}           # agent-base
├── agents/{orchestrator,code,mail}/               # Dockerfile, soul.md, agent.yaml, skills/
└── shared/skills/{kanban,memory}/SKILL.md
```

`/data` is persistent state: the seeded definitions plus `home/`, `kanban/` and the git repo.
Editing a seeded file in `/data` wins — the seed only fills in what's missing.

## Secrets

`.env` next to `compose.yaml`. Every agent gets `ANTHROPIC_API_KEY`; an agent also gets the vars
prefixed with its own name, so `MAIL_SMTP_PASS` only reaches `mail` and `CODE_GITHUB_TOKEN` only
reaches `code`. Nothing lands in an image or in git.

## Where this differs from the spec

- **Polling, not inotify.** The watcher scans the `todo/` dirs every 2s. The spec asked for inotify
  plus a 60s rescan; polling is ~3 lines, has no deps, and beats the 60s requirement anyway. Add
  inotify when the task count makes scanning expensive.
- **Rebuilds on content hash**, not on a git commit touching a Dockerfile. Same effect, no hook, and
  it also catches uncommitted edits.
- **Orchestrator runs in its own container** (`agent-orchestrator`, as root with `/data` rw) instead
  of in the main container's process. Same mounts as the table in the spec, one code path for all
  agents.
- **`docker-agent` standalone binary** instead of the `docker agent` CLI plugin — no Docker CLI
  needed inside an agent container.
- **Task ids are timestamps** (`task-20261030-114301-17`) instead of a 4-digit counter, so an agent
  can mint one without seeing the other agents' folders.
- **`/shared/requests`** is the orchestrator's `backlog/`, mounted rw into every sub-agent. The spec
  wants sub-agents to request work there but its mount table left it out.
- **Models**: `claude-opus-5-5` for the orchestrator, `claude-sonnet-5-5` for sub-agents. The spec's
  `claude-sonnet-4-5` is deprecated (retires 2026-11-30).
