extends RefCounted
class_name EdgegapDeploymentsApi

## Mirrors Unity EdgegapDeploymentsApi + EdgegapIpApi for the deploy section:
## POST v2/deployments, GET v1/status/{id}, GET v1/deployments, DELETE v1/stop/{id}, GET v1/ip

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")

signal ip_completed(ok: bool, public_ip: String, response_code: int, body: String)
signal create_completed(ok: bool, request_id: String, response_code: int, body: String)
signal status_completed(ok: bool, status: Dictionary, response_code: int, body: String)
signal list_completed(ok: bool, deployments: Array, response_code: int, body: String)
signal stop_completed(ok: bool, response_code: int, body: String)

enum Phase { IDLE, IP, CREATE, STATUS, LIST, STOP }

var _http: HTTPRequest
var _authorization := ""
var _phase: Phase = Phase.IDLE

func bind_http(http: HTTPRequest) -> void:
	if _http and _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.disconnect(_on_request_completed)
	_http = http
	if not _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.connect(_on_request_completed)

func set_authorization(token: String) -> void:
	_authorization = token

func get_public_ip() -> Error:
	EdgegapLogger.info("Deploy API: GET v1/ip")
	return _start(Phase.IP, HTTPClient.METHOD_GET, "%s/v1/ip" % EdgegapConstants.API_BASE, "")

func create_deployment(app_name: String, version_name: String, external_ip: String) -> Error:
	EdgegapLogger.info("Deploy API: POST v2/deployments (%s / %s)" % [app_name, version_name])
	var body := JSON.stringify({
		"application": app_name,
		"version": version_name,
		"users": [{
			"user_type": "ip_address",
			"user_data": {"ip_address": external_ip},
		}],
		"tags": [EdgegapConstants.DEFAULT_DEPLOYMENT_TAG],
	})
	return _start(Phase.CREATE, HTTPClient.METHOD_POST, "%s/v2/deployments" % EdgegapConstants.API_BASE, body)

func get_deployment_status(request_id: String) -> Error:
	return _start(
		Phase.STATUS,
		HTTPClient.METHOD_GET,
		"%s/v1/status/%s" % [EdgegapConstants.API_BASE, request_id.uri_encode()],
		""
	)

func list_deployments() -> Error:
	EdgegapLogger.info("Deploy API: GET v1/deployments")
	return _start(Phase.LIST, HTTPClient.METHOD_GET, "%s/v1/deployments" % EdgegapConstants.API_BASE, "")

func stop_deployment(request_id: String) -> Error:
	EdgegapLogger.info("Deploy API: DELETE v1/stop/%s" % request_id)
	return _start(
		Phase.STOP,
		HTTPClient.METHOD_DELETE,
		"%s/v1/stop/%s" % [EdgegapConstants.API_BASE, request_id.uri_encode()],
		""
	)

func _start(phase: Phase, method: int, url: String, body: String) -> Error:
	if _http == null:
		EdgegapLogger.error("Deploy API: HTTPRequest not bound.")
		return ERR_UNCONFIGURED
	if _authorization.is_empty():
		EdgegapLogger.error("Deploy API: authorization token is empty.")
		return ERR_INVALID_PARAMETER
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	_phase = phase
	var err := _http.request(url, _auth_headers(not body.is_empty()), method, body)
	if err != OK:
		EdgegapLogger.error("Deploy API request failed to start: %s" % error_string(err))
		_phase = Phase.IDLE
	return err

func _auth_headers(include_json: bool) -> PackedStringArray:
	var headers := PackedStringArray([
		"Authorization: %s" % _authorization,
		"Accept: application/json",
	])
	if include_json:
		headers.append("Content-Type: application/json")
	return headers

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var phase := _phase
	_phase = Phase.IDLE

	if result != HTTPRequest.RESULT_SUCCESS:
		EdgegapLogger.error("Deploy API HTTP transport error: result=%d" % result)
		_emit_failure(phase, response_code, text)
		return

	match phase:
		Phase.IP:
			var ok := response_code >= 200 and response_code < 300
			var ip := ""
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					ip = str(parsed.get("public_ip", "")).strip_edges()
				ok = not ip.is_empty()
			if ok:
				EdgegapLogger.info("Public IP: %s" % ip)
			else:
				EdgegapLogger.error("IP lookup failed: HTTP %d %s" % [response_code, text])
			ip_completed.emit(ok, ip, response_code, text)
		Phase.CREATE:
			# Unity window treats 202 as success for create.
			var ok := response_code == 202 or response_code == 200
			var request_id := ""
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					request_id = str(parsed.get("request_id", "")).strip_edges()
				ok = not request_id.is_empty()
			if ok:
				EdgegapLogger.info("Deployment requested: %s" % request_id)
			else:
				EdgegapLogger.error("Create deployment failed: HTTP %d %s" % [response_code, text])
			create_completed.emit(ok, request_id, response_code, text)
		Phase.STATUS:
			var ok := response_code >= 200 and response_code < 300
			var status: Dictionary = {}
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					status = parsed as Dictionary
				else:
					ok = false
			status_completed.emit(ok, status, response_code, text)
		Phase.LIST:
			var ok := response_code >= 200 and response_code < 300
			var deployments: Array = []
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					var data: Variant = (parsed as Dictionary).get("data", [])
					if typeof(data) == TYPE_ARRAY:
						deployments = data as Array
				else:
					ok = false
			if not ok:
				EdgegapLogger.error("List deployments failed: HTTP %d %s" % [response_code, text])
			list_completed.emit(ok, deployments, response_code, text)
		Phase.STOP:
			# 200 = stopping/stopped ack; 410 = already gone (Unity awaits 410).
			var ok := response_code == 200 or response_code == 410
			if not ok:
				EdgegapLogger.error("Stop deployment failed: HTTP %d %s" % [response_code, text])
			stop_completed.emit(ok, response_code, text)
		_:
			pass

func _emit_failure(phase: Phase, response_code: int, text: String) -> void:
	match phase:
		Phase.IP:
			ip_completed.emit(false, "", response_code, text)
		Phase.CREATE:
			create_completed.emit(false, "", response_code, text)
		Phase.STATUS:
			status_completed.emit(false, {}, response_code, text)
		Phase.LIST:
			list_completed.emit(false, [], response_code, text)
		Phase.STOP:
			stop_completed.emit(false, response_code, text)
		_:
			pass
