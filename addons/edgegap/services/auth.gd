extends RefCounted
class_name EdgegapAuth

## Token verification aligned with Unity EdgegapWindowV2.verifyApiTokenGetRegistryCreds:
## 1) POST /v1/wizard/init-quick-start (204)
## 2) GET /v1/wizard/registry-credentials (200)

const WizardApiScript = preload("wizard_api.gd")
const EdgegapSettings = preload("settings.gd")
const EdgegapLogger = preload("logger.gd")

signal verified(ok: bool, message: String)

var _wizard
var _pending_token := ""
var _bound := false

func _init() -> void:
	_wizard = WizardApiScript.new()

func bind_http(http: HTTPRequest) -> void:
	_ensure_wizard()
	_wizard.bind_http(http)
	if not _bound:
		_wizard.init_completed.connect(_on_init_completed)
		_wizard.credentials_completed.connect(_on_credentials_completed)
		_bound = true

func validate_token(token: String) -> void:
	_ensure_wizard()
	_pending_token = token
	var err: Error = _wizard.verify_and_fetch_credentials(_pending_token)
	if err != OK:
		verified.emit(false, "Failed to start token verification.")

func _ensure_wizard() -> void:
	if _wizard == null:
		_wizard = WizardApiScript.new()

func _on_init_completed(ok: bool, response_code: int, body: String) -> void:
	if not ok:
		verified.emit(false, "Invalid token (HTTP %d)." % response_code)
		EdgegapLogger.error("Token verification failed: HTTP %d %s" % [response_code, body])
		return

	# Match Unity: verified on 204, then fetch registry credentials.
	var err: Error = _wizard.fetch_registry_credentials()
	if err != OK:
		# Token is valid enough to unlock; credentials fetch failed to start.
		EdgegapSettings.set_token(_pending_token)
		EdgegapSettings.clear_registry_credentials()
		verified.emit(true, "Token verified, but registry credentials request failed to start.")
		EdgegapLogger.error("Failed to start registry credentials request.")

func _on_credentials_completed(ok: bool, response_code: int, credentials: Dictionary, body: String) -> void:
	# Unity unlocks UI after 204 even if credentials fail.
	if ok:
		EdgegapSettings.set_token(_pending_token)
		EdgegapSettings.set_registry_credentials(credentials)
		verified.emit(true, "Token verified. Registry credentials loaded.")
		EdgegapLogger.info("Edgegap API token verified successfully.")
		return

	EdgegapSettings.set_token(_pending_token)
	EdgegapSettings.clear_registry_credentials()
	verified.emit(
		true,
		"Token verified, but registry credentials failed (HTTP %d). Try re-logging." % response_code
	)
	EdgegapLogger.error(
		"Couldn't retrieve Edgegap registry credentials, try re-logging.\n%s" % body
	)
