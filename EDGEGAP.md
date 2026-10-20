# Edgegap Arena Shooter: dedicated servers and matchmaking on Edgegap

A fork of [Super Star Fighter](https://github.com/DumpsterFireLabs/SuperStarFighter) (Godot 4.7.2, MIT) set up as an Edgegap sample. Players click **FIND MATCH**, the Edgegap matchmaker groups them and starts a dedicated server near them, the clients join it over `wss://`, and the server stops its own deployment when the match is over.

The game's server already runs the whole simulation, so nothing about the netcode changes. The Edgegap pieces live in two folders, with three one-line hooks in upstream files so upstream syncs stay easy.

| File | What it does |
|---|---|
| `src/shared/edgegap/edgegap_server.gd` | Server lifecycle on Edgegap: lobby password, auto start, NPC fill, self-stop |
| `src/client/edgegap/edgegap_find_match.gd` | The FIND MATCH tab: matchmaker tickets, then join through Direct Connect |
| `src/client/edgegap/edgegap_settings.gd` | Matchmaker URL, Auth Token, profile and port name |
| `edgegap/Dockerfile` | Server image from the Linux x86_64 dedicated-server package |
| `edgegap/matchmaker-config.json` | Matchmaker config: one `casual` profile, 2 to 4 players, solo after 30 s |
| `src/bootstrap.gd`, `src/server/server_main.gd`, `src/client/ui/connection_controller.gd` | One line each to call the above |

Outside an Edgegap deployment (no `ARBITRIUM_REQUEST_ID`) the server behaves exactly like upstream.

## How a match runs

1. The client posts a ticket: `POST {matchmaker}/tickets {"profile": "casual", "attributes": {}}`, then polls `GET /tickets/{id}` every 2 s until `HOST_ASSIGNED`.
2. The matchmaker deploys `godot-arena-shooter` near the players. The server reads the matched player count from `MM_TICKET_IDS`.
3. The client joins `wss://<fqdn>:<external port>` through the existing Direct Connect code. The lobby password is the deployment's request ID, which is the first label of the fqdn. Only matched players are given that address.
4. The server starts the match when every matched player is in, or 30 s after the first one joined. NPCs fill the empty seats up to 4 ships, so a solo player still gets a game.
5. After the final results, the server waits 20 s and calls `ARBITRIUM_DELETE_URL` to stop its deployment. It also stops if nobody joins within 120 s, or if everyone leaves for 30 s. One match per deployment: a rematch request still ends it, and players queue again.

Server env vars (optional, on the app version): `EDGEGAP_NPC_FILL` (default 4, 0 turns NPCs off), `EDGEGAP_START_GRACE` (30), `EDGEGAP_JOIN_TIMEOUT` (120), `EDGEGAP_ROUNDS_TO_WIN` (3). Server log lines start with `EDGEGAP`.

## Build and deploy

```bash
python tools/build.py bootstrap
python tools/build.py build server-linux-x64 --skip-gate
docker build --platform linux/amd64 -f edgegap/Dockerfile -t registry.edgegap.com/<project>/arena-shooter:<tag> builds/beta-19/server-linux-x86_64
docker push registry.edgegap.com/<project>/arena-shooter:<tag>
```

App version: port `7000`, name `gameport`, protocol **WS** with **TLS Upgrade** on, 0.5 vCPU / 1 GB, plus the Container Registry username and token so Edgegap can pull the image.

Matchmaker: dashboard → Matchmaker → Create → upload `edgegap/matchmaker-config.json` (set `application.name`/`version` to yours) → Create and Start. Copy the API URL and Auth Token into `src/client/edgegap/edgegap_settings.gd`, or set `EDGEGAP_MATCHMAKER_URL` and `EDGEGAP_MATCHMAKER_TOKEN` when launching the client. The Auth Token is the matchmaker's client token; it is meant to ship in game clients and gives no access to the Edgegap account. Never put the Edgegap API token in the client.

Client: `python tools/build.py build windows --skip-gate`. `EDGEGAP_FIND_MATCH=1` makes a client press FIND MATCH at launch, for tests.

## Tested

2026-10-20, Godot 4.7.2, Edgegap matchmaker 3.3.2:
- Local Docker image with simulated Edgegap env and two bot clients: auto start with 2 NPCs, stop after final results.
- Direct deployment (Newark): two bot clients over `wss://`, 3-round match, the deployment stopped itself after 5.4 min.
- Matchmaker: two Windows clients pressed FIND MATCH, were assigned the same server, joined, and the match started with 2 NPCs.
- Deployments nobody joined stopped themselves after the 120 s join timeout.

## Changes from upstream

- Renamed to Edgegap Arena Shooter, and the music and studio logo removed: the upstream [asset license](assets/LICENSE.md) reserves them, and the game's name, for unmodified builds. Sound effects are synthesized in code and still play.
- The update checker points at this fork's releases.
