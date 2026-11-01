FROM docker:28-dind AS source
RUN apk add --no-cache git
# Pin the core independently of the Home Assistant packaging version.
ARG AGENT_FS_REF=4e3151954e055289353ba05aa4e2629dcab633ff
RUN git init /source \
    && git -C /source fetch --depth 1 https://github.com/ameesme/agent-fs.git "$AGENT_FS_REF" \
    && git -C /source checkout FETCH_HEAD \
    && rm -rf /source/.git

FROM docker:28-dind
RUN apk add --no-cache git curl jq tzdata
ENV DOCKER_TLS_CERTDIR=""
COPY --from=source /source/runtime /opt/agent-fs/runtime
COPY --from=source /source/channels /channels
COPY --from=source /source/docker /opt/agent-fs/docker
COPY --from=source /source/data /etc/agent-fs-defaults
RUN mkdir -p /agent-base /etc \
    && cp /opt/agent-fs/docker/agent.Dockerfile /agent-base/Dockerfile \
    && cp /opt/agent-fs/runtime/process-tasks.sh /opt/agent-fs/runtime/create-task.sh /agent-base/ \
    && cp -R /opt/agent-fs/runtime/pi /agent-base/pi \
    && cp /opt/agent-fs/docker/data.gitignore /etc/agent-fs.gitignore \
    && for name in boot.sh watch-fs start-agent cron-tasks create-task; do \
         source=$name; [ "$name" = boot.sh ] || source=$name.sh; \
         ln -s "/opt/agent-fs/runtime/$source" "/usr/local/bin/$name"; \
       done \
    && ln -s /opt/agent-fs/runtime/pi/chat-main.sh /usr/local/bin/chat-main \
    && ln -s /channels/cli.sh /usr/local/bin/chat \
    && chmod +x /usr/local/bin/boot.sh /usr/local/bin/watch-fs \
         /usr/local/bin/start-agent /usr/local/bin/cron-tasks \
         /usr/local/bin/create-task /usr/local/bin/chat-main /usr/local/bin/chat
COPY run.sh /usr/local/bin/home-assistant-run
ENTRYPOINT ["sh", "/usr/local/bin/home-assistant-run"]
