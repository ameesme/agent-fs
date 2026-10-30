# Agent-systeem POC spec

Oct 29, 2026 · @Mees

## Doel

Een multi-agent systeem in één Docker-container: een orchestrator die sub-agents in eigen containers draait, met taken als markdown-bestanden in kanban-mappen. Elke sub-agent heeft een eigen file system plus een gedeeld deel. Draait op Linux, macOS en Windows.

POC-scope: één orchestrator en twee sub-agents (`code`, `mail`), één instance per agent-type, taken serieel. Eenvoud boven features.

## Architectuur

Alles draait in één hoofdcontainer met een eigen Docker daemon (DinD, Docker-in-Docker). De sub-agent-containers leven daarbinnen; op de host is alleen de hoofdcontainer zichtbaar. Linux met Docker Engine, macOS en Windows met Docker Desktop (daar draait alles in de Linux-VM van Docker Desktop, dus het gedrag binnen de container is overal gelijk).

- **Hoofdcontainer:** basis `docker:dind` (Alpine), gestart met `privileged`. Draait `dockerd`, de orchestrator-agent en de watcher.
- **Sub-agent-images:** elke agent heeft een eigen `Dockerfile`, met `FROM agent-base`. `agent-base` bevat wat elke agent nodig heeft (Docker Agent, Python, `jq`, `git`); de agent-Dockerfile voegt de eigen tools toe, bijvoorbeeld Claude Code en Chromium voor `code`. Elke agent draait onder een eigen UID (`code` = 1001, `mail` = 1002).
- **Geen host-socket mounten.** Sub-agents horen binnen de hoofdcontainer, niet op de host-Docker.

Starten (`compose.yaml`):

```yaml
services:
  agents:
    build: .
    privileged: true
    volumes:
      - agents-data:/data
    ports:
      - "8080:8080"   # taak-endpoint
volumes:
  agents-data:
```

`dockerd --data-root /data/docker`. `/data` is een named volume, geen bind mount naar een hostmap: op macOS en Windows werken overlay2, inotify en UID-rechten niet betrouwbaar op gedeelde hostmappen. Bestanden inzien via `docker exec` of `docker cp`; op Linux mag `/data/agents` wel een bind mount zijn.

## Filesystem en mounts

```
/data/
├── .git/                      # config van alle agents, zie Soul, memory en git
├── docker/                    # data-root van dockerd
├── base/
│   └── Dockerfile             # agent-base
├── agents/
│   ├── orchestrator/          # zelfde opbouw als code
│   ├── code/
│   │   ├── Dockerfile         # FROM agent-base + eigen tools
│   │   ├── soul.md
│   │   ├── agent.yaml
│   │   ├── skills/            # agent-specifieke skills
│   │   ├── home/              # $HOME van de agent, persistent
│   │   │   ├── memory.md
│   │   │   └── workspace/     # repo's en werkbestanden
│   │   └── kanban/
│   │       ├── backlog/
│   │       ├── todo/
│   │       ├── in-progress/
│   │       ├── blocked/
│   │       └── done/
│   └── mail/  (zelfde opbouw)
└── shared/
    ├── skills/                # gedeelde toolset
    ├── skills-proposed/       # door agents voorgestelde skills en Dockerfile-wijzigingen
    └── files/                 # handoff van bestanden
```

De agent-map is de definitie van de agent (`Dockerfile`, `soul.md`, `agent.yaml`, `skills/`); `home/` en `kanban/` zijn runtime-state.

| Container | Mount | Pad in container | Modus |
| --- | --- | --- | --- |
| orchestrator | `/data` | `/data` | rw |
| sub-agent | `/data/agents/<naam>/soul.md` | `/agent/soul.md` | ro |
| sub-agent | `/data/agents/<naam>/agent.yaml` | `/agent/agent.yaml` | ro |
| sub-agent | `/data/agents/<naam>/home` | `/agent/home` (= `$HOME`) | rw |
| sub-agent | `/data/agents/<naam>/kanban` | `/agent/kanban` | rw |
| sub-agent | `/data/agents/<naam>/kanban/backlog` | `/agent/kanban/backlog` | ro |
| sub-agent | elke skill uit `/data/shared/skills/` en `/data/agents/<naam>/skills/` | `$HOME/.agents/skills/<skill>` | ro |
| sub-agent | `/data/shared/files`, `/data/shared/skills-proposed` | `/shared/...` | rw |

