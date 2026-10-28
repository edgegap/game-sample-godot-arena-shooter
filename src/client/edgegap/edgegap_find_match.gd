class_name EdgegapFindMatch
extends VBoxContainer

## FIND MATCH tab: queues on the Edgegap matchmaker, waits for a server, then
## joins it through the DIRECT CONNECT flow.
##   POST {url}/tickets {profile, attributes}  →  GET {url}/tickets/{id} every 2 s
##   SEARCHING → MATCH_FOUND → HOST_ASSIGNED {fqdn, ports{gameport{external}}}
##   DELETE {url}/tickets/{id} on cancel.
## Header: Authorization: <matchmaker auth token>, raw.
## The lobby password of an Edgegap match is its request ID, the first label of
## the fqdn (see EdgegapServer).

enum State { IDLE, CREATING, SEARCHING, MATCH_FOUND, JOINING }

var controller: Node
var status_label: Label
var find_button: Button
var state := State.IDLE
var ticket_id := ""
var _http: HTTPRequest
var _poll_timer: Timer
var _searching_since := 0.0
var _busy := false
static var _auto_search_done := false


## Adds the tab first in the connection tabs and selects it.
static func install(connection_controller: Node, tabs: TabContainer) -> EdgegapFindMatch:
	var tab := EdgegapFindMatch.new()
	tab.name = "FIND MATCH"
	tab.controller = connection_controller
	tabs.add_child(tab)
	tabs.move_child(tab, 0)
	tabs.current_tab = 0
	return tab


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var hint := Label.new()
	hint.text = "Get matched with other players on an Edgegap dedicated server near you."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = &"HintLabel"
	add_child(hint)
	status_label = Label.new()
	status_label.name = "EdgegapMatchStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	var center := CenterContainer.new()
	add_child(center)
	find_button = Button.new()
	find_button.name = "FindMatchButton"
	find_button.theme_type_variation = &"PrimaryButton"
	find_button.custom_minimum_size = Vector2(280.0, 48.0)
	find_button.pressed.connect(_on_find_pressed)
	center.add_child(find_button)
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = EdgegapGameSettings.POLL_SECONDS
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	_set_state(State.IDLE, "Ready." if EdgegapGameSettings.is_configured() else "Set the matchmaker URL and Auth Token in src/client/edgegap/edgegap_settings.gd.")
	find_button.disabled = not EdgegapGameSettings.is_configured()
	# EDGEGAP_FIND_MATCH=1 starts searching once at launch, for automated tests.
	if not OS.get_environment("EDGEGAP_FIND_MATCH").is_empty() and not _auto_search_done:
		_auto_search_done = true
		_on_find_pressed.call_deferred()


func _on_find_pressed() -> void:
	if state == State.IDLE:
		_create_ticket()
	elif state in [State.CREATING, State.SEARCHING]:
		_cancel_ticket()


func _create_ticket() -> void:
	_ensure_display_name()
	_searching_since = Time.get_ticks_msec() / 1000.0
	_set_state(State.CREATING, "Joining the queue…")
	var body := JSON.stringify({"profile": EdgegapGameSettings.PROFILE, "attributes": {}})
	_send(HTTPClient.METHOD_POST, "/tickets", body, _on_ticket_created)


func _on_ticket_created(code: int, data: Variant) -> void:
	if state != State.CREATING:
		# Cancelled while the request was in flight: drop the new ticket.
		if code in [200, 201] and data is Dictionary and data.has("id"):
			_send(HTTPClient.METHOD_DELETE, "/tickets/%s" % data.id, "", Callable())
		return
	if code not in [200, 201] or not (data is Dictionary) or not data.has("id"):
		_fail(_error_text(code, "create the ticket"))
		return
	ticket_id = String(data.id)
	print("EDGEGAP_MM ticket=%s" % ticket_id)
	_set_state(State.SEARCHING, "Searching for players…")
	_poll_timer.start()


func _poll() -> void:
	if ticket_id.is_empty() or _busy or state not in [State.SEARCHING, State.MATCH_FOUND]:
		return
	if Time.get_ticks_msec() / 1000.0 - _searching_since > EdgegapGameSettings.SEARCH_TIMEOUT_SECONDS:
		_cancel_ticket()
		_fail("No match found in time. Try again.")
		return
	_send(HTTPClient.METHOD_GET, "/tickets/%s" % ticket_id, "", _on_ticket_status)


func _on_ticket_status(code: int, data: Variant) -> void:
	if state not in [State.SEARCHING, State.MATCH_FOUND]:
		return
	if code == 404:
		_fail("The ticket expired. Try again.")
		return
	if code != 200 or not (data is Dictionary):
		return # Transient: keep polling.
	match String(data.get("status", "")):
		"SEARCHING":
			_set_state(State.SEARCHING, "Searching for players…")
		"MATCH_FOUND", "TEAM_FOUND":
			_set_state(State.MATCH_FOUND, "Match found. Starting a server near you…")
		"HOST_ASSIGNED":
			_join_assignment(data.get("assignment", {}))
		"CANCELLED":
			_fail("The matchmaker cancelled the ticket. Try again.")


