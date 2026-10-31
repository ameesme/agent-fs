# agentFS

Folders hold agents. Markdown files hold tasks. Pi does the work.

Tasks move through `todo → in-progress → done` or `blocked`. A shell loop starts
agents in Docker containers when work arrives. Main delegates work and reports results.

## Getting started

- Install Docker and clone this repo
- Copy `data/shared/.env.example` to `data/shared/.env`
- Add your provider's API key, e.g. `OPENAI_API_KEY=your-api-key`.
  See [Pi's provider setup][llm] for other providers
- Run `docker compose up -d --build`
- Run `docker compose exec agents chat` to open Pi's native CLI

Two demo agents are included: **main** coordinates tasks; **poem** writes poems.
Ask: `Ask poem to write a short poem about a quiet morning.` Main dispatches it
and reports back when it finishes. You can keep chatting while poem works.

Use Pi's `/help` for commands. Resume with
`docker compose exec agents chat --continue`, or choose a session with `--resume`.

## Add an agent

Copy an [example folder](agents) into `data/agents/`:

```sh
cp -R agents/code data/agents/
cp data/agents/code/.env.example data/agents/code/.env
```

An agent needs `agent.json` and a `Dockerfile`. Everything else is optional.
The JSON defines its instructions, tools, skills and optional model. Set `PI_MODEL`
in `.env` to override the model. Customize its `soul.md` and skills as needed.
The runtime creates its workspace, memory and task folders, and builds its image.

## Cron

Ask main to schedule recurring work. Schedules live in each worker's `cron/` folder
and create ordinary tasks. Set `TZ` in the root `.env` for local time (default UTC).
See the [task skill](data/agents/main/skills/task/SKILL.md#scheduling) for the format.

## Shared

- `data/shared/.env`: credentials for all agents; an agent's own `.env` overrides them
- `data/shared/skills/`: common skills; an agent's own skills override matching names
- Shared files also live here and stay ignored by Git
- Restart agentFS after changing main's credentials or shared skills

## Bridges

The CLI opens Pi's terminal UI. For Telegram, set
`BRIDGE_COMMAND=sh /bridges/telegram.sh`, `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_IDS` in the root `.env`, then run `docker compose up -d`.
Each Telegram chat has its own conversation; `/new` or `/reset` starts a fresh one.

[MIT](LICENSE).

[llm]: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md
