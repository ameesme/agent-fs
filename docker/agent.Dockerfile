FROM debian:bookworm-slim

ARG DOCKER_AGENT_VERSION=1.154.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

RUN case "$(uname -m)" in \
      x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) echo "unsupported $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/docker-agent \
      "https://github.com/docker/docker-agent/releases/download/v${DOCKER_AGENT_VERSION}/docker-agent-linux-$arch" \
    && chmod +x /usr/local/bin/docker-agent

COPY agent-loop.sh /usr/local/bin/agent-loop
COPY newtask.sh /usr/local/bin/newtask
RUN chmod +x /usr/local/bin/agent-loop /usr/local/bin/newtask

ENV HOME=/agent/home \
    DOCKER_AGENT_NO_SETUP=1
WORKDIR /agent/home/workspace

ENTRYPOINT ["/usr/local/bin/agent-loop"]