`agent-base` zet `HOME=/agent/home`, zodat dotfiles en caches (Claude Code-config, Chromium-profiel, `.gitconfig`) persistent zijn. Skills worden per skill-map gemount, omdat gedeelde en agent-specifieke skills samen in de standaard skill-map van Docker Agent moeten staan; bij een naamconflict wint de agent-specifieke.

De `Dockerfile` van een agent wordt niet in diens container gemount; een agent kan zijn eigen image dus niet aanpassen, alleen een wijziging voorstellen via `skills-proposed/`.

De orchestrator draait als root binnen de hoofdcontainer en kan dus in alle agent-mappen.

## Kanban

Elke taak is één markdown-bestand; de map waarin het staat is de status. Status staat nooit in de frontmatter.

Bestandsnaam: `task-<id>.md`. Formaat:

```markdown
---
id: task-0142
created: 2026-10-29T14:00:00+01:00
created_by: orchestrator
priority: normal
parent: task-0139        # optioneel
group: auth-refactor     # optioneel
---
# Korte titel

Opdracht in gewone taal.

## Resultaat
(door de agent ingevuld bij done of blocked)
```

**Wie schrijft waar:**

| Map | Schrijver |
| --- | --- |
| `backlog/`, `todo/` van een sub-agent | alleen orchestrator (of Mees) |
| `in-progress/`, `blocked/`, `done/` | alleen de agent zelf |
| alle mappen van `orchestrator/kanban/` | orchestrator |

**Regels:**

1. Nieuwe taak: schrijf als `.task-<id>.md.tmp`, dan `rename` naar `task-<id>.md`. Nooit direct in de doelmap schrijven.
2. Claimen: `rename todo/x.md in-progress/x.md`. Mislukt met `ENOENT` → iemand anders had hem al, volgende pakken. Geen lockfiles.
3. Backlog wordt nooit door een agent opgepakt; de orchestrator verplaatst backlog → todo.
4. Sub-agent wil werk bij een andere agent → nieuwe taak in `orchestrator/kanban/backlog/`, nooit rechtstreeks in een andere agent.

## Orchestrator en watcher

De orchestrator bestaat uit twee delen: een watcher (gewoon script, geen LLM) en een orchestrator-agent (Docker Agent met filesystem-toegang tot `/data/agents` en `/data/shared`).

**Watcher:**

- inotify op alle `kanban/todo/`-mappen, events `IN_MOVED_TO` en `IN_CLOSE_WRITE`. Bestanden die met `.` beginnen negeren.
- Daarnaast een rescan elke 60 s, voor gemiste events en na een herstart.
- Nieuwe taak in `agents/<naam>/kanban/todo/` en container van `<naam>` draait niet → container starten.
- Container stopt zelf als zijn `todo/` leeg is. Geen idle containers.
- Taak in `orchestrator/kanban/todo/` → orchestrator-agent aanroepen met die taak.

**Orchestrator-agent:** plant werk door taakbestanden te schrijven (backlog of todo van een sub-agent), leest resultaten uit `done/` en `blocked/`, en commit memory-wijzigingen naar git. Gerelateerde taken voegt die samen tot één taak met een checklist.

**Images bouwen:** bij het opstarten en na elke commit die `base/Dockerfile` of een `agents/<naam>/Dockerfile` wijzigt, bouwt de orchestrator in de interne `dockerd`: eerst `agent-base`, dan `agent-<naam>`. De watcher start sub-agents altijd met `agent-<naam>:latest`.

**Secrets** (API-keys voor modellen, Claude Code, mail) staan nooit in een Dockerfile of in git. Ze staan in een `.env` naast `compose.yaml`; de orchestrator geeft per agent alleen de benodigde variabelen mee als environment bij het starten van de container.

**Invoer van buitenaf** (chat, webhooks, Telegram): buiten POC-scope behalve één simpele manier om een taak in `orchestrator/kanban/todo/` te zetten, bijvoorbeeld een HTTP-endpoint dat een markdown-body als taakbestand wegschrijft.

## Agent-runtime en skills

