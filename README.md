# agentFS

Folders hold agents. Markdown files hold tasks. Docker Agent does the work.

Tasks move through `todo → in-progress → done` or `blocked`. A shell loop starts
agents when work arrives. Main delegates work and reviews the results.

## Getting started

- Install Docker
- Clone this repo
- Copy `data/shared/.env.example` to `data/shared/.env`
- Add your LLM provider's API key, e.g. `OPENAI_API_KEY=your-api-key`.
  See [Docker Agent's model setup][llm] for other providers
- Run `docker compose up -d --build` to start the main agent
- Run `docker compose exec agents chat` to open the built-in CLI bridge to chat

### What's included

Two agents are included in `data/agents/` as a demo-setup:

- **main**: the primary agent that you can chat with, which also coordinates
  tasks
- **poems**: writes poems

### Instructions

Ask: `Ask poem to write a short poem about a quiet morning.` Main will create a
task for poem, waits for it to finish, and replies with the poem.
`/reset` starts a fresh conversation; `/quit` or Ctrl-D exits.

It is really easy to introduce new agents yourself, see
[Add an agent](#add-an-agent).

## Add an agent

Copy an [example folder](agents) into `data/agents/` or create your own, then
optionally configure its `.env`, `soul.md` and skills. The runtime automatically
creates a workspace, memory and task folders, and rebuilds the image when they
change.

```sh
cp -R agents/code data/agents/
cp data/agents/code/.env.example data/agents/code/.env
```

An agent needs `agent.yaml` and a `Dockerfile`. Everything else is optional.

## Shared

- `data/shared/.env`: credentials for all agents; an agent's own `.env`
  overrides shared values. Both are ignored by Git.
- `data/shared/skills/`: common skills; an agent's own skills override shared
  skills with the same name.
- Shared files, requests and proposed skills also live here and stay ignored
  by Git.
- Restart agentFS after changing main's credentials or shared skills.

## Bridges

By default agentFS uses the CLI-bridge, allowing you to chat with the main agent
over your terminal. You can however easily introduce other bridges, by
configuring a `BRIDGE_COMMAND`.

**Telegram**
Set `BRIDGE_COMMAND=sh /bridges/telegram.sh`, `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_IDS` in the root `.env`, then run `docker compose up -d` or
optionally restart the container.

[MIT](LICENSE).

[llm]: https://docs.docker.com/ai/docker-agent/getting-started/set-up-a-model/
