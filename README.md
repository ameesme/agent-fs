# agentFS

Simple, filesystem-based orchestration for AI agents.

**Includes**

- A main chat-agent that delegates work and reports back results
- Separate Docker containers, tools, skills and instructions for each agent
- File-based Kanban, persistent workspaces and memory
- File-based Cron schedules for recurring tasks
- Git-based version control for agent definitions, skills, schedules and memory
- Pi's terminal UI and an optional Telegram channel
- Code and poem agents included

## In a nutshell

Each agent is a folder with its own instructions, tools and Docker image.
Tasks are Markdown files in that agent's `kanban/` folder. Moving a task between
`todo`, `in-progress`, `done` and `blocked` changes the task's status.

`main` stays available for chat and delegates work by creating task files.
agentFS starts agent containers as tasks arrive. When a task finishes or gets
blocked, `main` is notified and reports back to you.

## Getting started

- Install Docker and clone this repo
- Copy `data/shared/.env.example` to `data/shared/.env`
- Add your provider's API key, e.g. `OPENAI_API_KEY=your-api-key`.
  See [Pi's provider setup][llm] for other providers
- Run `docker compose up -d --build`
- Run `docker compose exec agents chat` to open Pi's native CLI

### The main agent

By default, a `main` agent is included, which is responsible for coordinating
tasks and reporting the results back to you in a chat.

### Demo

As an example, `poem` is included as an agent by default too. As its name
suggests, it writes poems, including a cron-based daily poem.

Ask main: `Have poem write a short poem about a quiet morning.` Main dispatches
the task and reports back when it finishes. You can keep chatting while poem
works.

Use Pi's `/help` for commands. Resume with
`docker compose exec agents chat --continue`, or choose a session with
`--resume`.

## Adding other agents

Ask `main` to create an agent, or add a folder under `data/agents/` yourself.
An agent needs just `agent.json` and a `Dockerfile`. Everything else is optional.

**agent.json**

`agent.json` is agentFS's configuration for Pi. It defines the agent's
instructions, tools, skills and optional model. Customize its `soul.md` and
`skills/` as needed.

**Dockerfile**

Use `FROM agent-base` for Pi, Python and the task runtime. Add any other
software your agent needs, for example, the included code agent adds Claude Code, tmux and
Chromium.

agentFS creates workspace, memory and task folders, and builds the agent's
image. It rebuilds the image when its Dockerfile or the base image definition changes.

## Cron

Define recurring tasks as Markdown files in each worker's `cron/` folder. Ask
`main` to set up a schedule, or copy [poem's example][daily-poem].

## Shared

- `data/shared/.env`: shared credentials; an agent's own `.env` overrides them
- `data/shared/skills/`: common skills; an agent's own skills override matching
  names
- Shared files also live here and stay ignored by Git
- Restart agentFS after changing main's credentials or shared skills

## Channels

The default way to interact with `main` is through Pi's terminal UI. However, by
setting a custom `CHANNEL_COMMAND`, you can enable other ways.

### Telegram
For Telegram, set `CHANNEL_COMMAND=sh /channels/telegram.sh`, `TELEGRAM_BOT_TOKEN`
and `TELEGRAM_CHAT_IDS` in the root `.env`, then run `docker compose up -d`.
If you have a dedicated chat bot, set `TELEGRAM_CHAT_BOT_TOKEN`; the channel uses
that token instead of `TELEGRAM_BOT_TOKEN`.

Each Telegram chat has its own conversation; `/new` or `/reset` starts a fresh
one.

[MIT](LICENSE).

[llm]: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md
[daily-poem]: data/agents/poem/cron/daily-poem.md
