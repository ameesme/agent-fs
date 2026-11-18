# Changelog

## 0.3.0

### Breaking changes

- `model` in an agent's `agent.json` now wins over `PI_MODEL` in `.env`.
  `PI_MODEL` only sets the model for agents without one.

### Added

- Web chat supports multiline messages (Shift+Enter), shows sent messages
  immediately, and offers a stop button while a reply is running.
- Main can restart agentFS, after you confirm it, to apply changes to any
  agent's instructions, skills and credentials. It writes
  `/data/.control/restart`; the runtime recreates every agent container once
  all agents are idle and logs to `/data/.control/restart.log`.

### Fixed

- Web chat polling skips updates while text in the conversation is selected.

### Upgrading

Run `docker compose up -d --build` to rebuild and recreate the runtime. If you
edited main's `agents` skill, merge the new restart section into your copy.

## 0.2.1

### Fixed

- Chats with an agent use its rebuilt image instead of the one their container
  started with.

## 0.2.0

First versioned release.

### Breaking changes

- Skills are mounted at `/agent/skills/<name>` instead of
  `/agent/home/.agents/skills/<name>`. Update skills that call their own
  scripts by full path.
- `soul.md` is now always part of the agent's system prompt. An `instruction`
  in `agent.json` still works and comes first. Move it into `soul.md`, and
  drop any "Read /agent/soul.md" line so the soul isn't loaded twice.
- The bundled `main`, `poem` and `code` agents moved their instructions from
  `agent.json` to `soul.md`. If you changed those files, expect a merge
  conflict on `git pull`.

### Upgrading

Run `docker compose up -d --build` to rebuild the image.

### Added

- Web channel: chat with any agent and browse, upload, download and delete
  agent and shared files.
- MCP servers in `agent.json` under `mcpServers`, with `${NAME}` values from
  the agent's `.env`.
- Telegram shows tool calls in a status message.

### Fixed

- Boot stops when Docker fails to start.
- Worker agents no longer look for a task file in a direct chat.
- Skills no longer leave empty folders in agent homes.
