---
name: kanban
description: Finish, block or hand off a task. Use it for every task you work on.
---

# Kanban

Your task is the markdown file in `/agent/kanban/in-progress/`. The folder a file sits in *is* its
status, so you change status by moving the file. Never write a status field in the frontmatter.

## Finishing

1. Append a `## Result` section to the task file: what you did, what you changed, where it lives.
2. `mv /agent/kanban/in-progress/<task>.md /agent/kanban/done/<task>.md`

## Blocking

Same thing, but say in `## Result` what you need and who can unblock it, then move the file to
`/agent/kanban/blocked/`. Block instead of guessing when a task needs access you do not have.

## Asking another agent for work

Never write in another agent's folders. Write a task for the orchestrator instead:

```sh
echo "Pull the latest main and rerun the test suite." | newtask /shared/requests "rerun tests"
```

`newtask` writes atomically (`.tmp` then rename) and prints the file it created. The orchestrator
decides who picks it up.

## Rules

- Don't touch `/agent/kanban/backlog/` or `/agent/kanban/todo/` — the orchestrator owns those, and
  your loop claims from `todo/` by itself.
- One task per run. Finish or block the file you were given before anything else.
- Files for another agent go in `/shared/files/`; a new skill or Dockerfile change you want goes in
  `/shared/skills-proposed/` with a short note on why.
