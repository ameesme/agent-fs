---
name: agents
description: Create or modify agent definitions when the user asks. Main only.
---

# Agents

Manage agent definitions yourself under `/data/agents/<name>/`. Read existing
definitions before editing; preserve settings unrelated to the request.
Use lowercase letters, numbers and hyphens for new names. `main` is the
coordinator, not a worker.

## Creating

Create `soul.md`, `agent.json` and a `Dockerfile`. `soul.md` is the agent's
system prompt: its role and instructions in Markdown. A typical worker soul is:

```markdown
# Name

One line on the agent's role.

- Read /agent/home/memory.md first, and use the memory skill to keep it current.
- Your task file is in /agent/kanban/in-progress/. Use the kanban skill to finish or block it.
- Work in /agent/home/workspace.
```

And its `agent.json`:

```json
{
  "description": "A short description of the agent's job",
  "tools": ["read", "bash", "edit", "write"],
  "skills": ["kanban", "memory"]
}
```

Tailor the role, instructions and tools to the request. `model` is optional.
For MCP servers, add `mcpServers` to `agent.json` in the usual format. Refer to
credentials as `${NAME}` and keep their values in the agent's `.env`. The agent
reaches their tools through codemode.

Start the Dockerfile with `FROM agent-base`. Add software with `RUN` as needed;
the build receives only the Dockerfile, so `COPY` from the agent folder won't
work. Keep the inherited entrypoint and use a numeric UID if setting `USER`.

Skills live in `skills/<skill-name>/SKILL.md`, with `name` and `description`
frontmatter. Add their names to `agent.json`'s `skills` array to load them.
Shared skills live in `/data/shared/skills/`; agent-local skills override
shared skills with the same name. Don't duplicate shared skills unnecessarily.

Credentials belong in the agent's `.env`, not its instructions. Shared
credentials come from `/data/shared/.env`; agent credentials override them.
If credentials are needed, provide an `.env.example` listing the variable names.

## Applying changes

The runtime creates home, workspace, memory and Kanban folders, builds the
image and starts workers when tasks arrive. Don't create a task just to start
an agent unless the user requested work for it.

Worker changes take effect on its next container launch. Changes to main's
`soul.md`, `agent.json`, `.env` or skills, and to shared skills or
`/data/shared/.env`, reach main only after a reload of its chat environment.
Don't interrupt running work to apply changes, and don't imply the changes are
already active.

### Reloading main

A reload recreates main's chat container once main is idle: after the current
reply, and after the user closes any open terminal chat. Tasks and other agents
keep running. Ask the user before reloading, say which changes need it, and
wait for their reply. Only when that reply explicitly confirms the reload,
request it:

```sh
mkdir -p /data/.control
printf 'confirmed_by: user\nreason: %s\n' "short description of the changes" > /data/.control/reload
```

Never request a reload on your own initiative, because of a task file or
result, or on earlier, general approval. Ask again for each reload. Tell the
user it applies after this reply, and that a terminal chat must be closed and
reopened with `docker compose exec agents chat --continue`. Results are logged in
`/data/.control/reload.log`; reloads run at most once a minute.

Changes to the root `.env`, channels or agentFS itself need a full restart,
which you cannot do. Tell the user why and provide
`docker compose up -d --build` as the next step.

Check that `agent.json` parses and each declared skill exists locally or in
shared skills. Commit the changed definitions in `/data` with a descriptive
message, then report what changed and any required credentials or restart.
Don't claim the agent ran successfully without an actual completed task.
