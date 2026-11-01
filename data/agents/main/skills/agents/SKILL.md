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

Create `agent.json` and a `Dockerfile`. A typical worker configuration is:

```json
{
  "description": "A short description of the agent's job",
  "instruction": "Read /agent/home/memory.md first. Follow the kanban skill to finish or block your assigned task and the memory skill to keep memory current. Work in /agent/home/workspace.",
  "tools": ["read", "bash", "edit", "write"],
  "skills": ["kanban", "memory"]
}
```

Tailor the role, instructions and tools to the request. `model` is optional.
For a separate personality or role file, create `soul.md` and explicitly tell
the agent to read `/agent/soul.md` in its instruction.

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
configuration or mounts require restarting agentFS. Don't interrupt running
work to apply changes.
If a restart is required, explicitly tell the user why and provide
`docker compose restart agents` as the next step. Don't imply the changes are
already active.

Check that `agent.json` parses and each declared skill exists locally or in
shared skills. Commit the changed definitions in `/data` with a descriptive
message, then report what changed and any required credentials or restart.
Don't claim the agent ran successfully without an actual completed task.