Elke sub-agent-container draait een loop over zijn eigen `todo/`: claim de oudste taak (rename naar `in-progress/`), roep Docker Agent aan, herhaal tot `todo/` leeg is, stop.

```bash
docker agent run --exec /agent/agent.yaml --yolo "$(cat /agent/kanban/in-progress/task-0142.md)"
```

**agent.yaml per agent:** één agent, eigen model, `filesystem`- en `shell`-toolset, skills gefilterd op naam. Geen `sub_agents` voor taakwerk. Geen ingebouwde memory-toolset: memory gaat via `memory.md`.

```yaml
agents:
  root:
    model: anthropic/claude-sonnet-4-5
    description: Code agent
    instruction: |
      Lees eerst /agent/soul.md en /agent/home/memory.md.
      Volg de kanban-skill voor het afronden van taken.
    skills: [kanban, memory]
    toolsets:
      - type: filesystem
      - type: shell
```

**Gedeelde skills** (`/data/shared/skills/<naam>/SKILL.md`, per skill ro gemount onder `~/.agents/skills`):

- `kanban`: taak afronden (resultaat invullen, naar `done/`), blokkeren (reden invullen, naar `blocked/`), werk voor een andere agent aanvragen.
- `memory`: wanneer en hoe `memory.md` bijwerken. Kort, feitelijk, geen taaklog.

Agents mogen nieuwe skills alleen in `/shared/skills-proposed/` zetten. Promoveren naar `skills/` doet Mees of de orchestrator.

`sub_agents` zijn toegestaan in de orchestrator-config voor incidentele vragen met direct antwoord, maar alleen voor rollen die lezen of opzoeken: ze draaien in het orchestrator-proces en hebben dus schrijftoegang tot heel `/data`.

## Soul, memory en git

- `soul.md`: persoonlijkheid, rol en regels van de agent. Read-only in de sub-agent-container; alleen Mees of de orchestrator past het aan.
- `memory.md`: door de agent zelf bijgewerkt via de memory-skill.
- Een agent bestaat in git uit: `Dockerfile`, `soul.md`, `memory.md`, `agent.yaml` en `skills/`. Samen met `base/Dockerfile` en `shared/skills/` is dat de volledige definitie van het systeem; kanban, werkbestanden en images vallen erbuiten.
- Eén git-repo in `/data/` met een whitelist-`.gitignore`:

```
*
!*/
!base/Dockerfile
!agents/*/Dockerfile
!agents/*/soul.md
!agents/*/agent.yaml
!agents/*/skills/**
!agents/*/home/memory.md
!shared/skills/**
docker/
agents/*/kanban/
agents/*/home/workspace/
shared/files/
```

De orchestrator commit na elke taak die in `done/` of `blocked/` belandt, met het taak-id in de message: `git commit -m "code: task-0142"`. Sub-agents hebben geen git-toegang nodig.

## Acceptatie en buiten scope

De POC is klaar als:

- [ ] De hoofdcontainer start met docker compose op Linux, macOS en Windows; `dockerd` draait erin en kan een container starten.
- [ ] Bij opstarten worden `agent-base`, `agent-code` en `agent-mail` gebouwd; `agent-code` bevat Claude Code, `git` en Chromium.
- [ ] Een gecommitte wijziging in `agents/code/Dockerfile` leidt tot een nieuw `agent-code`-image, gebruikt bij de volgende taak.
- [ ] Een taakbestand in `code/kanban/todo/` start de `code`-container binnen 60 s.
- [ ] De agent claimt de taak, voert hem uit en zet hem met resultaat in `done/`; de container stopt daarna.
- [ ] Twee taken tegelijk in `todo/` worden na elkaar afgewerkt, geen van beide dubbel.
- [ ] Een sub-agent kan niet schrijven in de map van een andere agent, in zijn eigen `soul.md`, `agent.yaml`, `skills/` of `backlog/`, en ziet zijn eigen `Dockerfile` niet.
- [ ] Een sub-agent kan via de kanban-skill een taak in `orchestrator/kanban/backlog/` zetten.
- [ ] Een wijziging in `memory.md` staat na afronding als commit met taak-id in git.

**Buiten scope:** meerdere instances per agent-type, git worktrees per instance, Telegram, STT (speech-to-text), OpenAI-compatible API, een kanban-UI, automatisch promoveren van skills, Home Assistant-integratie.
