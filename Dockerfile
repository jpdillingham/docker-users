FROM ubuntu:noble

# gosu: lightweight setuid/setgid helper (Debian/Ubuntu equivalent of su-exec)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/output"]

ENTRYPOINT ["/entrypoint.sh"]
