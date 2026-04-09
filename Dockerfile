FROM alpine:3.19

# su-exec: lightweight setuid/setgid helper (used by linuxserver.io)
RUN apk add --no-cache su-exec

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/output"]

ENTRYPOINT ["/entrypoint.sh"]
