class_name EdgegapServer
extends Node

## Runs a dedicated server as one Edgegap match: the lobby password, auto start
## once the matched players are in, NPC fill, and self-stop when the match ends.
## Does nothing outside an Edgegap deployment (no ARBITRIUM_REQUEST_ID).
##
## Env vars, all optional, set on the app version or deployment:
##   EDGEGAP_NPC_FILL=4        fill the match up to this many ships with NPCs (0: off)
##   EDGEGAP_START_GRACE=30    seconds after the first join before starting short-handed
##   EDGEGAP_JOIN_TIMEOUT=120  stop if nobody joins within this many seconds
##   EDGEGAP_ROUNDS_TO_WIN=3   rounds needed to win the match

const LOG_PREFIX := "EDGEGAP"
const DEFAULT_NPC_FILL := 4
const DEFAULT_START_GRACE_SECONDS := 30.0
const DIRECT_START_GRACE_SECONDS := 10.0
const DEFAULT_JOIN_TIMEOUT_SECONDS := 120.0
const EMPTY_GRACE_SECONDS := 30.0
const RESULTS_GRACE_SECONDS := 20.0
const SIGTERM_FALLBACK_SECONDS := 30.0

enum Phase { WAITING, PLAYING, STOPPING }

var bridge: NetworkBridge
var expected_players := 0
var npc_fill := DEFAULT_NPC_FILL
var start_grace := DEFAULT_START_GRACE_SECONDS
var join_timeout := DEFAULT_JOIN_TIMEOUT_SECONDS
var phase := Phase.WAITING
var _elapsed := 0.0
var _coordinator: AuthoritativeMatchCoordinator
var _first_join_at := -1.0
var _empty_since := -1.0
var _match_over_at := -1.0
var _next_start_attempt := 0.0


static func is_edgegap() -> bool:
	return not OS.get_environment("ARBITRIUM_REQUEST_ID").is_empty()


static func request_id() -> String:
	return OS.get_environment("ARBITRIUM_REQUEST_ID").to_lower()


## Call before CommandLineConfig.parse. The lobby password of an Edgegap match is
## its request ID: the matchmaker only hands the server address
## (<request_id>.pr.edgegap.net) to the players it matched, and clients read the
## password from that hostname.
static func prepare_environment() -> void:
	if not is_edgegap():
		return
	if OS.get_environment(CommandLineConfig.LOBBY_PASSWORD_ENVIRONMENT_VARIABLE).is_empty():
		OS.set_environment(CommandLineConfig.LOBBY_PASSWORD_ENVIRONMENT_VARIABLE, request_id())


## Call after CommandLineConfig.parse succeeded.
static func apply_command_line(configuration: Dictionary) -> void:
	if not is_edgegap() or configuration.get("mode", "") != "server":
		return
	var expected := matched_player_count()
	var fill := _env_int("EDGEGAP_NPC_FILL", DEFAULT_NPC_FILL, 0, GameConstants.MAX_PLAYERS)
	configuration.server_name = "Edgegap %s" % request_id()
	configuration.max_players = clampi(maxi(maxi(expected, fill), GameConstants.MIN_PLAYERS), GameConstants.MIN_PLAYERS, GameConstants.MAX_PLAYERS)
	configuration.rounds_to_win = _env_int("EDGEGAP_ROUNDS_TO_WIN", int(configuration.rounds_to_win), GameConstants.MIN_ROUNDS_TO_WIN, GameConstants.MAX_ROUNDS_TO_WIN)
	# This node starts the match itself, once the matched players are in.
	configuration.auto_start = false


## Players the matchmaker put in this match (one ticket each), or 0 for a
## deployment started without the matchmaker.
static func matched_player_count() -> int:
	var text := OS.get_environment("MM_TICKET_IDS")
	if text.is_empty():
		return 0
	var parsed: Variant = JSON.parse_string(text)
	return (parsed as Array).size() if parsed is Array else 0


## Adds the lifecycle node next to the running server. No-op outside Edgegap.
static func attach(parent: Node, server_bridge: NetworkBridge) -> void:
	if not is_edgegap():
		return
	var node := EdgegapServer.new()
	node.name = "EdgegapServer"
	node.bridge = server_bridge
	parent.add_child(node)


func _ready() -> void:
	expected_players = matched_player_count()
	npc_fill = _env_int("EDGEGAP_NPC_FILL", DEFAULT_NPC_FILL, 0, GameConstants.MAX_PLAYERS)
	var default_grace := DEFAULT_START_GRACE_SECONDS if expected_players > 0 else DIRECT_START_GRACE_SECONDS
	start_grace = float(_env_int("EDGEGAP_START_GRACE", int(default_grace), 0, 600))
	join_timeout = float(_env_int("EDGEGAP_JOIN_TIMEOUT", int(DEFAULT_JOIN_TIMEOUT_SECONDS), 10, 3600))
	_log("ready request_id=%s match_id=%s profile=%s expected_players=%d npc_fill=%d" % [
		request_id(), OS.get_environment("MM_MATCH_ID"), OS.get_environment("MM_MATCH_PROFILE"), expected_players, npc_fill,
	])


