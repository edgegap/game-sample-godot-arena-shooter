@tool
extends ScrollContainer

const ConstantsScript = preload("../constants.gd")
const SettingsScript = preload("../services/settings.gd")
const LoggerScript = preload("../services/logger.gd")
const AuthScript = preload("../services/auth.gd")
const TemplatesScript = preload("../services/export_templates.gd")
const PresetScript = preload("../services/export_preset.gd")
const ExportScript = preload("../services/headless_export.gd")
const DockerScript = preload("../services/docker.gd")
const AppApiScript = preload("../services/app_api.gd")
const DeploymentsApiScript = preload("../services/deployments_api.gd")
const PathsScript = preload("../services/paths.gd")
const RevertibleFieldScript = preload("revertible_field.gd")
const ActionStatusScript = preload("action_status.gd")

var _root := VBoxContainer.new()
var _signed_out_box := VBoxContainer.new()
var _auth_box := VBoxContainer.new()
var _workflow_box := VBoxContainer.new()

var _get_token_btn := Button.new()
var _sign_in_btn := Button.new()
var _sign_out_btn := Button.new()

var _token_edit := LineEdit.new()
var _auth_status
var _templates_status
var _export_status
var _docker_status
var _containerize_status
var _rebuild_status
var _local_status
var _upload_status
var _deploy_status

var _validate_templates_btn := Button.new()
var _export_btn := Button.new()
var _validate_token_btn := Button.new()
var _containerize_btn := Button.new()
var _rebuild_btn := Button.new()
var _deploy_local_btn := Button.new()
var _terminate_local_btn := Button.new()
var _upload_btn := Button.new()
var _app_dropdown_btn := Button.new()
var _deploy_btn := Button.new()
var _stop_deploy_btn := Button.new()
var _deploy_app_dropdown_btn := Button.new()
var _deploy_version_dropdown_btn := Button.new()

var _image_name_field
var _image_tag_field
var _dockerfile_field
var _build_params_field
var _run_params_field
var _local_tag_option := OptionButton.new()
var _app_name_edit := LineEdit.new()
var _upload_image_option := OptionButton.new()
var _app_names_popup := PopupMenu.new()
var _deploy_app_name_edit := LineEdit.new()
var _deploy_version_edit := LineEdit.new()
var _deploy_app_names_popup := PopupMenu.new()
var _deploy_versions_popup := PopupMenu.new()

var _http := HTTPRequest.new()
var _app_http := HTTPRequest.new()
var _deploy_http := HTTPRequest.new()
var _auth
var _templates
var _presets
var _exporter
var _docker
var _app_api
var _deploy_api

var _awaiting_token_entry := false
var _exporting := false
var _export_progress := 0.0
var _containerizing := false
var _containerize_progress := 0.0
var _rebuilding := false
var _pushing := false
var _push_progress := 0.0
var _uploading := false
var _upload_remote_ref := ""
var _stored_app_names: PackedStringArray = []
var _stored_app_versions: PackedStringArray = []
var _pending_app_dropdown_open := false
var _pending_deploy_app_dropdown_open := false
var _pending_deploy_version_dropdown_open := false
var _token_debounce: Timer
var _token_validating := false
var _token_validate_again := false
var _suppress_token_changed := false

enum DeployPhase { IDLE, IP, CREATE, POLL_READY, LIST_STOP, STOP, POLL_STOP }
var _deploy_phase: DeployPhase = DeployPhase.IDLE
var _deploy_request_id := ""
var _deploy_poll_timer: Timer
var _deploy_elapsed := 0.0

const TOKEN_VALIDATE_DEBOUNCE_SEC := 0.75
const APP_NAME_ALLOWED := "^[a-zA-Z0-9_+\\-.]*$"

func _ready() -> void:
	_auth = AuthScript.new()
	_templates = TemplatesScript.new()
	_presets = PresetScript.new()
	_exporter = ExportScript.new()
	_docker = DockerScript.new()
	_app_api = AppApiScript.new()
	_deploy_api = DeploymentsApiScript.new()

	SettingsScript.ensure_defaults()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)

	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.focus_mode = Control.FOCUS_CLICK
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)

	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_auth.bind_http(_http)
	_auth.verified.connect(_on_auth_verified)

	add_child(_app_http)
	_app_api.bind_http(_app_http)
	_app_api.get_apps_completed.connect(_on_get_apps_completed)
	_app_api.get_versions_completed.connect(_on_get_versions_completed)

	add_child(_deploy_http)
	_deploy_api.bind_http(_deploy_http)
	_deploy_api.ip_completed.connect(_on_deploy_ip_completed)
	_deploy_api.create_completed.connect(_on_deploy_create_completed)
	_deploy_api.status_completed.connect(_on_deploy_status_completed)
	_deploy_api.list_completed.connect(_on_deploy_list_completed)
	_deploy_api.stop_completed.connect(_on_deploy_stop_completed)

	_deploy_poll_timer = Timer.new()
	_deploy_poll_timer.one_shot = true
	_deploy_poll_timer.wait_time = ConstantsScript.DEPLOY_POLL_SECONDS
	_deploy_poll_timer.timeout.connect(_on_deploy_poll_timeout)
	add_child(_deploy_poll_timer)

	_build_header()
	_build_discord_row()
	_build_auth()
	_build_workflow()
	_refresh_auth_visibility()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _token_edit.has_focus():
		return
	var mouse_pos := get_global_mouse_position()
	if not get_global_rect().has_point(mouse_pos):
		return
	if _token_edit.get_global_rect().has_point(mouse_pos):
		return
	_token_edit.release_focus()

func _new_action_status():
	return ActionStatusScript.new()

func _action_block(button_row: Control, status, target_button: Button) -> VBoxContainer:
	status.bind(target_button)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	box.add_child(button_row)
	box.add_child(status)
	return box

