FROM docker:28-dind

RUN apk add --no-cache git curl jq
ENV DOCKER_TLS_CERTDIR=""

COPY runtime/boot.sh /usr/local/bin/
COPY runtime/watch-fs.sh /usr/local/bin/watch-fs
COPY runtime/start-agent.sh /usr/local/bin/start-agent
COPY bridges /bridges
COPY bridges/cli.sh /usr/local/bin/chat
COPY docker/agent.Dockerfile /agent-base/Dockerfile
COPY runtime/process-tasks.sh runtime/create-task.sh /agent-base/
COPY runtime/create-task.sh /usr/local/bin/create-task
COPY docker/data.gitignore /data/.gitignore
RUN chmod +x /usr/local/bin/boot.sh /usr/local/bin/watch-fs /usr/local/bin/start-agent /usr/local/bin/create-task /usr/local/bin/chat

ENTRYPOINT ["boot.sh"]
