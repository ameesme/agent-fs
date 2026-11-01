FROM node:22-bookworm-slim

ARG PI_VERSION=1.2.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git bash fd-find ripgrep \
      python3 python3-pip python3-venv python-is-python3 \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

RUN npm install --global --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
    && npm cache clean --force

COPY process-tasks.sh /usr/local/bin/process-tasks
COPY create-task.sh /usr/local/bin/create-task
COPY pi/agent-run.mjs /usr/local/bin/agent-run
COPY pi/agentFS.mjs /usr/local/lib/agent-fs/agentFS.mjs
RUN chmod +x /usr/local/bin/process-tasks /usr/local/bin/create-task /usr/local/bin/agent-run

ENV HOME=/agent/home \
    PI_OFFLINE=1 \
    PI_TELEMETRY=0
WORKDIR /agent/home/workspace

ENTRYPOINT ["/usr/local/bin/process-tasks"]
