FROM agent-base

RUN apt-get update && apt-get install -y --no-install-recommends \
      nodejs npm chromium \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

ENV CHROME_BIN=/usr/bin/chromium
USER 1001
