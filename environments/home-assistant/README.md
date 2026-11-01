# agentFS for Home Assistant

[![Add agentFS to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fameesme%2Fagent-fs)

This optional app is isolated in `environments/home-assistant/`. Its image fetches the core
at the commit pinned by `AGENT_FS_REF` in this folder's Dockerfile, so Supervisor
can build from this folder without changing the core Dockerfile or runtime.
Home Assistant requires `repository.yaml` at the repository root to recognize
the repository; the app itself stays in this folder.

Requires Home Assistant OS with the app store (formerly add-ons).

1. Add `https://github.com/ameesme/agent-fs` under **Settings → Apps →
   App store → ⋮ → Repositories**, then install **agentFS**.
2. Turn off **Protection mode** on the app's Info tab. agentFS needs privileged
   Docker-in-Docker, as it does in Compose. It uses its own Docker daemon;
   it does not connect to Home Assistant's Docker socket.
   The app also requests explicit Linux capabilities for mounts, container
   networking, resource limits, device nodes and file capabilities;
   `full_access` alone does not grant these.
3. In the app's Configuration tab, add your provider credentials and Telegram
   settings, for example:

   ```yaml
   environment:
     - name: OPENAI_API_KEY
       value: your-api-key
   telegram_bot_token: "your-bot-token"
   telegram_chat_ids: "123456789"
   ```

4. Save and start the app, then message the bot. The first start builds the
   agent images and can take several minutes. Follow progress in the Logs tab.

The app supports amd64 and aarch64. It installs the included main, code and
poem agents on first start and keeps agents, memory, tasks and Docker images
in its persistent `/data` directory. Later starts leave agent definitions
unchanged. Configuration entries in `environment` generate
`/data/shared/.env` on every start; per-agent `.env` files still override them.
Use single-line, unquoted values, as with Docker env files.

Telegram is optional; leave both Telegram fields empty to run only scheduled
tasks. There is no browser chat or Home Assistant sidebar panel. The existing
Compose installation and CLI continue to work as before.
