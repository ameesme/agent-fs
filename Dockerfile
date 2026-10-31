FROM docker:28-dind

RUN apk add --no-cache git curl jq tzdata
ENV DOCKER_TLS_CERTDIR=""

COPY runtime/boot.sh /usr/local/bin/
COPY runtime/watch-fs.sh /usr/local/bin/watch-fs
COPY runtime/start-agent.sh /usr/local/bin/start-agent
COPY runtime/cron-tasks.sh /usr/local/bin/cron-tasks
COPY runtime/pi/chat-main.sh /usr/local/bin/chat-main
COPY bridges /bridges
COPY bridges/cli.sh /usr/local/bin/chat
COPY docker/agent.Dockerfile /agent-base/Dockerfile
COPY runtime/process-tasks.sh runtime/create-task.sh /agent-base/
COPY runtime/pi /agent-base/pi
COPY runtime/create-task.sh /usr/local/bin/create-task
COPY docker/data.gitignore /etc/agent-fs.gitignore
RUN chmod +x /usr/local/bin/boot.sh /usr/local/bin/watch-fs /usr/local/bin/start-agent /usr/local/bin/cron-tasks /usr/local/bin/create-task /usr/local/bin/chat-main /usr/local/bin/chat

ENTRYPOINT ["boot.sh"]
