FROM agent-base

ARG CLAUDE_VERSION=2.1.316

RUN useradd --uid 1001 --user-group --home-dir /agent/home --no-create-home agent

# Uncomment to give the agent tmux, Chromium and Claude Code (adds ~1 GB to the image)
# RUN apt-get update && apt-get install -y --no-install-recommends tmux chromium \
#     && rm -rf /var/lib/apt/lists/*
# RUN npm install --global "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
#     && npm cache clean --force

USER 1001