func _join_assignment(assignment: Variant) -> void:
	_poll_timer.stop()
	var fqdn := ""
	var port := 0
	if assignment is Dictionary:
		fqdn = String(assignment.get("fqdn", ""))
		var ports: Variant = assignment.get("ports", {})
		if ports is Dictionary and ports.has(EdgegapGameSettings.PORT_NAME):
			port = int((ports[EdgegapGameSettings.PORT_NAME] as Dictionary).get("external", 0))
	if fqdn.is_empty() or port <= 0:
		_fail("The server has no port named '%s'. Check the app version." % EdgegapGameSettings.PORT_NAME)
		return
	var scheme := "wss" if EdgegapGameSettings.USE_TLS else "ws"
	var url := "%s://%s:%d" % [scheme, fqdn, port]
	print("EDGEGAP_MM assigned=%s" % url)
	ticket_id = ""
	_set_state(State.JOINING, "Server ready. Joining %s…" % fqdn)
	controller.host_field.text = url
	controller.port_field.text = str(port)
	controller.direct_password_field.text = fqdn.get_slice(".", 0).to_lower()
	controller.remember_password_button.button_pressed = false
	controller._connect_online()
	if controller.bridge.role != NetworkBridge.Role.CLIENT:
		# Direct Connect refused to start; its status label says why.
		_set_state(State.IDLE, "Couldn't join the server: %s" % controller.connection_status.text)
		return
	# The lobby screen takes over from here; reset for the next search.
	_set_state(State.IDLE, "Ready.")


## Direct Connect refuses an empty or invalid display name, which a fresh
## install has. Fill one in before queueing so the join can't fail on it.
func _ensure_display_name() -> void:
	var field: LineEdit = controller.name_field
	if ServerLobby.sanitize_display_name(field.text).is_empty():
		field.text = "Pilot %03d" % (randi() % 1000)


func _cancel_ticket() -> void:
	_poll_timer.stop()
	if not ticket_id.is_empty():
		_send(HTTPClient.METHOD_DELETE, "/tickets/%s" % ticket_id, "", Callable())
	ticket_id = ""
	_set_state(State.IDLE, "Search cancelled.")


func _fail(message: String) -> void:
	_poll_timer.stop()
	ticket_id = ""
	_set_state(State.IDLE, message)


func _set_state(next: State, message: String) -> void:
	state = next
	status_label.text = message
	match next:
		State.IDLE:
			find_button.text = "FIND MATCH"
			find_button.disabled = not EdgegapGameSettings.is_configured()
		State.CREATING, State.SEARCHING:
			find_button.text = "CANCEL"
			find_button.disabled = false
		_:
			find_button.text = "PLEASE WAIT"
			find_button.disabled = true


## One request at a time; DELETEs use their own node so a cancel never waits.
func _send(method: int, path: String, body: String, on_done: Callable) -> void:
	var headers := PackedStringArray(["Authorization: %s" % EdgegapGameSettings.auth_token()])
	if not body.is_empty():
		headers.append("Content-Type: application/json")
	var http := _http
	if method == HTTPClient.METHOD_DELETE or _busy:
		http = HTTPRequest.new()
		http.timeout = 10.0
		add_child(http)
	var owned := http != _http
	if not owned:
		_busy = true
	http.request_completed.connect(func(result: int, code: int, _response_headers: PackedStringArray, response: PackedByteArray) -> void:
		if not owned:
			_busy = false
		else:
			http.queue_free()
		var data: Variant = JSON.parse_string(response.get_string_from_utf8()) if response.size() > 0 else null
		if result != HTTPRequest.RESULT_SUCCESS:
			code = 0
		if code >= 400 or code == 0:
			print("EDGEGAP_MM %s /%s -> %d %s" % [_method_name(method), path.get_slice("/", 1), code, response.get_string_from_utf8().left(200)])
		if on_done.is_valid():
			on_done.call(code, data)
	, CONNECT_ONE_SHOT)
	var error := http.request(EdgegapGameSettings.matchmaker_url() + path, headers, method, body)
	if error != OK:
		if not owned:
			_busy = false
		if on_done.is_valid():
			on_done.call(0, null)


static func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
	return str(method)


static func _error_text(code: int, action: String) -> String:
	match code:
		0:
			return "Couldn't reach the matchmaker. Is it running?"
		400:
			return "The matchmaker rejected the ticket (profile or attributes don't match its config)."
		401, 403:
			return "The matchmaker refused the Auth Token."
		429:
			return "The matchmaker is busy. Try again."
	return "Couldn't %s (HTTP %d)." % [action, code]
