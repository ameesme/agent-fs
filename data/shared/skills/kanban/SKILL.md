---
name: kanban
description: Finish, block or hand off a task.
---

Your task is in `/agent/kanban/in-progress/`. The folder is its status.

Append a `## Result` with what you did and verified, then move the file to `done/`.
If you're blocked, explain what you need and move it to `blocked/` instead.
Preserve the task's frontmatter and id. Work on only the task you were given.

Include any relevant follow-up requests or proposed tools and skills in the task's
`## Result`. Main reviews them and decides what happens next.
Leave your own `todo/` and `backlog/` alone. Put handoff files in `/shared/files/`
and reference their paths in the result.
