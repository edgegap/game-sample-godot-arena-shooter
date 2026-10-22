# Edgegap game server image for the Linux x86_64 dedicated server package.
#   python tools/build.py build server-linux-x64
#   docker build --platform linux/amd64 -f edgegap/Dockerfile \
#     --build-arg PACKAGE=EdgegapArenaShooter-Beta19-Server-Linux-x64.tar.gz \
#     -t registry.edgegap.com/<project>/arena-shooter:<tag> builds/beta-19/server-linux-x86_64
# Gameplay is one WebSocket (TCP) port, 7000. On Edgegap the lobby password is
# the deployment's request ID (src/shared/edgegap/edgegap_server.gd).
FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 server

ARG PACKAGE=EdgegapArenaShooter-Beta19-Server-Linux-x64.tar.gz
WORKDIR /server
ADD ${PACKAGE} /server/
RUN mv /server/EdgegapArenaShooter-Server.x86_64 /server/server.x86_64 \
    && chmod +x /server/server.x86_64 \
    && chown -R server:server /server

USER server
EXPOSE 7000/tcp
ENTRYPOINT ["/server/server.x86_64", "--headless", "--", "--server", "--port=7000"]
