extends RefCounted
class_name EdgegapSettings

const EdgegapConstants = preload("../constants.gd")
const EdgegapPaths = preload("paths.gd")

static func _editor_settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()

static func ensure_defaults() -> void:
	var es := _editor_settings()
	_ensure_setting(es, EdgegapConstants.SETTINGS_TOKEN, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_TOKEN_VERIFIED, false)
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_URL, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_PROJECT, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_USERNAME, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_REGISTRY_TOKEN, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_LOCAL_CONTAINER_ID, "")
	_ensure_setting(es, EdgegapConstants.SETTINGS_LAST_DEPLOYMENT_ID, "")

static func _ensure_setting(es: EditorSettings, key: String, default_value: Variant) -> void:
	if not es.has_setting(key):
		es.set_setting(key, default_value)
	es.set_initial_value(key, default_value, false)

static func get_token() -> String:
	return str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_TOKEN))

static func set_token(token: String) -> void:
	var es := _editor_settings()
	es.set_setting(EdgegapConstants.SETTINGS_TOKEN, token)
	es.set_setting(EdgegapConstants.SETTINGS_TOKEN_VERIFIED, not token.is_empty())

static func clear_token() -> void:
	set_token("")
	clear_registry_credentials()

static func is_token_verified() -> bool:
	return bool(_editor_settings().get_setting(EdgegapConstants.SETTINGS_TOKEN_VERIFIED)) \
		and not get_token().is_empty()

static func set_registry_credentials(credentials: Dictionary) -> void:
	var es := _editor_settings()
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_URL, str(credentials.get("registry_url", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_PROJECT, str(credentials.get("project", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_USERNAME, str(credentials.get("username", "")))
	es.set_setting(EdgegapConstants.SETTINGS_REGISTRY_TOKEN, str(credentials.get("token", "")))

static func clear_registry_credentials() -> void:
	set_registry_credentials({})

static func get_registry_credentials() -> Dictionary:
	return {
		"registry_url": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_URL)),
		"project": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_PROJECT)),
		"username": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_USERNAME)),
		"token": str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_REGISTRY_TOKEN)),
	}

static func has_registry_credentials() -> bool:
	var creds := get_registry_credentials()
	return (
		not str(creds.registry_url).is_empty()
		and not str(creds.username).is_empty()
		and not str(creds.token).is_empty()
	)

static func get_local_container_id() -> String:
	return str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_LOCAL_CONTAINER_ID))

static func set_local_container_id(container_id: String) -> void:
	_editor_settings().set_setting(EdgegapConstants.SETTINGS_LOCAL_CONTAINER_ID, container_id)

static func clear_local_container_id() -> void:
	set_local_container_id("")

static func get_last_deployment_id() -> String:
	return str(_editor_settings().get_setting(EdgegapConstants.SETTINGS_LAST_DEPLOYMENT_ID))

static func set_last_deployment_id(request_id: String) -> void:
	_editor_settings().set_setting(EdgegapConstants.SETTINGS_LAST_DEPLOYMENT_ID, request_id)

static func clear_last_deployment_id() -> void:
	set_last_deployment_id("")

static func default_image_name() -> String:
	var name := String(ProjectSettings.get_setting("application/config/name", "godot-server"))
	name = name.strip_edges().to_lower().replace(" ", "-")
	if name.is_empty():
		return "godot-server"
	return name

static func default_dockerfile_path() -> String:
	return ProjectSettings.globalize_path(EdgegapPaths.dockerfile_res_path())

static func is_arm_cpu() -> bool:
	if OS.has_feature("arm64") or OS.has_feature("arm32"):
		return true
	var arch := Engine.get_architecture_name().to_lower()
	if arch.begins_with("arm") or arch == "aarch64":
		return true
	var cpu := OS.get_processor_name().to_lower()
	if "apple m" in cpu or "snapdragon" in cpu:
		return true
	# Catch Apple Silicon even when the editor runs under Rosetta (x86_64).
	if OS.get_name() == "macOS":
		var out: Array = []
		OS.execute("uname", PackedStringArray(["-m"]), out, true, false)
		var machine := " ".join(PackedStringArray(out)).to_lower()
		if "arm" in machine or "aarch64" in machine:
			return true
	return false

static func default_docker_build_params() -> String:
	if is_arm_cpu():
		return EdgegapConstants.DOCKER_ARM_PLATFORM
	return ""

static func default_docker_run_params() -> String:
	return "-p %d/udp" % EdgegapConstants.DEFAULT_SERVER_PORT

static func unity_style_timestamp_tag() -> String:
	var utc := Time.get_datetime_dict_from_system(true)
	return "%02d.%02d.%02d-%02d.%02d.%02d-UTC" % [
		utc.year % 100, utc.month, utc.day, utc.hour, utc.minute, utc.second
	]