func _button_row(secondaries: Array = [], primaries: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for btn in primaries:
		row.add_child(btn)
	if not secondaries.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		for btn in secondaries:
			row.add_child(btn)
	return row

func _style_primary(button: Button) -> void:
	button.flat = false

func _style_secondary(button: Button) -> void:
	button.flat = false
	var theme := EditorInterface.get_editor_theme()
	var bg := Color("#292929")
	var bg_hover := bg.lightened(0.08)
	var bg_pressed := bg.darkened(0.06)
	var border := theme.get_color("font_color", "Editor")
	border.a = 0.45

	button.add_theme_stylebox_override("normal", _make_outlined_button_style(bg, border))
	button.add_theme_stylebox_override("hover", _make_outlined_button_style(bg_hover, border))
	button.add_theme_stylebox_override("pressed", _make_outlined_button_style(bg_pressed, border))
	button.add_theme_stylebox_override("disabled", _make_outlined_button_style(bg, Color(border, border.a * 0.5)))
	button.add_theme_stylebox_override("focus", _make_outlined_button_style(bg, border))

func _set_button_icon(button: Button, icon_names: Array) -> void:
	var theme := EditorInterface.get_editor_theme()
	for icon_name in icon_names:
		if theme.has_icon(icon_name, "EditorIcons"):
			button.icon = theme.get_icon(icon_name, "EditorIcons")
			button.expand_icon = false
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_constant_override("icon_max_width", 16)
			return

func _make_outlined_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _make_collapsible_section(title: String, expanded: bool = true) -> Dictionary:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	root.add_child(HSeparator.new())

	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", 16)
	header.text = _section_header_text(title, expanded)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.visible = expanded

	header.pressed.connect(func():
		body.visible = not body.visible
		header.text = _section_header_text(title, body.visible)
	)

	root.add_child(header)
	root.add_child(body)
	return { "root": root, "body": body, "header": header, "title": title }

func _section_header_text(title: String, expanded: bool) -> String:
	return ("%s  %s" % ["▼" if expanded else "▶", title])

func _clear_action_statuses() -> void:
	for status in [
		_auth_status, _templates_status, _export_status, _docker_status,
		_containerize_status, _rebuild_status, _local_status, _upload_status,
		_deploy_status
	]:
		if status:
			status.clear_all()

func _build_header() -> void:
	var tex := load(PathsScript.addon_root().path_join("assets/banner.png")) as Texture2D

	var clip := Control.new()
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	if tex:
		clip.custom_minimum_size = Vector2(0, tex.get_height())

	var banner := TextureRect.new()
	banner.texture = tex
	banner.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	banner.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	banner.tooltip_text = ConstantsScript.SITE_URL
	banner.gui_input.connect(_on_banner_gui_input)
	if tex:
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		banner.anchor_left = 1.0
		banner.anchor_top = 0.0
		banner.anchor_right = 1.0
		banner.anchor_bottom = 0.0
		banner.offset_left = -w
		banner.offset_top = 0.0
		banner.offset_right = 0.0
		banner.offset_bottom = h

	clip.add_child(banner)
	_root.add_child(clip)

func _on_banner_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(ConstantsScript.SITE_URL)

func _build_discord_row() -> void:
	var discord := Button.new()
	discord.text = "Join our Discord"
	discord.pressed.connect(func(): OS.shell_open(ConstantsScript.DISCORD_URL))
	_root.add_child(discord)

func _build_auth() -> void:
	var section: Dictionary = _make_collapsible_section("1. Connect your Edgegap Account", true)
	_root.add_child(section.root)
	var body: VBoxContainer = section.body

	_signed_out_box.add_theme_constant_override("separation", 8)
	_sign_in_btn.text = "Sign in"
	_style_primary(_sign_in_btn)
	_set_button_icon(_sign_in_btn, ["Key"])
	_sign_in_btn.pressed.connect(_on_sign_in_pressed)
	_signed_out_box.add_child(_button_row([], [_sign_in_btn]))
	body.add_child(_signed_out_box)

	_auth_box.add_theme_constant_override("separation", 8)
	_token_edit.secret = true
	_token_edit.placeholder_text = "token xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
	_token_edit.focus_entered.connect(func(): _token_edit.secret = false)
	_token_edit.focus_exited.connect(func(): _token_edit.secret = true)
	_token_edit.text_changed.connect(_on_token_text_changed)
	_auth_box.add_child(_token_edit)

	_token_debounce = Timer.new()
	_token_debounce.wait_time = TOKEN_VALIDATE_DEBOUNCE_SEC
	_token_debounce.one_shot = true
	_token_debounce.timeout.connect(_on_validate_token)
	add_child(_token_debounce)

	_get_token_btn.text = "Get token"
	_style_primary(_get_token_btn)
	_set_button_icon(_get_token_btn, ["Key"])
	_get_token_btn.pressed.connect(func(): OS.shell_open(ConstantsScript.SIGN_IN_URL))
	_validate_token_btn.text = "Validate token"
	_style_secondary(_validate_token_btn)
	_set_button_icon(_validate_token_btn, ["Search"])
	_validate_token_btn.pressed.connect(_on_validate_token)
	_sign_out_btn.text = "Sign out"
	_style_secondary(_sign_out_btn)
	_set_button_icon(_sign_out_btn, ["GuiClose"])
	_sign_out_btn.pressed.connect(_on_sign_out)

	_auth_status = _new_action_status()
	_auth_box.add_child(_action_block(
		_button_row([_validate_token_btn, _sign_out_btn], [_get_token_btn]),
		_auth_status,
		_validate_token_btn
	))
	body.add_child(_auth_box)

func _build_workflow() -> void:
	_workflow_box.add_theme_constant_override("separation", 4)
	_workflow_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var build_section: Dictionary = _make_collapsible_section("2. Build Your Game Server", true)
	var build_body: VBoxContainer = build_section.body

	_validate_templates_btn.text = "Validate export templates"
	_style_secondary(_validate_templates_btn)
	_set_button_icon(_validate_templates_btn, ["Search"])
	_validate_templates_btn.tooltip_text = "Check Linux export templates. Opens Godot's template manager if they are missing."
	_validate_templates_btn.pressed.connect(func(): _on_validate_templates(true))
	var open_presets := Button.new()
	open_presets.text = "Open export presets"
	_style_secondary(open_presets)
	_set_button_icon(open_presets, ["FileList", "Filesystem", "Folder"])
	open_presets.pressed.connect(func(): _presets.open_export_dialog())
	_export_btn.text = "Export server"
	_style_primary(_export_btn)
	_set_button_icon(_export_btn, ["ExternalLink", "Forward", "ArrowRight"])
	_export_btn.pressed.connect(_on_export_server)

	_templates_status = _new_action_status()
	_templates_status.bind(_validate_templates_btn)
	_export_status = _new_action_status()
	_export_status.bind(_export_btn)

	var build_actions := VBoxContainer.new()
	build_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_actions.add_theme_constant_override("separation", 4)
	build_actions.add_child(_button_row(
		[_validate_templates_btn, open_presets],
		[_export_btn]
	))
	build_actions.add_child(_templates_status)
	build_actions.add_child(_export_status)
	build_body.add_child(build_actions)
	_workflow_box.add_child(build_section.root)

	var containerize_section: Dictionary = _make_collapsible_section("3. Containerize Your Server", true)
	var containerize_body: VBoxContainer = containerize_section.body

	_image_name_field = RevertibleFieldScript.new()
	_image_tag_field = RevertibleFieldScript.new()
	_dockerfile_field = RevertibleFieldScript.new()
	_build_params_field = RevertibleFieldScript.new()
	containerize_body.add_child(_labeled("Image name", _image_name_field))
	containerize_body.add_child(_labeled("Image tag", _image_tag_field))
	containerize_body.add_child(_labeled("Dockerfile path", _dockerfile_field))
	containerize_body.add_child(_labeled("Optional Docker build parameters", _build_params_field))

	_rebuild_btn.text = "Rebuild from source"
	_style_secondary(_rebuild_btn)
	_set_button_icon(_rebuild_btn, ["Reload", "HistoryRedo"])
	_rebuild_btn.pressed.connect(_on_rebuild_from_source)
	var validate_docker := Button.new()
	validate_docker.text = "Validate Docker"
	_style_secondary(validate_docker)
	_set_button_icon(validate_docker, ["Search"])
	validate_docker.pressed.connect(_on_validate_docker)
	_containerize_btn.text = "Containerize with Docker"
	_style_primary(_containerize_btn)
	_set_button_icon(_containerize_btn, ["Package", "ResourcePreloader", "PackedScene"])
	_containerize_btn.pressed.connect(_on_containerize)
	var docker_row := _button_row([validate_docker, _rebuild_btn], [_containerize_btn])

	_docker_status = _new_action_status()
	_docker_status.bind(validate_docker)
	_containerize_status = _new_action_status()
	_containerize_status.bind(_containerize_btn)
	_rebuild_status = _new_action_status()
	_rebuild_status.bind(_rebuild_btn)

	var docker_actions := VBoxContainer.new()
	docker_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	docker_actions.add_theme_constant_override("separation", 4)
	docker_actions.add_child(docker_row)
	docker_actions.add_child(_rebuild_status)
	docker_actions.add_child(_docker_status)
	docker_actions.add_child(_containerize_status)
	containerize_body.add_child(docker_actions)
	_workflow_box.add_child(containerize_section.root)

	var test_section: Dictionary = _make_collapsible_section("4. Test Your Server Locally", true)
	var test_body: VBoxContainer = test_section.body
	_local_tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_local_tag_option.get_popup().about_to_popup.connect(_refresh_local_images)
	test_body.add_child(_labeled("Server image", _local_tag_option))
	_run_params_field = RevertibleFieldScript.new()
	test_body.add_child(_labeled("Docker run parameters", _run_params_field))

	_deploy_local_btn.text = "Deploy local container"
	_style_primary(_deploy_local_btn)
	_set_button_icon(_deploy_local_btn, ["Play", "MainPlay"])
	_deploy_local_btn.pressed.connect(_on_deploy_local)
	_terminate_local_btn.text = "Terminate"
	_style_primary(_terminate_local_btn)
	_set_button_icon(_terminate_local_btn, ["Stop"])
	_terminate_local_btn.pressed.connect(_on_terminate_local)
	_local_status = _new_action_status()
	test_body.add_child(_action_block(
		_button_row([], [_deploy_local_btn, _terminate_local_btn]),
		_local_status,
		_deploy_local_btn
	))
	_workflow_box.add_child(test_section.root)

	var upload_section: Dictionary = _make_collapsible_section("5. Upload to Edgegap", true)
	var upload_body: VBoxContainer = upload_section.body

	var app_name_row := HBoxContainer.new()
	app_name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_name_row.add_theme_constant_override("separation", 6)
	_app_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_app_name_edit.placeholder_text = "Application name"
	_app_name_edit.focus_exited.connect(_on_app_name_focus_exited)
	_app_dropdown_btn.custom_minimum_size = Vector2(28, 0)
	_set_button_icon(_app_dropdown_btn, ["GuiTreeArrowDown", "ArrowDown"])
	_app_dropdown_btn.tooltip_text = "Choose an existing Edgegap application"
	_app_dropdown_btn.pressed.connect(_on_app_name_dropdown_pressed)
	_app_names_popup.id_pressed.connect(_on_app_name_popup_id)
	add_child(_app_names_popup)
	app_name_row.add_child(_app_name_edit)
	app_name_row.add_child(_app_dropdown_btn)
	upload_body.add_child(_labeled("Application name", app_name_row))

	_upload_image_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upload_image_option.get_popup().about_to_popup.connect(_refresh_local_images)
	upload_body.add_child(_labeled("Server image", _upload_image_option))

	var port_link := Button.new()
	port_link.text = "See how to set port mapping"
	port_link.flat = true
	port_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_button_icon(port_link, ["ExternalLink", "Help"])
	port_link.pressed.connect(func(): _open_edgegap_docs(ConstantsScript.DOC_PORT_MAPPING_PATH))
	upload_body.add_child(port_link)

	_upload_btn.text = "Upload image & create app version"
	_style_primary(_upload_btn)
	_set_button_icon(_upload_btn, ["ArrowUp", "Forward", "ExternalLink"])
	_upload_btn.pressed.connect(_on_upload)

	_upload_status = _new_action_status()
	upload_body.add_child(_action_block(
		_button_row([], [_upload_btn]),
		_upload_status,
		_upload_btn
	))

	_workflow_box.add_child(upload_section.root)

	var deploy_section: Dictionary = _make_collapsible_section("6. Deploy a Server on Edgegap", true)
	var deploy_body: VBoxContainer = deploy_section.body

	var deploy_app_row := HBoxContainer.new()
	deploy_app_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_app_row.add_theme_constant_override("separation", 6)
	_deploy_app_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deploy_app_name_edit.placeholder_text = "Application name"
	_deploy_app_name_edit.text_changed.connect(_on_deploy_app_name_changed)
	_deploy_app_dropdown_btn.custom_minimum_size = Vector2(28, 0)
	_set_button_icon(_deploy_app_dropdown_btn, ["GuiTreeArrowDown", "ArrowDown"])
	_deploy_app_dropdown_btn.tooltip_text = "Choose an existing Edgegap application"
	_deploy_app_dropdown_btn.pressed.connect(_on_deploy_app_dropdown_pressed)
	_deploy_app_names_popup.id_pressed.connect(_on_deploy_app_popup_id)
	add_child(_deploy_app_names_popup)
	deploy_app_row.add_child(_deploy_app_name_edit)
	deploy_app_row.add_child(_deploy_app_dropdown_btn)
	deploy_body.add_child(_labeled("Application name", deploy_app_row))

	var deploy_version_row := HBoxContainer.new()
	deploy_version_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_version_row.add_theme_constant_override("separation", 6)
	_deploy_version_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deploy_version_edit.placeholder_text = "Application version"
	_deploy_version_edit.text_changed.connect(func(_t: String): _update_deploy_buttons_enabled())
	_deploy_version_dropdown_btn.custom_minimum_size = Vector2(28, 0)
	_set_button_icon(_deploy_version_dropdown_btn, ["GuiTreeArrowDown", "ArrowDown"])
	_deploy_version_dropdown_btn.tooltip_text = "Choose an active application version"
	_deploy_version_dropdown_btn.pressed.connect(_on_deploy_version_dropdown_pressed)
	_deploy_versions_popup.id_pressed.connect(_on_deploy_version_popup_id)
	add_child(_deploy_versions_popup)
	deploy_version_row.add_child(_deploy_version_edit)
	deploy_version_row.add_child(_deploy_version_dropdown_btn)
	deploy_body.add_child(_labeled("Application version", deploy_version_row))

	var free_tier_link := Button.new()
	free_tier_link.text = "You're limited to 1 deployment and 60 minutes of runtime per instance in Free Tier."
	free_tier_link.flat = true
	free_tier_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	free_tier_link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_button_icon(free_tier_link, ["ExternalLink", "Help"])
	free_tier_link.pressed.connect(func(): _open_edgegap_url(ConstantsScript.FREE_TIER_INFO_URL))
	deploy_body.add_child(free_tier_link)

	_deploy_btn.text = "Deploy to cloud"
	_style_primary(_deploy_btn)
	_set_button_icon(_deploy_btn, ["Play", "Forward", "ArrowRight"])
	_deploy_btn.pressed.connect(_on_deploy_to_cloud)

	_stop_deploy_btn.text = "Stop last deployment"
	_style_secondary(_stop_deploy_btn)
	_set_button_icon(_stop_deploy_btn, ["Stop", "Remove", "Close"])
	_stop_deploy_btn.pressed.connect(_on_stop_last_deployment)

	_deploy_status = _new_action_status()
	deploy_body.add_child(_action_block(
		_button_row([_stop_deploy_btn], [_deploy_btn]),
		_deploy_status,
		_deploy_btn
	))

	_workflow_box.add_child(deploy_section.root)
	_update_deploy_buttons_enabled()

	_root.add_child(_workflow_box)
	_reload_field_defaults()

func _labeled(title: String, field: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(field)
	return box

func _reload_field_defaults() -> void:
	if _image_name_field == null:
		return
	var image_default: String = SettingsScript.default_image_name()
	_image_name_field.configure(image_default, image_default)
	_image_tag_field.configure("", "", "yy.MM.dd-HH.mm.ss-UTC (auto on build)")
	_image_tag_field.set_value("")
	var docker_default: String = SettingsScript.default_dockerfile_path()
	_dockerfile_field.configure(docker_default, docker_default)
	var build_default: String = SettingsScript.default_docker_build_params()
	_build_params_field.configure(build_default, build_default)
	var run_default: String = SettingsScript.default_docker_run_params()
	_run_params_field.configure(run_default, run_default)
	_set_token_edit_text(SettingsScript.get_token())
	_refresh_local_images()
	_on_validate_templates()

func _refresh_auth_visibility() -> void:
	var has_token: bool = SettingsScript.is_token_verified()
	if has_token:
		_awaiting_token_entry = false
		_signed_out_box.visible = false
		_auth_box.visible = true
		_workflow_box.visible = true
		_set_token_edit_text(SettingsScript.get_token())
		_reload_field_defaults()
		return

	_auth_box.visible = _awaiting_token_entry
	_workflow_box.visible = false
	_signed_out_box.visible = not _awaiting_token_entry

func _on_sign_in_pressed() -> void:
	OS.shell_open(ConstantsScript.SIGN_IN_URL)
	_awaiting_token_entry = true
	_refresh_auth_visibility()
	_token_edit.grab_focus()
	if _auth_status:
		_auth_status.clear()

func _on_sign_out() -> void:
	if _token_debounce:
		_token_debounce.stop()
	if _deploy_poll_timer:
		_deploy_poll_timer.stop()
	_deploy_phase = DeployPhase.IDLE
	_deploy_request_id = ""
	SettingsScript.clear_token()
	_set_token_edit_text("")
	_awaiting_token_entry = false
	_clear_action_statuses()
	_refresh_auth_visibility()

func _set_token_edit_text(value: String) -> void:
	_suppress_token_changed = true
	_token_edit.text = value
	_suppress_token_changed = false

func _on_token_text_changed(_text: String) -> void:
	if _suppress_token_changed:
		return
	if _token_debounce:
		_token_debounce.start()

func _on_validate_token() -> void:
	var token := _token_edit.text.strip_edges()
	if token.is_empty():
		_token_validating = false
		_token_validate_again = false
		_validate_token_btn.disabled = false
		if _auth_status:
			_auth_status.clear()
		return
	if _token_validating:
		_token_validate_again = true
		return
	_token_validating = true
	_validate_token_btn.disabled = true
	_auth_status.set_busy("Validating token via Edgegap wizard…", 20)
	_auth.validate_token(token)

func _on_auth_verified(ok: bool, message: String) -> void:
	_token_validating = false
	_validate_token_btn.disabled = false
	if ok:
		# Refresh UI first, then stamp the result so nothing overwrites the button mark.
		_refresh_auth_visibility()
		_auth_status.bind(_validate_token_btn)
		_auth_status.set_success(message)
		if SettingsScript.has_registry_credentials():
			var creds := SettingsScript.get_registry_credentials()
			LoggerScript.info(
				"Registry ready: %s / project=%s / user=%s" % [
					creds.registry_url, creds.project, creds.username
				]
			)
	else:
		_auth_status.bind(_validate_token_btn)
		_auth_status.set_error(message)

	if _token_validate_again:
		_token_validate_again = false
		_on_validate_token()

func _process(delta: float) -> void:
	if _exporting:
		var export_status = _pipeline_status()
		if _exporter.is_running():
			var cap := 35.0 if _rebuilding else 90.0
			_export_progress = minf(_export_progress + delta * 12.0, cap)
			if export_status:
				export_status.set_progress(
					_export_progress,
					"Rebuild: exporting…" if _rebuilding else "Exporting dedicated server (debug)…"
				)
		else:
			_finish_export()

	if _containerizing:
		var build_status = _pipeline_status()
		if _docker.is_build_running():
			var floor_pct := 45.0 if _rebuilding else 10.0
			_containerize_progress = maxf(_containerize_progress, floor_pct)
			_containerize_progress = minf(_containerize_progress + delta * 8.0, 90.0)
			if build_status:
				build_status.set_progress(
					_containerize_progress,
					"Rebuild: building Docker image…" if _rebuilding else "Building Docker image…"
				)
		else:
			_finish_containerize()

	if _pushing:
		if _docker.is_push_running():
			_push_progress = minf(_push_progress + delta * 6.0, 85.0)
			if _upload_status:
				_upload_status.set_progress(_push_progress, "Pushing Docker image…")
		else:
			_finish_push()

func _on_validate_templates(open_manager_if_missing: bool = false) -> void:
	_templates_status.bind(_validate_templates_btn)
	var ok: bool = _templates.is_installed()
	LoggerScript.info(
		"Templates check: version=%s dir=%s installed=%s" % [
			_templates.resolved_version(), _templates.templates_dir(), ok
		]
	)
	if _templates_status == null:
		return
	if ok:
		_templates_status.set_success("Templates OK.")
		LoggerScript.info(_templates.status_message())
		return

	LoggerScript.warn(_templates.status_message())
	if open_manager_if_missing and _templates.open_template_manager():
		_templates_status.set_error(
			"Templates missing — use Godot's manager to download, then Validate again."
		)
		return
	_templates_status.set_error("Templates missing — install required.")

func _on_export_server() -> void:
	if _exporting or _containerizing or _rebuilding or _uploading:
		return
	_start_export(_export_status, _export_btn)

func _start_export(status, trigger_btn: Button) -> bool:
	status.bind(trigger_btn)
	status.set_busy("Preparing export…", 5)
	var preset_err: Error = _presets.ensure_preset()
	if preset_err != OK:
		status.set_error("Failed to ensure export preset. See Output.")
		return false

	if not _templates.is_installed():
		_on_validate_templates()
		status.set_error("Export templates missing. Install them first.")
		return false

	_export_progress = 10.0
	_exporting = true
	_set_pipeline_buttons_disabled(true)
	status.set_busy("Exporting dedicated server (debug)…", _export_progress)

	var err: Error = _exporter.start_export_debug(
		ConstantsScript.PRESET_NAME,
		_presets.get_export_path()
	)
	if err != OK:
		_exporting = false
		_set_pipeline_buttons_disabled(false)
		status.set_error("Failed to start export. See Output.")
		return false
	return true

func _pipeline_status():
	if _rebuilding:
		return _rebuild_status
	if _containerizing:
		return _containerize_status
	return _export_status

func _pipeline_trigger_btn() -> Button:
	if _rebuilding:
		return _rebuild_btn
	return _export_btn

func _finish_export() -> void:
	var status = _pipeline_status()
	var trigger_btn: Button = _pipeline_trigger_btn()
	status.bind(trigger_btn)
	var code: int = _exporter.take_exit_code()
	_exporting = false

	if code != 0:
		_rebuilding = false
		_set_pipeline_buttons_disabled(false)
		status.set_error("Export failed (exit %d). See Output." % code)
		LoggerScript.error("Export failed with exit code %d" % code)
		return

	var out_path: String = _exporter.export_output_path()
	if not FileAccess.file_exists(out_path):
		_rebuilding = false
		_set_pipeline_buttons_disabled(false)
		status.set_error("Export finished but binary missing. See Output.")
		LoggerScript.error("Export finished but binary missing at %s" % out_path)
		return

	LoggerScript.info("Export succeeded: %s" % out_path)
	if _rebuilding:
		status.set_progress(40, "Export finished — starting containerize…")
		if not _start_containerize(status, trigger_btn):
			_rebuilding = false
			_set_pipeline_buttons_disabled(false)
		return

	_set_pipeline_buttons_disabled(false)
	status.set_success("Export finished: %s" % _presets.get_export_path())

func _on_validate_docker() -> void:
	_docker_status.set_busy("Checking Docker…", 30)
	var status = _docker.check_status()
	var message: String = _docker.status_message(status)
	match status:
		DockerScript.Status.OK:
			_docker_status.set_success(message)
			LoggerScript.info(message)
		DockerScript.Status.NOT_RUNNING:
			_docker_status.set_error(message)
			LoggerScript.warn(message)
		_:
			_docker_status.set_error(message)
			LoggerScript.error("%s Opening install page." % message)
			_docker.open_install_page()

func _on_containerize() -> void:
	if _exporting or _containerizing or _rebuilding or _uploading:
		return
	_start_containerize(_containerize_status, _containerize_btn)

func _on_rebuild_from_source() -> void:
	if _exporting or _containerizing or _rebuilding or _uploading:
		return
	_rebuilding = true
	_rebuild_status.bind(_rebuild_btn)
	_rebuild_status.set_busy("Rebuild from source: exporting…", 5)
	if not _start_export(_rebuild_status, _rebuild_btn):
		_rebuilding = false

func _start_containerize(status, trigger_btn: Button) -> bool:
	var docker_status = _docker.check_status()
	if docker_status != DockerScript.Status.OK:
		var message: String = _docker.status_message(docker_status)
		status.set_error(message)
		if docker_status == DockerScript.Status.NOT_RUNNING:
			LoggerScript.warn(message)
		else:
			LoggerScript.error("%s Opening install page." % message)
			_docker.open_install_page()
		return false

	if not _presets.has_preset():
		status.set_error("Export preset missing. Run Export server first.")
		return false

	var image_name: String = _image_name_field.get_value().strip_edges()
	var image_tag: String = _image_tag_field.get_value().strip_edges()
	if image_tag.is_empty():
		image_tag = SettingsScript.unity_style_timestamp_tag()
		_image_tag_field.set_value(image_tag)

	var dockerfile: String = _dockerfile_field.get_value().strip_edges()
	if not FileAccess.file_exists(dockerfile):
		status.set_error("Dockerfile not found.")
		LoggerScript.error("Dockerfile missing at %s" % dockerfile)
		return false

	_containerize_progress = 10.0 if not _rebuilding else 45.0
	status.bind(trigger_btn)
	status.set_busy("Building Docker image…", _containerize_progress)

	var build_params: String = _build_params_field.get_value().strip_edges()
	var err: Error = _docker.start_build_image(
		dockerfile,
		_presets.get_server_build_arg(),
		image_name,
		image_tag,
		build_params
	)
	if err != OK:
		status.set_error("Failed to start Docker build. See Output.")
		return false

	_containerizing = true
	_set_pipeline_buttons_disabled(true)
	return true

func _finish_containerize() -> void:
	var status = _pipeline_status()
	var code: int = _docker.take_build_exit_code()
	_containerizing = false
	var was_rebuild := _rebuilding
	_rebuilding = false
	_set_pipeline_buttons_disabled(false)

	var image_name: String = _docker.build_image_name()
	var image_tag: String = _docker.build_image_tag()
	if code != 0:
		status.set_error(
			("Rebuild" if was_rebuild else "Containerize") + " failed (exit %d). See Output." % code
		)
		return

	_refresh_local_images()
	var built_ref := "%s:%s" % [image_name, image_tag]
	_local_tag_option.select(_find_image_ref_index(_local_tag_option, built_ref))
	_upload_image_option.select(_find_image_ref_index(_upload_image_option, built_ref))
	_maybe_prefill_app_name_from_image(image_name)

	if was_rebuild:
		status.set_success("Rebuild complete: %s:%s" % [image_name, image_tag])
	else:
		status.set_success("Image ready: %s:%s" % [image_name, image_tag])

func _set_pipeline_buttons_disabled(disabled: bool) -> void:
	_export_btn.disabled = disabled
	_containerize_btn.disabled = disabled
	_rebuild_btn.disabled = disabled
	_upload_btn.disabled = disabled
	if disabled:
		_deploy_btn.disabled = true
		_stop_deploy_btn.disabled = true
	else:
		_update_deploy_buttons_enabled()

func _on_deploy_local() -> void:
	_local_status.bind(_deploy_local_btn)
	var docker_status = _docker.check_status()
	if docker_status != DockerScript.Status.OK:
		_local_status.set_error(_docker.status_message(docker_status))
		_refresh_local_images()
		return
	if _docker.is_plugin_container_running():
		_local_status.set_error("A plugin container is already running. Terminate it first.")
		return
	var image_name := ""
	var image_tag := ""
	if _local_tag_option.item_count > 0:
		var selected: String = _local_tag_option.get_item_text(_local_tag_option.selected)
		if _is_docker_unavailable_placeholder(selected):
			_local_status.set_error(selected)
			return
		var parts := selected.rsplit(":", true, 1)
		if parts.size() == 2:
			image_name = parts[0]
			image_tag = parts[1]
		else:
			image_tag = selected
			image_name = _image_name_field.get_value().strip_edges()
	else:
		image_name = _image_name_field.get_value().strip_edges()
		image_tag = _image_tag_field.get_value().strip_edges()
	if image_name.is_empty() or image_tag.is_empty():
		_local_status.set_error("No server image selected.")
		return
	_local_status.set_busy("Starting local container…", 50)
	var id: String = _docker.run_container(image_name, image_tag, _run_params_field.get_value())
	if id.is_empty():
		_local_status.set_error("Failed to start container. See Output.")
		return
	_local_status.set_success("Container running: %s" % id)

func _on_terminate_local() -> void:
	_local_status.bind(_terminate_local_btn)
	if _docker.terminate_plugin_container():
		_local_status.set_success("Terminated local container.")
	else:
		_local_status.set_error("No plugin container to terminate.")

func _refresh_local_images() -> void:
	var previous_local := _short_image_ref(_selected_image_ref(_local_tag_option))
	var previous_upload := _short_image_ref(_selected_image_ref(_upload_image_option))

	var preferred := previous_local
	var field_name: String = _image_name_field.get_value().strip_edges() if _image_name_field else ""
	var field_tag: String = _image_tag_field.get_value().strip_edges() if _image_tag_field else ""
	if not field_name.is_empty() and not field_tag.is_empty():
		preferred = "%s:%s" % [field_name.get_file() if "/" in field_name else field_name, field_tag]

	var docker_status = _docker.check_status()
	if docker_status != DockerScript.Status.OK:
		var placeholder := _docker_unavailable_placeholder(docker_status)
		_fill_image_option(_local_tag_option, [{"display": placeholder, "uploaded": false, "local_ref": ""}], "")
		_fill_image_option(_upload_image_option, [{"display": placeholder, "uploaded": false, "local_ref": ""}], "")
		return

	var refs: PackedStringArray = _docker.list_local_image_refs()
	var entries: Array = _dedupe_image_refs(refs)
	if entries.is_empty() and not preferred.is_empty():
		entries.append({"display": preferred, "uploaded": false, "local_ref": preferred})
	if entries.is_empty():
		entries.append({
			"display": "No local images — containerize your server first",
			"uploaded": false,
			"local_ref": "",
		})

	var local_preferred := preferred if not preferred.is_empty() else previous_local
	var upload_preferred := previous_upload if not previous_upload.is_empty() else preferred
	_fill_image_option(_local_tag_option, entries, local_preferred)
	_fill_image_option(_upload_image_option, entries, upload_preferred)
	_maybe_prefill_app_name_from_selected_upload_image()

## Collapse registry/project duplicates into one "name:tag" row; mark uploaded when a remote tag exists.
func _dedupe_image_refs(refs: PackedStringArray) -> Array:
	var by_key := {}
	var order: PackedStringArray = []
	for ref in refs:
		var text := str(ref).strip_edges()
		if text.is_empty() or _is_docker_unavailable_placeholder(text):
			continue
		var parts := text.rsplit(":", true, 1)
		if parts.size() != 2:
			continue
		var repo := parts[0]
		var tag := parts[1]
		var short_name := repo.get_file() if "/" in repo else repo
		var key := "%s:%s" % [short_name, tag]
		var is_remote := "/" in repo
		if not by_key.has(key):
			by_key[key] = {"display": key, "uploaded": is_remote, "local_ref": text}
			order.append(key)
			continue
		var entry: Dictionary = by_key[key]
		if is_remote:
			entry.uploaded = true
		else:
			# Prefer bare local ref for docker run / tag source.
			entry.local_ref = text
		by_key[key] = entry

	var entries: Array = []
	for key in order:
		entries.append(by_key[key])
	return entries

func _fill_image_option(option: OptionButton, entries: Array, preferred: String) -> void:
	option.get_popup().clear()
	option.clear()
	var cloud_icon := _get_uploaded_image_icon()
	var preferred_short := _short_image_ref(preferred)
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var display := str(entry.get("display", ""))
		var uploaded := bool(entry.get("uploaded", false))
		var local_ref := str(entry.get("local_ref", display))
		var idx := option.item_count
		if uploaded and cloud_icon != null:
			option.add_icon_item(cloud_icon, display)
		else:
			option.add_item(display)
		option.set_item_metadata(idx, {
			"local_ref": local_ref,
			"uploaded": uploaded,
			"display": display,
		})
	if option.item_count == 0:
		return
	if preferred_short.is_empty() or _is_docker_unavailable_placeholder(preferred_short):
		option.select(0)
	else:
		option.select(_find_image_ref_index(option, preferred_short))

func _get_uploaded_image_icon() -> Texture2D:
	# Godot EditorIcons has no cloud glyph; use a bundled SVG.
	var path := PathsScript.addon_root().path_join("assets/cloud.svg")
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	return _get_editor_icon(["ExternalLink", "ArrowUp"])

func _get_editor_icon(icon_names: Array) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for icon_name in icon_names:
		if theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null

func _selected_image_ref(option: OptionButton) -> String:
	if option.item_count <= 0 or option.selected < 0:
		return ""
	var text := option.get_item_text(option.selected)
	if _is_docker_unavailable_placeholder(text):
		return ""
	var meta: Variant = option.get_item_metadata(option.selected)
	if typeof(meta) == TYPE_DICTIONARY:
		var local_ref := str(meta.get("local_ref", ""))
		if not local_ref.is_empty():
			return local_ref
	return text

func _short_image_ref(ref: String) -> String:
	if ref.is_empty() or _is_docker_unavailable_placeholder(ref):
		return ""
	var parsed := _parse_image_ref(ref)
	if parsed.size() != 2:
		return ref
	return "%s:%s" % [parsed[0], parsed[1]]

func _docker_unavailable_placeholder(status) -> String:
	match status:
		DockerScript.Status.NOT_RUNNING:
			return "Docker is not running — start Docker Desktop"
		DockerScript.Status.NOT_INSTALLED:
			return "Docker is not installed"
		_:
			return "Docker is not available"

func _is_docker_unavailable_placeholder(text: String) -> bool:
	return text.begins_with("Docker is not") or text.begins_with("No local images")

func _find_image_ref_index(option: OptionButton, ref: String) -> int:
	var want := _short_image_ref(ref)
	for i in option.item_count:
		if _short_image_ref(option.get_item_text(i)) == want:
			return i
	option.add_item(want if not want.is_empty() else ref)
	return option.item_count - 1

func _tokenize(value: String) -> String:
	var trimmed := value.strip_edges()
	var out := ""
	var prev_dash := false
	for i in trimmed.length():
		var ch := trimmed[i]
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
			or (ch >= "0" and ch <= "9")
		if ok:
			out += ch
			prev_dash = false
		elif not prev_dash:
			out += "-"
			prev_dash = true
	return out.trim_prefix("-").trim_suffix("-")

func _maybe_prefill_app_name_from_selected_upload_image() -> void:
	var selected := _selected_image_ref(_upload_image_option)
	if selected.is_empty():
		return
	var parts := selected.rsplit(":", true, 1)
	if parts.is_empty():
		return
	_maybe_prefill_app_name_from_image(parts[0])

func _maybe_prefill_app_name_from_image(image_name: String) -> void:
	if not _app_name_edit.text.strip_edges().is_empty():
		return
	var short_name := image_name
	if "/" in short_name:
		short_name = short_name.get_file()
	if not short_name.is_empty():
		_app_name_edit.text = _tokenize(short_name)

func _parse_image_ref(ref: String) -> PackedStringArray:
	# Returns [image_name, image_tag] with short image name (no registry/project prefix for push naming).
	var parts := ref.rsplit(":", true, 1)
	if parts.size() != 2:
		return PackedStringArray()
	var repo := parts[0]
	var tag := parts[1]
	var short_name := repo
	if "/" in short_name:
		short_name = short_name.get_file()
	return PackedStringArray([short_name, tag])

func _open_edgegap_docs(path: String) -> void:
	var url := "%s%s" % [ConstantsScript.DOC_BASE_URL, path]
	var anchor_idx := url.find("#")
	if anchor_idx >= 0:
		url = url.insert(anchor_idx, "?%s" % ConstantsScript.UTM_TAGS)
	else:
		url = "%s?%s" % [url, ConstantsScript.UTM_TAGS]
	OS.shell_open(url)

func _open_edgegap_url(url: String) -> void:
	var joiner := "&" if "?" in url else "?"
	OS.shell_open("%s%s%s" % [url, joiner, ConstantsScript.UTM_TAGS])

func _on_app_name_focus_exited() -> void:
	var name := _app_name_edit.text.strip_edges()
	if name.is_empty():
		return
	var re := RegEx.new()
	re.compile(APP_NAME_ALLOWED)
	if re.search(name) == null:
		if _upload_status:
			_upload_status.bind(_upload_btn)
			_upload_status.set_error(
				"App name has invalid characters. Only [a-zA-Z0-9_-+.] are allowed."
			)

func _on_app_name_dropdown_pressed() -> void:
	_pending_app_dropdown_open = true
	_app_api.set_authorization(SettingsScript.get_token())
	var err: Error = _app_api.get_apps()
	if err != OK:
		_pending_app_dropdown_open = false
		if _upload_status:
			_upload_status.bind(_upload_btn)
			_upload_status.set_error("Failed to load applications. See Output.")

func _on_get_apps_completed(ok: bool, response_code: int, app_names: PackedStringArray, _body: String) -> void:
	var wanted_upload := _pending_app_dropdown_open
	var wanted_deploy := _pending_deploy_app_dropdown_open
	_pending_app_dropdown_open = false
	_pending_deploy_app_dropdown_open = false

	if not ok:
		if wanted_upload and _upload_status and not _uploading:
			_upload_status.bind(_upload_btn)
			_upload_status.set_error("Failed to list apps (HTTP %d)." % response_code)
		if wanted_deploy and _deploy_status and _deploy_phase == DeployPhase.IDLE:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("Failed to list apps (HTTP %d)." % response_code)
		return

	_stored_app_names = app_names

	if wanted_upload:
		_app_names_popup.clear()
		_app_names_popup.add_item(ConstantsScript.DEFAULT_NEW_APPLICATION_LABEL, 0)
		var id := 1
		for app_name in _stored_app_names:
			_app_names_popup.add_item(app_name, id)
			id += 1
		_show_dropdown_popup(_app_names_popup, _app_dropdown_btn)

	if wanted_deploy:
		_deploy_app_names_popup.clear()
		var id := 0
		for app_name in _stored_app_names:
			_deploy_app_names_popup.add_item(app_name, id)
			id += 1
		if _deploy_app_names_popup.item_count == 0:
			if _deploy_status:
				_deploy_status.bind(_deploy_btn)
				_deploy_status.set_error("No applications found. Upload an image first.")
			return
		_show_dropdown_popup(_deploy_app_names_popup, _deploy_app_dropdown_btn)

func _show_dropdown_popup(popup: PopupMenu, anchor: Control) -> void:
	# Without max_size, PopupMenu height is clamped to the parent rect (the dock),
	# which often fits only ~10 items and hides the rest with no usable scroll.
	popup.reset_size()
	var anchor_rect := anchor.get_global_rect()
	var width := maxi(int(anchor_rect.size.x), 220)
	popup.max_size = Vector2i(maxi(width, 360), 420)
	var pos := Vector2i(int(anchor_rect.position.x), int(anchor_rect.end.y))
	popup.popup(Rect2i(pos, Vector2i(width, 0)))

func _on_app_name_popup_id(id: int) -> void:
	var label := _app_names_popup.get_item_text(_app_names_popup.get_item_index(id))
	if label == ConstantsScript.DEFAULT_NEW_APPLICATION_LABEL:
		var selected := _selected_image_ref(_upload_image_option)
		var parsed := _parse_image_ref(selected)
		_app_name_edit.text = _tokenize(parsed[0] if parsed.size() == 2 else "")
		_app_name_edit.grab_focus()
		return
	_app_name_edit.text = _tokenize(label)

func _on_upload() -> void:
	if _exporting or _containerizing or _rebuilding or _uploading:
		return
	_start_upload()

func _start_upload() -> void:
	_upload_status.bind(_upload_btn)
	var app_name := _tokenize(_app_name_edit.text)
	_app_name_edit.text = app_name

	var selected := _selected_image_ref(_upload_image_option)
	if selected.is_empty():
		_refresh_local_images()
		selected = _selected_image_ref(_upload_image_option)
	if selected.is_empty() or _is_docker_unavailable_placeholder(
		_upload_image_option.get_item_text(_upload_image_option.selected) if _upload_image_option.item_count > 0 else ""
	):
		_upload_status.set_error("Select a local server image to upload.")
		return

	var parsed := _parse_image_ref(selected)
	if parsed.size() != 2:
		_upload_status.set_error("Invalid server image selection.")
		return
	var image_name := parsed[0]
	var image_tag := parsed[1]

	if app_name.is_empty():
		_upload_status.set_error("Application name is required.")
		return

	var re := RegEx.new()
	re.compile(APP_NAME_ALLOWED)
	if re.search(app_name) == null:
		_upload_status.set_error(
			"App name has invalid characters. Only [a-zA-Z0-9_-+.] are allowed."
		)
		return

	if not SettingsScript.has_registry_credentials():
		_upload_status.set_error("Registry credentials missing. Re-validate your token.")
		return

	var docker_status = _docker.check_status()
	if docker_status != DockerScript.Status.OK:
		_upload_status.set_error(_docker.status_message(docker_status))
		_refresh_local_images()
		return

	var creds := SettingsScript.get_registry_credentials()
	var resolved := _resolve_local_image_ref(image_name, image_tag, str(creds.registry_url), str(creds.project))
	var local_ref := resolved if not resolved.is_empty() else selected
	var refs: PackedStringArray = _docker.list_local_image_refs()
	if refs.find(local_ref) < 0:
		_upload_status.set_error("Local image not found. Containerize your server first.")
		return

	_uploading = true
	_set_pipeline_buttons_disabled(true)
	_upload_status.set_busy("Logging into container registry…", 10)

	if not _docker.login_registry(str(creds.registry_url), str(creds.username), str(creds.token)):
		_uploading = false
		_set_pipeline_buttons_disabled(false)
		_upload_status.set_error("Docker authorization failed (see Output).")
		return

	_upload_status.set_busy("Tagging image for registry…", 20)
	_upload_remote_ref = _docker.tag_for_registry(
		local_ref,
		str(creds.registry_url),
		str(creds.project),
		image_name,
		image_tag
	)
	if _upload_remote_ref.is_empty():
		_uploading = false
		_set_pipeline_buttons_disabled(false)
		_upload_status.set_error("Failed to tag image for registry. See Output.")
		return

	_push_progress = 25.0
	_upload_status.set_busy("Pushing Docker image…", _push_progress)
	var err: Error = _docker.start_push_image(_upload_remote_ref)
	if err != OK:
		_uploading = false
		_set_pipeline_buttons_disabled(false)
		_upload_status.set_error("Failed to start Docker push. See Output.")
		return
	_pushing = true

func _resolve_local_image_ref(image_name: String, image_tag: String, registry_url: String, project: String) -> String:
	var candidates := PackedStringArray([
		"%s:%s" % [image_name, image_tag],
		"%s/%s/%s:%s" % [registry_url, project, image_name, image_tag],
		"%s/%s:%s" % [project, image_name, image_tag],
	])
	var refs: PackedStringArray = _docker.list_local_image_refs()
	for candidate in candidates:
		if refs.find(candidate) >= 0:
			return candidate
	# Soft match: ends with /image:tag or image:tag
	var suffix := "%s:%s" % [image_name, image_tag]
	for ref in refs:
		if ref == suffix or ref.ends_with("/" + suffix):
			return ref
	return ""

func _finish_push() -> void:
	var code: int = _docker.take_push_exit_code()
	_pushing = false
	if code != 0:
		_uploading = false
		_set_pipeline_buttons_disabled(false)
		_upload_status.set_error("Unable to push Docker image to registry (see Output).")
		return
	_finish_upload_open_create_version()

func _finish_upload_open_create_version() -> void:
	var app_name := _app_name_edit.text.strip_edges()
	var selected := _selected_image_ref(_upload_image_option)
	var parsed := _parse_image_ref(selected)
	var image_name := parsed[0] if parsed.size() == 2 else ""
	var image_tag := parsed[1] if parsed.size() == 2 else ""
	var creds := SettingsScript.get_registry_credentials()
	var image_repo := "%s/%s" % [str(creds.project), image_name]
	var url := "%s%s/versions/create/?name=%s&imageRepo=%s&dockerTag=%s&vCPU=1&memory=1" % [
		ConstantsScript.CREATE_APP_BASE_URL,
		app_name.uri_encode(),
		image_tag.uri_encode(),
		image_repo.uri_encode(),
		image_tag.uri_encode(),
	]
	_open_edgegap_url(url)
	_uploading = false
	_set_pipeline_buttons_disabled(false)
	_refresh_local_images()
	_upload_status.set_success("Image pushed. Finish creating the app version in the browser.")
	if not app_name.is_empty():
		_deploy_app_name_edit.text = app_name
		_deploy_version_edit.text = ""
		_update_deploy_buttons_enabled()
		_load_deploy_app_versions(false)

func _update_deploy_buttons_enabled() -> void:
	var busy := _deploy_phase != DeployPhase.IDLE or _exporting or _containerizing or _rebuilding or _uploading
	var can_deploy := (
		not busy
		and not _deploy_app_name_edit.text.strip_edges().is_empty()
		and not _deploy_version_edit.text.strip_edges().is_empty()
	)
	_deploy_btn.disabled = not can_deploy
	_stop_deploy_btn.disabled = busy
	_deploy_app_dropdown_btn.disabled = busy
	_deploy_version_dropdown_btn.disabled = busy or _deploy_app_name_edit.text.strip_edges().is_empty()

func _on_deploy_app_name_changed(_text: String) -> void:
	_deploy_version_edit.text = ""
	_stored_app_versions = PackedStringArray()
	_update_deploy_buttons_enabled()

func _on_deploy_app_dropdown_pressed() -> void:
	_pending_deploy_app_dropdown_open = true
	_pending_app_dropdown_open = false
	_app_api.set_authorization(SettingsScript.get_token())
	var err: Error = _app_api.get_apps()
	if err != OK:
		_pending_deploy_app_dropdown_open = false
		if _deploy_status:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("Failed to load applications. See Output.")

func _on_deploy_app_popup_id(id: int) -> void:
	var label := _deploy_app_names_popup.get_item_text(_deploy_app_names_popup.get_item_index(id))
	_deploy_app_name_edit.text = label
	_deploy_version_edit.text = ""
	_update_deploy_buttons_enabled()
	_load_deploy_app_versions(false)

func _on_deploy_version_dropdown_pressed() -> void:
	var app_name := _deploy_app_name_edit.text.strip_edges()
	if app_name.is_empty():
		if _deploy_status:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("Select an application first.")
		return
	_load_deploy_app_versions(true)

func _load_deploy_app_versions(open_popup: bool) -> void:
	_pending_deploy_version_dropdown_open = open_popup
	_app_api.set_authorization(SettingsScript.get_token())
	var err: Error = _app_api.get_app_versions(_deploy_app_name_edit.text.strip_edges())
	if err != OK:
		_pending_deploy_version_dropdown_open = false
		if _deploy_status:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("Failed to load app versions. See Output.")

func _on_get_versions_completed(ok: bool, response_code: int, versions: PackedStringArray, _body: String) -> void:
	var open_popup := _pending_deploy_version_dropdown_open
	_pending_deploy_version_dropdown_open = false
	if not ok:
		if open_popup and _deploy_status and _deploy_phase == DeployPhase.IDLE:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("Failed to list app versions (HTTP %d)." % response_code)
		return
	_stored_app_versions = versions
	_deploy_versions_popup.clear()
	var id := 0
	for version in _stored_app_versions:
		_deploy_versions_popup.add_item(version, id)
		id += 1
	if _deploy_versions_popup.item_count == 0:
		if open_popup and _deploy_status and _deploy_phase == DeployPhase.IDLE:
			_deploy_status.bind(_deploy_btn)
			_deploy_status.set_error("No active versions for this application.")
		_update_deploy_buttons_enabled()
		return
	if _deploy_version_edit.text.strip_edges().is_empty():
		_deploy_version_edit.text = _stored_app_versions[0]
	_update_deploy_buttons_enabled()
	if open_popup:
		_show_dropdown_popup(_deploy_versions_popup, _deploy_version_dropdown_btn)

func _on_deploy_version_popup_id(id: int) -> void:
	_deploy_version_edit.text = _deploy_versions_popup.get_item_text(_deploy_versions_popup.get_item_index(id))
	_update_deploy_buttons_enabled()

func _on_deploy_to_cloud() -> void:
	if _deploy_phase != DeployPhase.IDLE or _exporting or _containerizing or _rebuilding or _uploading:
		return
	var app_name := _deploy_app_name_edit.text.strip_edges()
	var version := _deploy_version_edit.text.strip_edges()
	if app_name.is_empty() or version.is_empty():
		_deploy_status.bind(_deploy_btn)
		_deploy_status.set_error("Application name and version are required.")
		return
	if not SettingsScript.is_token_verified():
		_deploy_status.bind(_deploy_btn)
		_deploy_status.set_error("Validate your Edgegap token first.")
		return

	_deploy_status.bind(_deploy_btn)
	_deploy_api.set_authorization(SettingsScript.get_token())
	_deploy_elapsed = 0.0
	_deploy_request_id = ""

	_deploy_phase = DeployPhase.IP
	_update_deploy_buttons_enabled()
	_deploy_status.set_busy("Requesting Deploy…", 10)
	var err: Error = _deploy_api.get_public_ip()
	if err != OK:
		_finish_deploy_error("Failed to look up public IP. See Output.")

func _start_create_deployment(external_ip: String) -> void:
	_deploy_phase = DeployPhase.CREATE
	_update_deploy_buttons_enabled()
	_deploy_status.bind(_deploy_btn)
	_deploy_status.set_busy("Requesting Deploy…", 25)
	var err: Error = _deploy_api.create_deployment(
		_deploy_app_name_edit.text.strip_edges(),
		_deploy_version_edit.text.strip_edges(),
		external_ip
	)
	if err != OK:
		_finish_deploy_error("Failed to create deployment. See Output.")

func _on_deploy_ip_completed(ok: bool, public_ip: String, _response_code: int, _body: String) -> void:
	if _deploy_phase != DeployPhase.IP:
		return
	if not ok or public_ip.is_empty():
		_finish_deploy_error("Couldn't retrieve your public IP.")
		return
	_start_create_deployment(public_ip)

func _on_deploy_create_completed(ok: bool, request_id: String, _response_code: int, body: String) -> void:
	if _deploy_phase != DeployPhase.CREATE:
		return
	if not ok or request_id.is_empty():
		_finish_deploy_error(_extract_api_error(body, "Failed to create deployment."))
		return
	_deploy_request_id = request_id
	SettingsScript.set_last_deployment_id(request_id)
	_deploy_status.set_busy("Deployment starting, see Dashboard for details.", 40)
	_open_edgegap_url(ConstantsScript.DEPLOY_APP_URL)
	_deploy_phase = DeployPhase.POLL_READY
	_deploy_elapsed = 0.0
	_schedule_deploy_poll()

func _schedule_deploy_poll() -> void:
	if _deploy_poll_timer:
		_deploy_poll_timer.start(ConstantsScript.DEPLOY_POLL_SECONDS)

func _on_deploy_poll_timeout() -> void:
	_deploy_elapsed += ConstantsScript.DEPLOY_POLL_SECONDS
	if _deploy_elapsed > ConstantsScript.DEPLOY_TIMEOUT_SECONDS:
		if _deploy_phase == DeployPhase.POLL_READY:
			_finish_deploy_error("Timed out waiting for deployment to become ready.")
		elif _deploy_phase == DeployPhase.POLL_STOP:
			_finish_deploy_error("Timed out waiting for deployment to stop.")
		return

	match _deploy_phase:
		DeployPhase.POLL_READY:
			_deploy_status.set_busy("Waiting for deployment READY…", minf(40.0 + _deploy_elapsed, 90.0))
			var err: Error = _deploy_api.get_deployment_status(_deploy_request_id)
			if err != OK:
				_finish_deploy_error("Failed to poll deployment status. See Output.")
		DeployPhase.POLL_STOP:
			_deploy_status.bind(_stop_deploy_btn)
			_deploy_status.set_busy("Stopping…", minf(40.0 + _deploy_elapsed, 90.0))
			var err: Error = _deploy_api.stop_deployment(_deploy_request_id)
			if err != OK:
				_finish_deploy_error("Failed to poll stop status. See Output.")
		_:
			pass

func _on_deploy_status_completed(ok: bool, status: Dictionary, _response_code: int, body: String) -> void:
	if _deploy_phase != DeployPhase.POLL_READY:
		return
	if not ok:
		_finish_deploy_error(_extract_api_error(body, "Failed to get deployment status."))
		return
	var current := str(status.get("current_status", ""))
	if current == ConstantsScript.READY_STATUS:
		_deploy_phase = DeployPhase.IDLE
		_update_deploy_buttons_enabled()
		_deploy_status.bind(_deploy_btn)
		_deploy_status.set_success(
			"Server deployed successfully. Don't forget to remove the deployment after testing."
		)
		return
	if bool(status.get("error", false)):
		_finish_deploy_error(str(status.get("error_detail", "Deployment failed.")))
		return
	_schedule_deploy_poll()

func _on_stop_last_deployment() -> void:
	if _deploy_phase != DeployPhase.IDLE or _exporting or _containerizing or _rebuilding or _uploading:
		return
	if not SettingsScript.is_token_verified():
		_deploy_status.bind(_stop_deploy_btn)
		_deploy_status.set_error("Validate your Edgegap token first.")
		return

	_deploy_status.bind(_stop_deploy_btn)
	_deploy_api.set_authorization(SettingsScript.get_token())
	_deploy_phase = DeployPhase.LIST_STOP
	_deploy_elapsed = 0.0
	_update_deploy_buttons_enabled()
	_deploy_status.set_busy("Looking up quickstart deployments…", 15)
	var err: Error = _deploy_api.list_deployments()
	if err != OK:
		_finish_deploy_error("Failed to list deployments. See Output.")

func _on_deploy_list_completed(ok: bool, deployments: Array, _response_code: int, body: String) -> void:
	if _deploy_phase != DeployPhase.LIST_STOP:
		return
	if not ok:
		_finish_deploy_error(_extract_api_error(body, "Failed to list deployments."))
		return

	var quickstart_ids: PackedStringArray = []
	for deploy in deployments:
		if typeof(deploy) != TYPE_DICTIONARY:
			continue
		if not _deployment_has_quickstart_tag(deploy):
			continue
		var request_id := str(deploy.get("request_id", "")).strip_edges()
		if not request_id.is_empty():
			quickstart_ids.append(request_id)

	if quickstart_ids.is_empty():
		_deploy_phase = DeployPhase.IDLE
		_update_deploy_buttons_enabled()
		_deploy_status.bind(_stop_deploy_btn)
		_deploy_status.set_success("No quickstart deployment found")
		return

	_deploy_request_id = quickstart_ids[0]
	_deploy_phase = DeployPhase.STOP
	_deploy_status.set_busy("Stopping…", 30)
	var err: Error = _deploy_api.stop_deployment(_deploy_request_id)
	if err != OK:
		_finish_deploy_error("Failed to stop deployment. See Output.")

func _on_deploy_stop_completed(ok: bool, response_code: int, body: String) -> void:
	if _deploy_phase == DeployPhase.STOP:
		if not ok or response_code != 200:
			_finish_deploy_error(_extract_api_error(body, "Failed to stop deployment."))
			return
		_deploy_phase = DeployPhase.POLL_STOP
		_deploy_elapsed = 0.0
		_schedule_deploy_poll()
		return

	if _deploy_phase == DeployPhase.POLL_STOP:
		if response_code == 410:
			SettingsScript.clear_last_deployment_id()
			_deploy_phase = DeployPhase.IDLE
			_update_deploy_buttons_enabled()
			_deploy_status.bind(_stop_deploy_btn)
			_deploy_status.set_success("Deployment stopped successfully")
			return
		if response_code == 200:
			_schedule_deploy_poll()
			return
		_finish_deploy_error(_extract_api_error(body, "Failed while waiting for deployment stop."))

func _deployment_has_quickstart_tag(deploy: Dictionary) -> bool:
	var tags: Variant = deploy.get("tags", [])
	if typeof(tags) != TYPE_ARRAY:
		return false
	for tag in tags:
		if str(tag) == ConstantsScript.DEFAULT_DEPLOYMENT_TAG:
			return true
	return false

func _finish_deploy_error(message: String) -> void:
	_deploy_poll_timer.stop()
	var was_stop := (
		_deploy_phase == DeployPhase.LIST_STOP
		or _deploy_phase == DeployPhase.STOP
		or _deploy_phase == DeployPhase.POLL_STOP
	)
	_deploy_phase = DeployPhase.IDLE
	_update_deploy_buttons_enabled()
	if _deploy_status:
		_deploy_status.bind(_stop_deploy_btn if was_stop else _deploy_btn)
		_deploy_status.set_error(message)
	LoggerScript.error(message)
	LoggerScript.info("See deployments on Dashboard: %s" % ConstantsScript.DEPLOY_APP_URL)

func _extract_api_error(body: String, fallback: String) -> String:
	if body.is_empty():
		return fallback
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return fallback
	for key in ["message", "error", "error_message", "detail"]:
		var value := str(parsed.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return fallback

func _on_http_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Wizard/auth owns auth HTTP responses via EdgegapWizardApi.
	pass
