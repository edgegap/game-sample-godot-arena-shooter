extends RefCounted
class_name EdgegapWizardApi

## Mirrors Unity EdgegapWizardApi / EdgegapApiBase:
## https://github.com/edgegap/edgegap-unity-plugin/blob/main/Editor/Api/EdgegapWizardApi.cs
## https://github.com/edgegap/edgegap-unity-plugin/blob/main/Editor/Api/EdgegapApiBase.cs

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")

signal init_completed(ok: bool, response_code: int, body: String)
signal credentials_completed(ok: bool, response_code: int, credentials: Dictionary, body: String)

enum Phase { IDLE, INIT, CREDENTIALS }

var _http: HTTPRequest
## Exact Authorization header value from the input (includes "token …").
var _authorization := ""
var _phase: Phase = Phase.IDLE

func bind_http(http: HTTPRequest) -> void:
	if _http and _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.disconnect(_on_request_completed)
	_http = http
	if not _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.connect(_on_request_completed)

func verify_and_fetch_credentials(token: String) -> Error:
	# Paste as-is from Edgegap dashboard (already includes the "token " scheme).
	_authorization = token
	if _authorization.is_empty():
		init_completed.emit(false, 0, "API token is empty.")
		return ERR_INVALID_PARAMETER

	_phase = Phase.INIT
	EdgegapLogger.info("Wizard: POST v1/wizard/init-quick-start")
	# Match Unity body exactly (source must be "unity" for this endpoint).
	return _request(
		HTTPClient.METHOD_POST,
		"%s/v1/wizard/init-quick-start" % EdgegapConstants.API_BASE,
		"{\"source\":\"unity\"}",
		true
	)

func fetch_registry_credentials() -> Error:
	_phase = Phase.CREDENTIALS
	EdgegapLogger.info("Wizard: GET v1/wizard/registry-credentials")
	return _request(
		HTTPClient.METHOD_GET,
		"%s/v1/wizard/registry-credentials" % EdgegapConstants.API_BASE,
		"",
		false
	)

func _auth_headers(include_json_content_type: bool) -> PackedStringArray:
	var headers := PackedStringArray([
		# Exact paste from the Edgegap dashboard input (includes "token …").
		"Authorization: %s" % _authorization,
		"Accept: application/json",
	])
	if include_json_content_type:
		headers.append("Content-Type: application/json")
	return headers

func _request(method: int, url: String, body: String, json_body: bool) -> Error:
	if _http == null:
		EdgegapLogger.error("Wizard API: HTTPRequest not bound.")
		return ERR_UNCONFIGURED
	var err := _http.request(url, _auth_headers(json_body), method, body)
	if err != OK:
		EdgegapLogger.error("Wizard API request failed to start: %s" % error_string(err))
		_phase = Phase.IDLE
	return err

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var phase := _phase
	_phase = Phase.IDLE

	if result != HTTPRequest.RESULT_SUCCESS:
		EdgegapLogger.error("Wizard HTTP transport error: result=%d" % result)
		if phase == Phase.INIT:
			init_completed.emit(false, response_code, text)
		elif phase == Phase.CREDENTIALS:
			credentials_completed.emit(false, response_code, {}, text)
		return

	if phase == Phase.INIT:
		# Unity treats 204 as verified token.
		var ok := response_code == 204
		if ok:
			EdgegapLogger.info("Wizard init-quick-start succeeded (204).")
		else:
			EdgegapLogger.error("Wizard init-quick-start failed: HTTP %d %s" % [response_code, text])
		init_completed.emit(ok, response_code, text)
		return

	if phase == Phase.CREDENTIALS:
		var ok := response_code >= 200 and response_code < 300
		var credentials := {}
		if ok:
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var registry_token := str(parsed.get("token", ""))
				if registry_token.is_empty():
					registry_token = str(parsed.get("password", ""))
				credentials = {
					"registry_url": str(parsed.get("registry_url", "")),
					"project": str(parsed.get("project", "")),
					"username": str(parsed.get("username", "")),
					"token": registry_token,
				}
				EdgegapLogger.info(
					"Registry credentials loaded (project=%s, registry=%s, user=%s, token_len=%d)." % [
						credentials.project,
						credentials.registry_url,
						credentials.username,
						str(credentials.token).length(),
					]
				)
				if str(credentials.token).is_empty() or str(credentials.username).is_empty():
					ok = false
					EdgegapLogger.error(
						"Registry credentials incomplete (need username + token). Raw: %s" % text
					)
			else:
				ok = false
				EdgegapLogger.error("Registry credentials response was not a JSON object.")
		else:
			EdgegapLogger.error("Wizard registry-credentials failed: HTTP %d %s" % [response_code, text])
		credentials_completed.emit(ok, response_code, credentials, text)
