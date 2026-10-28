extends RefCounted
class_name EdgegapAppApi

## Applications + versions for upload/deploy dropdowns (Unity EdgegapAppApi).

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")

signal get_apps_completed(ok: bool, response_code: int, app_names: PackedStringArray, body: String)
signal get_versions_completed(ok: bool, response_code: int, versions: PackedStringArray, body: String)

enum Phase { IDLE, GET_APPS, GET_VERSIONS }

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

func get_apps() -> Error:
	var url := "%s/v1/apps?limit=25" % EdgegapConstants.API_BASE
	EdgegapLogger.info("App API: GET %s" % url)
	return _start(Phase.GET_APPS, url)

func get_app_versions(app_name: String) -> Error:
	var url := "%s/v1/app/%s/versions?limit=25" % [
		EdgegapConstants.API_BASE, app_name.uri_encode()
	]
	EdgegapLogger.info("App API: GET %s" % url)
	return _start(Phase.GET_VERSIONS, url)

func _start(phase: Phase, url: String) -> Error:
	if _http == null:
		EdgegapLogger.error("App API: HTTPRequest not bound.")
		return ERR_UNCONFIGURED
	if _authorization.is_empty():
		EdgegapLogger.error("App API: authorization token is empty.")
		return ERR_INVALID_PARAMETER
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	_phase = phase
	var err := _http.request(url, _auth_headers(), HTTPClient.METHOD_GET, "")
	if err != OK:
		EdgegapLogger.error("App API request failed to start: %s" % error_string(err))
		_phase = Phase.IDLE
	return err

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: %s" % _authorization,
		"Accept: application/json",
	])

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var phase := _phase
	_phase = Phase.IDLE

	if result != HTTPRequest.RESULT_SUCCESS:
		EdgegapLogger.error("App API HTTP transport error: result=%d" % result)
		if phase == Phase.GET_APPS:
			get_apps_completed.emit(false, response_code, PackedStringArray(), text)
		elif phase == Phase.GET_VERSIONS:
			get_versions_completed.emit(false, response_code, PackedStringArray(), text)
		return

	var ok := response_code >= 200 and response_code < 300
	match phase:
		Phase.GET_APPS:
			var names: PackedStringArray = []
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					var apps: Variant = parsed.get("applications", [])
					if typeof(apps) == TYPE_ARRAY:
						for app in apps:
							if typeof(app) == TYPE_DICTIONARY:
								var name := str(app.get("name", "")).strip_edges()
								if not name.is_empty():
									names.append(name)
				else:
					ok = false
			if ok:
				EdgegapLogger.info("Loaded %d Edgegap application(s)." % names.size())
			else:
				EdgegapLogger.error("Get apps failed: HTTP %d %s" % [response_code, text])
			get_apps_completed.emit(ok, response_code, names, text)
		Phase.GET_VERSIONS:
			var versions: PackedStringArray = []
			if ok:
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					var list: Variant = parsed.get("versions", [])
					if typeof(list) == TYPE_ARRAY:
						for version in list:
							if typeof(version) != TYPE_DICTIONARY:
								continue
							if not bool(version.get("is_active", true)):
								continue
							var name := str(version.get("name", "")).strip_edges()
							if not name.is_empty():
								versions.append(name)
				else:
					ok = false
			if ok:
				EdgegapLogger.info("Loaded %d active app version(s)." % versions.size())
			else:
				EdgegapLogger.error("Get app versions failed: HTTP %d %s" % [response_code, text])
			get_versions_completed.emit(ok, response_code, versions, text)
		_:
			pass
