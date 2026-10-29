FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
# Project-relative path without extension, e.g. build/edgegap-linux-server
ARG SERVER_BUILD_PATH=build/edgegap-linux-server

COPY ${SERVER_BUILD_PATH}.x86_64 /root/build/server.x86_64
COPY ${SERVER_BUILD_PATH}.pck /root/build/server.pck

WORKDIR /root/build

RUN chmod +x /root/build/server.x86_64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    update-ca-certificates

ENV GODOT_COMMANDLINE_ARGS=""

# tini runs as PID 1 and forwards SIGTERM to Godot, so stopping a deployment
# ends the server right away instead of waiting out the kill timeout.
ENTRYPOINT ["/usr/bin/tini", "--"]
# Do not print the environment: Edgegap injects secrets such as
# ARBITRIUM_DELETE_TOKEN, and anything printed ends up in the deployment logs.
CMD ["/bin/bash", "-c", "exec ./server.x86_64 -- ${GODOT_COMMANDLINE_ARGS}"]
