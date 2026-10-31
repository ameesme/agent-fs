---
name: task
description: Dispatch work to sub-agents, read their results and commit to git. Main only.
---

# Tasks

You see all of `/data`. The agents are the directories in `/data/agents/`; read an agent's
`agent.json` to know what it is for.

Turn requests into the fewest useful tasks. Describe the outcome and let each agent choose how
to do it. Only change agent definitions when the user asks.

## Dispatching

```sh
agent=chosen-agent
echo "Describe the requested outcome." \
  | GROUP=conversation-id create-task "/data/agents/$agent/kanban/todo" "task title"
```

Use `todo/` for work that should start now, `backlog/` for work that should wait. The runtime starts
an agent's container within seconds of a file landing in its `todo/`. Only write task queues
and, when requested, cron schedules in another agent's directory.

Set `GROUP` to the Conversation id supplied by the runtime.
Use the actual id from the current context, including when creating follow-up tasks.
Tell the user what you created and that you will report back when there is an update.
Return immediately; do not poll or wait for the task.

## Scheduling

When asked for recurring work, write `/data/agents/<worker>/cron/<name>.md`.
Use a flat frontmatter with `schedule: "0 9 * * 1-5"`, `enabled: true`, and
`group: conversation-id` for updates to the requesting chat. Below the closing
`---`, write the task title and request as usual. Names use letters, numbers,
hyphens and underscores. Schedules use numeric five-field cron and the runtime's
shared `TZ` (UTC by default). Do not schedule main. Changes reload within a minute.
Disable with `enabled: false` or delete the file. Pending runs prevent overlap;
missed runs are skipped.

## Reading results

`/data/agents/<name>/kanban/done/` and `blocked/` hold finished task files with a `## Result`
section. A blocked task is yours to resolve: fix the blocker, dispatch a follow-up, or escalate to
the user in chat. Results may include follow-up requests or proposed tools and skills;
review these with the result and decide what to dispatch or raise with the user.
The filesystem watcher sends updates with the task path and its new status.
For a done task, say what finished and ask whether the user wants to see its result.
Do not paste the result into the notification or announce in-progress tasks.
When the user asks to see a result, read the task and share it.

## Committing

After reviewing a finished task, commit what changed in the definitions and memory, with the task id in the
message:

```sh
git -C /data add -A && git -C /data commit -q -m "code: task-20261030-114301-17"
```

`.gitignore` already whitelists what belongs in git: Dockerfiles, souls, agent.json, skills and
`memory.md`. Kanban files, workspaces and images stay out. Nothing to commit is fine, say so.
