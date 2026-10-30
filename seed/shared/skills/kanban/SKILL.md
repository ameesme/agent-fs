---
name: kanban
description: Finish, block or hand off a task. Use it for every task you work on.
---

# Kanban

Your task is the markdown file in `/agent/kanban/in-progress/`. The folder a file sits in *is* its
status, so you change status by moving the file. Never write a status field in the frontmatter.

## Finishing

1. Append a `## Result` section to the task file: what you did, what you changed, where it lives.
2. `checktask /agent/kanban/in-progress/<task>.md` — it prints nothing when the file is fine.
3. `mv /agent/kanban/in-progress/<task>.md /agent/kanban/done/<task>.md`

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

## Keeping the file valid

`checktask <file>` is the judge. It wants: the frontmatter block first, `id` matching the filename,
`created`, `created_by` and `priority` present, no other keys, a `# title` heading, and a non-empty
`## Result` once the file sits in `done/` or `blocked/`.

Append to the task file, don't rewrite it. Never touch the frontmatter — not the id, not `created`,
and never add a `status` key, because the folder is the status. A task that lands in `done/` or
`blocked/` broken gets moved back to `blocked/` with the errors appended, so you get to fix it.

## Rules

- Don't touch `/agent/kanban/backlog/` or `/agent/kanban/todo/` — the orchestrator owns those, and
  your loop claims from `todo/` by itself.
- One task per run. Finish or block the file you were given before anything else.
- Files for another agent go in `/shared/files/`; a new skill or Dockerfile change you want goes in
  `/shared/skills-proposed/` with a short note on why.
