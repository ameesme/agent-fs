FROM docker:28-dind

RUN apk add --no-cache python3 git

ENV DOCKER_TLS_CERTDIR=""

COPY entrypoint.sh watcher.py /usr/local/bin/
COPY seed /seed
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["entrypoint.sh"]
