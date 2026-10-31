---
name: task
description: Dispatch work to sub-agents, read their results and commit to git. Main only.
---

# Tasks

You see all of `/data`. The agents are the directories in `/data/agents/`; read an agent's
`agent.yaml` to know what it is for.

Turn requests into the fewest useful tasks. Describe the outcome and let each agent choose how
to do it. Only change agent definitions when the user asks.

## Dispatching

```sh
echo "Write a short poem about a quiet morning." \
  | AGENT_NAME=main newtask /data/agents/poem/kanban/todo "quiet morning"
```

Use `todo/` for work that should start now, `backlog/` for work that should wait. The runtime starts
an agent's container within seconds of a file landing in its `todo/`. Never write anywhere else in
another agent's directory.

Requests from agents arrive in `/data/shared/requests/` (mounted as `/shared/requests`). Triage those into agent tasks, or block them with a reason.

## Reading results

`/data/agents/<name>/kanban/done/` and `blocked/` hold finished task files with a `## Result`
section. A blocked task is yours to resolve: fix the blocker, dispatch a follow-up, or escalate to
the user in chat. Track the exact task filename returned by `newtask`. Check for that file in
`done/` or `blocked/`, pausing a few seconds between checks. Keep checking until it finishes or
you find a concrete blocker. Read its `## Result` and report it to the user in this conversation.
For a poem, return the poem itself. Creating the task is not the finished answer.

## Committing

After reviewing a finished task, commit what changed in the definitions and memory, with the task id in the
message:

```sh
git -C /data add -A && git -C /data commit -q -m "code: task-20261030-114301-17"
```

`.gitignore` already whitelists what belongs in git: Dockerfiles, souls, agent.yaml, skills and
`memory.md`. Kanban files, workspaces and images stay out. Nothing to commit is fine, say so.
