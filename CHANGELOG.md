# Changelog

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
