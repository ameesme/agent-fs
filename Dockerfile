FROM docker:28-dind

RUN apk add --no-cache git curl jq
ENV DOCKER_TLS_CERTDIR=""

COPY runtime/entrypoint.sh /usr/local/bin/
COPY runtime/watch.sh /usr/local/bin/agent-watch
COPY runtime/container.sh /usr/local/bin/agent-container
COPY bridges /bridges
COPY bridges/cli.sh /usr/local/bin/chat
COPY docker/agent.Dockerfile /agent-base/Dockerfile
COPY runtime/agent-loop.sh runtime/newtask.sh /agent-base/
COPY runtime/newtask.sh /usr/local/bin/newtask
COPY docker/data.gitignore /data/.gitignore
COPY shared/skills /data/shared/skills
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/agent-watch /usr/local/bin/agent-container /usr/local/bin/newtask /usr/local/bin/chat

ENTRYPOINT ["entrypoint.sh"]
