---
name: plan
description: Dispatch work to sub-agents, read their results and commit to git. Orchestrator only.
---

# Planning

You see all of `/data`. The agents are the directories in `/data/agents/`; read an agent's
`soul.md` to know what it is for.

## Dispatching

```sh
echo "Clone git@github.com:mees/foo and add a failing test for the bug in parse()." \
  | AGENT_NAME=orchestrator newtask /data/agents/code/kanban/todo "failing test for parse()"
```

Use `todo/` for work that should start now, `backlog/` for work that should wait. The watcher starts
an agent's container within seconds of a file landing in its `todo/`. Never write anywhere else in
another agent's directory.

Requests from the agents themselves arrive in your own `backlog/` (they write them via
`/shared/requests`). Triage those into agent tasks, or block them with a reason.

## Reading results

`/data/agents/<name>/kanban/done/` and `blocked/` hold finished task files with a `## Result`
section. A blocked task is yours to resolve: fix the blocker, dispatch a follow-up, or escalate to
Mees in your own `## Result`.

## Committing

After filing a task, commit what changed in the definitions and memory, with the task id in the
message:

```sh
git -C /data add -A && git -C /data commit -q -m "code: task-20261030-114301-17"
```

`.gitignore` already whitelists what belongs in git: Dockerfiles, souls, agent.yaml, skills and
`memory.md`. Kanban files, workspaces and images stay out. Nothing to commit is fine, say so.
