---
name: kanban
description: Finish, block or hand off a task.
---

Your task is in `/agent/kanban/in-progress/`. The folder is its status.

Append a `## Result` with what you did and verified, then move the file to `done/`.
If you're blocked, explain what you need and move it to `blocked/` instead.
Preserve the task's frontmatter and id. Work on only the task you were given.

Request work from another agent through the main:

```sh
echo 'What needs doing.' | create-task /shared/requests 'short title'
```

The main decides who picks it up. Leave your own `todo/` and `backlog/` alone.
Put handoff files in `/shared/files/`, and proposed tools or skills in `/shared/skills-proposed/`.
