# Edgegap Arena Shooter: dedicated servers and matchmaking on Edgegap

A fork of [Super Star Fighter](https://github.com/DumpsterFireLabs/SuperStarFighter) (Godot 4.7.2, MIT) set up as an Edgegap sample. Players click **FIND MATCH**, the Edgegap matchmaker groups them and starts a dedicated server near them, the clients join it over `wss://`, and the server stops its own deployment when the match is over.

The game's server already runs the whole simulation, so nothing about the netcode changes. The Edgegap pieces live in two folders plus the Edgegap plugin, with three one-line hooks in upstream files so upstream syncs stay easy.

| File | What it does |
|---|---|
| `src/shared/edgegap/edgegap_server.gd` | Server lifecycle on Edgegap: lobby password, auto start, NPC fill, self-stop |
| `src/client/edgegap/edgegap_find_match.gd` | The FIND MATCH tab: matchmaker tickets, then join through Direct Connect |
| `src/client/edgegap/edgegap_settings.gd` | Matchmaker URL, Auth Token, profile and port name |
| `addons/edgegap/` | [Edgegap Servers Quickstart plugin](https://github.com/edgegap/buildtool-godot-plugin) 1.0.10: exports, containerizes, uploads and deploys the server from the editor |
| `Edgegap Linux Server` preset, `.dockerignore` | What the plugin builds: the dedicated server export to `build/edgegap-linux-server`, and only that in the image |
| `edgegap/matchmaker-config.json` | Matchmaker config: one `casual` profile, 2 to 4 players, solo after 20 s, tickets expire after 30 s |
| `src/bootstrap.gd`, `src/server/server_main.gd`, `src/client/ui/connection_controller.gd` | One line each to call the above |

Outside an Edgegap deployment (no `ARBITRIUM_REQUEST_ID`) the server behaves exactly like upstream.

## How a match runs

1. The client posts a ticket: `POST {matchmaker}/tickets {"profile": "casual", "attributes": {}}`, then polls `GET /tickets/{id}` every 2 s until `HOST_ASSIGNED`.
2. The matchmaker deploys `godot-arena-shooter` near the players. The server reads the matched player count from `MM_TICKET_IDS`.
3. The client joins `wss://<fqdn>:<external port>` through the existing Direct Connect code. The lobby password is the deployment's request ID, which is the first label of the fqdn. Only matched players are given that address.
4. The server starts the match when every matched player is in, or 30 s after the first one joined. NPCs fill the empty seats up to 4 ships, so a solo player still gets a game.
5. After the final results, the server waits 20 s and calls `ARBITRIUM_DELETE_URL` to stop its deployment. It also stops if nobody joins within 120 s, or if everyone leaves for 30 s. One match per deployment: a rematch request still ends it, and players queue again.

**Playing alone:** a player who queues alone is not left waiting. The `casual` profile first looks for 2 to 4 players; after 20 s its expansion lowers the minimum to 1, so the lone ticket is matched on its own before its 30 s `ticket_expiration_period`. The matchmaker deploys a server with one ticket in `MM_TICKET_IDS`, the server starts the match as soon as that player joins (every matched player is in, so the 30 s start grace doesn't apply), and NPCs fill the other 3 seats up to 4 ships.

Server env vars (optional, on the app version): `EDGEGAP_NPC_FILL` (default 4, 0 turns NPCs off), `EDGEGAP_START_GRACE` (30), `EDGEGAP_JOIN_TIMEOUT` (120), `EDGEGAP_ROUNDS_TO_WIN` (3). Server log lines start with `EDGEGAP`.

**Known limitation:** the server does not check that a connecting player holds a matchmaker ticket for this match, so anyone who learns the server address can join. The lobby password is the deployment's request ID, which is part of that address, and `MM_TICKET_IDS` is only used to count players. Deployments stop themselves when no one joins or everyone leaves, which limits cost. Before production, validate each player against the match's tickets (`MM_TICKET_IDS` / the matchmaker API) or an auth token.

## Playing more than 4 ships

This sample was tested on Edgegap with up to 4 ships. The game supports up to 32 pilots (`GameConstants.MAX_PLAYERS`); the Edgegap server sizes the lobby to the larger of the matched player count and `EDGEGAP_NPC_FILL`. To go bigger, raise `max_team_size` in `edgegap/matchmaker-config.json` for more players and `EDGEGAP_NPC_FILL` for more NPCs, and give the app version more vCPU than the shipped 0.5 vCPU / 1 GB. A 32-pilot match should run that way, but it was not tested on Edgegap.

## Build and deploy

Everything goes through the **Edgegap** dock (right panel, next to Inspector; it opens with the project since the plugin is enabled). You need Docker running and the Godot 4.7.2 Linux export templates.

1. **Connect Account**: paste your Edgegap API token (the dock's link opens the page that gives one). It stays in your editor settings, never in the project.
2. **Build Your Game Server**: **Validate export templates**, then **Export server**. It uses the `Edgegap Linux Server` preset, which already exists, so the plugin leaves it as is: a Linux x86_64 dedicated-server export with this game's shipping allowlist, written to `build/edgegap-linux-server.x86_64` + `.pck`.
3. **Containerize Your Server**: **Validate Docker**, set **Image tag** to a UTC timestamp such as `20261028-1530`, then **Containerize**. The plugin's default Dockerfile works as is: the dedicated-server export starts headless in server mode on port `7000`, so no command-line arguments are needed.
4. **Test Your Server Locally** (optional): set **Docker run parameters** to `-p 7000:7000`, then **Deploy locally**, and join `ws://127.0.0.1:7000` with Direct Connect.
5. **Upload to Edgegap**: application name `godot-arena-shooter`, **Upload**. The plugin pushes the image to your Edgegap registry and opens the dashboard's new-version page with the image filled in. There, set port `7000`, name `gameport`, protocol **WS** with **TLS Upgrade** on, 0.5 vCPU / 1 GB, and create the version.
6. **Deploy to cloud**: picks the app and version and starts a server near you, tagged `quickstart`; **Stop** ends it. A server nobody joins stops itself after 120 s anyway.

Rebuilding after a code change is **Rebuild from source** (export + containerize in one click), then Upload with a new tag.

The same steps from a terminal, for CI or a coding agent:

```bash
godot --headless --path . --export-debug "Edgegap Linux Server" build/edgegap-linux-server.x86_64
docker build --platform linux/amd64 -f addons/edgegap/defaults/Dockerfile --build-arg SERVER_BUILD_PATH=build/edgegap-linux-server -t registry.edgegap.com/<project>/edgegap-arena-shooter:<tag> .
docker push registry.edgegap.com/<project>/edgegap-arena-shooter:<tag>
```

New files in shared, server or client folders need `python tools/update-export-policy.py` first: every preset, the Edgegap one included, exports an explicit allowlist.

Matchmaker: dashboard → Matchmaker → Create → upload `edgegap/matchmaker-config.json` (set `application.name`/`version` to yours) → Create and Start. Copy the API URL and Auth Token into `src/client/edgegap/edgegap_settings.gd`, or set `EDGEGAP_MATCHMAKER_URL` and `EDGEGAP_MATCHMAKER_TOKEN` when launching the client. The Auth Token is the matchmaker's client token; it is meant to ship in game clients and gives no access to the Edgegap account. Never put the Edgegap API token in the client.

Client: `python tools/build.py build windows --skip-gate`. `EDGEGAP_FIND_MATCH=1` makes a client press FIND MATCH at launch, for tests.

## Tested

2026-10-28, Godot 4.7.2, Edgegap Servers Quickstart plugin 1.0.9:
- Server built the plugin's way: the `Edgegap Linux Server` preset exported (`--export-debug`, as the dock does) and containerized with the plugin's default Dockerfile, no arguments.
- Local container with simulated Edgegap env and two bot clients: auto start with 2 NPCs, `stopping reason="match over"`, the container exited 0.
- Direct deployment (Toronto) of that image: two bot clients over `wss://` played a 3-round match, and the deployment stopped itself about 3 minutes after it started.

2026-10-20, Godot 4.7.2, Edgegap matchmaker 3.3.2:
- Local Docker image with simulated Edgegap env and two bot clients: auto start with 2 NPCs, stop after final results.
- Direct deployment (Newark): two bot clients over `wss://`, 3-round match, the deployment stopped itself after 5.4 min.
- Matchmaker: two Windows clients pressed FIND MATCH, were assigned the same server, joined, and the match started with 2 NPCs.
- Deployments nobody joined stopped themselves after the 120 s join timeout.

## Changes from upstream

- Renamed to Edgegap Arena Shooter, and the music and studio logo removed: the upstream [asset license](assets/LICENSE.md) reserves them, and the game's name, for unmodified builds. Sound effects are synthesized in code and still play.
- Binaries, packages, the macOS bundle ID (`com.edgegap.arenashooter`) and the settings file (`edgegap_arena_shooter_settings.cfg`) use the new name.
- The update checker asks the GitHub API for this fork's latest release (this fork has published none yet, so it finds nothing), but release links still open the upstream releases page.