func _process(delta: float) -> void:
	_elapsed += delta
	if phase == Phase.STOPPING or bridge == null or bridge.lobby == null:
		return
	var humans := bridge.lobby.human_peer_ids().size()
	if humans > 0:
		_empty_since = -1.0
		if _first_join_at < 0.0:
			_first_join_at = _elapsed
	elif _empty_since < 0.0:
		_empty_since = _elapsed

	match phase:
		Phase.WAITING:
			if humans == 0:
				if _first_join_at < 0.0 and _elapsed > join_timeout:
					stop("no player joined within %d s" % int(join_timeout))
				elif _first_join_at >= 0.0 and _elapsed - _empty_since > EMPTY_GRACE_SECONDS:
					stop("all players left before the match started")
			elif humans >= expected_players and expected_players > 0:
				_start_match(humans)
			elif _elapsed - _first_join_at > start_grace:
				_start_match(humans)
		Phase.PLAYING:
			# One match per deployment: once it ends, stop even if the lobby
			# leader starts a rematch. Players queue again for the next one.
			if _match_over_at < 0.0 and _match_finished():
				_match_over_at = _elapsed
				_log("match_over humans=%d" % humans)
			if _match_over_at >= 0.0:
				if _elapsed - _match_over_at > RESULTS_GRACE_SECONDS:
					stop("match over")
			elif humans == 0 and _elapsed - _empty_since > EMPTY_GRACE_SECONDS:
				stop("all players left")


## Final results are on screen (the game waits there for a rematch), a rematch
## replaced the match, or it already went back to the lobby. Checked every
## frame: a rematch can follow the results within a frame or two.
func _match_finished() -> bool:
	var coordinator := bridge.match_coordinator
	if _coordinator == null:
		_coordinator = coordinator
	return coordinator == null or coordinator != _coordinator or coordinator.machine.state == MatchStateMachine.State.MATCH_RESULT


func _start_match(humans: int) -> void:
	if _elapsed < _next_start_attempt:
		return
	_next_start_attempt = _elapsed + 2.0
	var lobby := bridge.lobby
	if lobby.match_active:
		phase = Phase.PLAYING
		return
	# NPCs fill the empty seats when the match starts, up to max_players.
	lobby.npcs_enabled = npc_fill > humans
	for peer_id in lobby.human_peer_ids():
		lobby.request_ready(peer_id, true)
	var result := lobby.request_start(lobby.leader_id)
	if not bool(result.get("ok", false)):
		_log("start_refused humans=%d error=%s" % [humans, result.get("error", "")])
		return
	bridge._activate_added_npcs(result)
	bridge._broadcast_lobby_state()
	bridge._start_match_coordinator(lobby.leader_id)
	phase = Phase.PLAYING
	_log("match_started humans=%d expected=%d npcs=%d" % [humans, expected_players, (result.get("added_npcs", []) as Array).size()])


## Stops this deployment through the self-stop URL Edgegap injects. Edgegap then
## sends SIGTERM, which ends the process; quit anyway if that never comes.
func stop(reason: String) -> void:
	if phase == Phase.STOPPING:
		return
	phase = Phase.STOPPING
	_log("stopping reason=\"%s\"" % reason)
	var url := OS.get_environment("ARBITRIUM_DELETE_URL")
	var token := OS.get_environment("ARBITRIUM_DELETE_TOKEN")
	get_tree().create_timer(SIGTERM_FALLBACK_SECONDS).timeout.connect(_quit)
	if url.is_empty() or token.is_empty():
		_quit()
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_log("self_stop result=%d http=%d" % [result, code])
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			_quit()
	)
	var error := http.request(url, ["Authorization: %s" % token], HTTPClient.METHOD_DELETE)
	if error != OK:
		_log("self_stop request_error=%d" % error)
		_quit()


func _quit() -> void:
	if bridge != null:
		bridge.flush_metrics()
		bridge.stop()
	_log("exit")
	get_tree().quit(0)


func _log(message: String) -> void:
	print("%s %s" % [LOG_PREFIX, message])


static func _env_int(key: String, fallback: int, minimum: int, maximum: int) -> int:
	var text := OS.get_environment(key).strip_edges()
	if text.is_valid_int():
		return clampi(int(text), minimum, maximum)
	return fallback
