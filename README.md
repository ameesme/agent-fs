# agentFS

Folders hold agents. Markdown files hold tasks. Docker Agent does the work.

Tasks move through `todo → in-progress → done` or `blocked`. A shell loop starts
agents when work arrives. Main delegates work and reviews the results.

## Getting started

- Install Docker
- Clone this repo
- Run `docker compose up -d --build` to start the main agent
- Run `docker compose exec agents chat` to open the built-in CLI bridge to chat

### Instructions

Ask: `Ask poem to write a short poem about a quiet morning.` Main will create a
task for poem, waits for it to finish, and replies with the poem.
`/reset` starts a fresh conversation; `/quit` or Ctrl-D exits.

### What's included

Two agents are included in `data/agents/` as a demo-setup:

- **main**: the primary agent that you can chat with, which also coordinates
  tasks
- **poems**: writes poems

It is really easy to introduce new agents yourself, see
[Add an agent](#add-an-agent).

## Add an agent

Copy an [example folder](agents) into `data/agents/`, then optionally configure
its own `.env`, `soul.md` and skills. The runtime automatically creates its
workspace, memory and task folders, and rebuilds its image when its changes.

```sh
cp -R agents/code data/agents/
cp data/agents/code/.env.example data/agents/code/.env
```

An agent needs `agent.yaml` and a `Dockerfile`. Everything else is optional.

## Bridges

By default agentFS uses the CLI-bridge, allowing you to chat with the main agent
over your terminal. You can however easily introduce other bridges, by
configuring a `BRIDGE_COMMAND`.

**Telegram**
Set `BRIDGE_COMMAND=sh /bridges/telegram.sh`, `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_IDS` in the root `.env`, then run `docker compose up -d` or
optionally restart the container.

[MIT](LICENSE).

[credentials]: https://docs.docker.com/ai/docker-agent/guides/secrets/
