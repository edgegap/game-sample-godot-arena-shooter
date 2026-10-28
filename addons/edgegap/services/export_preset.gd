extends RefCounted
class_name EdgegapExportPreset

const EdgegapConstants = preload("../constants.gd")
const EdgegapLogger = preload("logger.gd")

const PRESETS_RES_PATH := "res://export_presets.cfg"
const CREDENTIALS_RES_PATH := "res://.godot/export_credentials.cfg"
const CREDENTIALS_BACKUP_RES_PATH := "res://.godot/export_credentials.edgegap.bak"

func presets_path() -> String:
	return PRESETS_RES_PATH

func find_preset_section() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS_RES_PATH) != OK:
		return ""
	return _find_preset_section_in(cfg)

func _find_preset_section_in(cfg: ConfigFile) -> String:
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue
		if section.ends_with(".options"):
			continue
		if str(cfg.get_value(section, "name", "")) == EdgegapConstants.PRESET_NAME:
			return section
	return ""

func has_preset() -> bool:
	return not find_preset_section().is_empty()

func get_export_path() -> String:
	var section := find_preset_section()
	if section.is_empty():
		return EdgegapConstants.DEFAULT_EXPORT_PATH
	var cfg := ConfigFile.new()
	cfg.load(PRESETS_RES_PATH)
	return str(cfg.get_value(section, "export_path", EdgegapConstants.DEFAULT_EXPORT_PATH))

func get_server_build_arg() -> String:
	var path := get_export_path().replace("\\", "/")
	if path.ends_with(".x86_64"):
		path = path.substr(0, path.length() - ".x86_64".length())
	elif path.ends_with(".exe"):
		path = path.get_basename()
	return path

## The preset may exist on disk while the editor still holds a stale in-memory
## list, so a reload is attempted even when nothing new is written.
func ensure_preset() -> Error:
	if has_preset():
		EdgegapLogger.info("Using existing export preset '%s' (left as-is)." % EdgegapConstants.PRESET_NAME)
	else:
		var err := create_default_preset()
		if err != OK:
			return err
	_reload_editor_export_from_disk()
	return OK

func create_default_preset() -> Error:
	_stop_editor_export_save_timer()

	var cfg := ConfigFile.new()
	if FileAccess.file_exists(PRESETS_RES_PATH):
		var load_err := cfg.load(PRESETS_RES_PATH)
		if load_err != OK:
			EdgegapLogger.error("Failed to load export_presets.cfg: %s" % error_string(load_err))
			return load_err

	var index := _next_preset_index(cfg)
	var section := "preset.%d" % index
	var options := "preset.%d.options" % index

	cfg.set_value(section, "name", EdgegapConstants.PRESET_NAME)
	cfg.set_value(section, "platform", "Linux")
	cfg.set_value(section, "runnable", false)
	cfg.set_value(section, "dedicated_server", true)
	cfg.set_value(section, "custom_features", "")
	cfg.set_value(section, "export_filter", "customized")
	cfg.set_value(section, "customized_files", { "res://": "strip" })
	cfg.set_value(section, "include_filter", "")
	cfg.set_value(section, "exclude_filter", "")
	cfg.set_value(section, "export_path", EdgegapConstants.DEFAULT_EXPORT_PATH)
	cfg.set_value(section, "patches", PackedStringArray())
	cfg.set_value(section, "patch_delta_encoding", false)
	cfg.set_value(section, "patch_delta_compression_level_zstd", 19)
	cfg.set_value(section, "patch_delta_min_reduction", 0.1)
	cfg.set_value(section, "patch_delta_include_filters", "*")
	cfg.set_value(section, "patch_delta_exclude_filters", "")
	cfg.set_value(section, "encryption_include_filters", "")
	cfg.set_value(section, "encryption_exclude_filters", "")
	cfg.set_value(section, "seed", 0)
	cfg.set_value(section, "encrypt_pck", false)
	cfg.set_value(section, "encrypt_directory", false)
	cfg.set_value(section, "script_export_mode", 2)

	cfg.set_value(options, "custom_template/debug", "")
	cfg.set_value(options, "custom_template/release", "")
	cfg.set_value(options, "debug/export_console_wrapper", 2)
	cfg.set_value(options, "binary_format/embed_pck", false)
	cfg.set_value(options, "texture_format/s3tc_bptc", true)
	cfg.set_value(options, "texture_format/etc2_astc", false)
	cfg.set_value(options, "shader_baker/enabled", false)
	cfg.set_value(options, "binary_format/architecture", "x86_64")
	cfg.set_value(options, "ssh_remote_deploy/enabled", false)
	cfg.set_value(options, "ssh_remote_deploy/host", "user@host_ip")
	cfg.set_value(options, "ssh_remote_deploy/port", "22")
	cfg.set_value(options, "ssh_remote_deploy/extra_args_ssh", "")
	cfg.set_value(options, "ssh_remote_deploy/extra_args_scp", "")
	cfg.set_value(options, "dotnet/include_scripts_content", false)
	cfg.set_value(options, "dotnet/include_debug_symbols", true)
	cfg.set_value(options, "dotnet/embed_build_outputs", false)
	cfg.set_value(options, "texture_format/bptc", true)
	cfg.set_value(options, "texture_format/s3tc", true)
	cfg.set_value(options, "texture_format/etc", false)
	cfg.set_value(options, "texture_format/etc2", false)

	var save_err := cfg.save(PRESETS_RES_PATH)
	if save_err != OK:
		EdgegapLogger.error("Failed to save export_presets.cfg: %s" % error_string(save_err))
		return save_err

	EdgegapLogger.info(
		"Created export preset '%s' -> %s" % [
			EdgegapConstants.PRESET_NAME, EdgegapConstants.DEFAULT_EXPORT_PATH
		]
	)
	return OK

func _next_preset_index(cfg: ConfigFile) -> int:
	var max_index := -1
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue
		if section.ends_with(".options"):
			continue
		var parts := section.split(".")
		if parts.size() == 2 and parts[1].is_valid_int():
			max_index = maxi(max_index, int(parts[1]))
	return max_index + 1

func open_export_dialog() -> void:
	var err := ensure_preset()
	if err != OK:
		EdgegapLogger.error("Could not ensure Edgegap export preset.")
		return

	# Prefer Project > Export… so ProjectExportDialog.popup_export() refreshes the list.
	if _activate_project_export_menu():
		return

	var base := EditorInterface.get_base_control()
	var dialogs := base.find_children("*", "ProjectExportDialog", true, false)
	if dialogs.is_empty():
		EdgegapLogger.warn("Could not find Project Export dialog. Open Project > Export… manually.")
		return
	var dialog := dialogs[0] as Window
	if dialog:
		dialog.popup_centered_clamped(Vector2i(900, 600))

func _activate_project_export_menu() -> bool:
	var root := EditorInterface.get_base_control()
	var menus := root.find_children("*", "PopupMenu", true, false)
	for menu in menus:
		var path := str(menu.get_path())
		if not path.ends_with("/Project"):
			continue
		for i in menu.item_count:
			var text := str(menu.get_item_text(i))
			# Godot may use "..." or a unicode ellipsis.
			if text.begins_with("Export") and not text.begins_with("Export As"):
				menu.id_pressed.emit(menu.get_item_id(i))
				return true
	return false

## EditorExport keeps presets in memory and can overwrite disk on a delayed save,
## so it has to re-read export_presets.cfg after a preset is written.
func _reload_editor_export_from_disk() -> void:
	_stop_editor_export_save_timer()
	if _reload_via_temp_platform():
		return
	_reload_via_tree_notification()

## Godot 4.4+: adding/removing a platform sets should_reload_presets, which
## clears the in-memory presets and reloads them from disk on the next frame.
func _reload_via_temp_platform() -> bool:
	if not ClassDB.class_exists("EditorExportPlatformExtension"):
		return false

	var plugin := _find_any_editor_plugin()
	if plugin == null or not plugin.has_method("add_export_platform"):
		return false

	var temp = ClassDB.instantiate("EditorExportPlatformExtension")
	if temp == null:
		return false

	plugin.add_export_platform(temp)
	_notify_editor_export_process()
	plugin.remove_export_platform(temp)
	_notify_editor_export_process()
	_stop_editor_export_save_timer()
	return true

## Godot 4.3: no reload hook exists, and load_config() appends instead of
## replacing. NOTIFICATION_ENTER_TREE re-runs it against a file temporarily
## reduced to the Edgegap preset alone, so only that preset gets appended.
func _reload_via_tree_notification() -> void:
	var ee := _find_editor_export()
	if ee == null:
		EdgegapLogger.warn("Could not reload editor export presets (EditorExport not found).")
		return

	var original := FileAccess.get_file_as_string(PRESETS_RES_PATH)
	var stored := ConfigFile.new()
	if original.is_empty() or stored.parse(original) != OK:
		EdgegapLogger.warn("Could not read export_presets.cfg; restart the editor to see the preset.")
		return

	var section := _find_preset_section_in(stored)
	if section.is_empty():
		return

	# Flushing the editor's presets to disk is the only way to read its in-memory
	# list from GDScript. Whatever is missing from that dump would be overwritten
	# by the editor's next save anyway.
	if not _flush_editor_export_to_disk(ee):
		_restore_presets_file(original)
		EdgegapLogger.warn("Could not refresh export presets; restart the editor to see the preset.")
		return

	var live := ConfigFile.new()
	live.load(PRESETS_RES_PATH)
	if not _find_preset_section_in(live).is_empty():
		return

	var isolated := ConfigFile.new()
	_copy_preset_section(stored, section, isolated, "preset.0")
	if isolated.save(PRESETS_RES_PATH) != OK:
		_restore_presets_file(original)
		EdgegapLogger.warn("Could not refresh export presets; restart the editor to see the preset.")
		return

	# Credentials are matched by preset index, so hide them while our preset sits at index 0.
	var credentials_moved := FileAccess.file_exists(CREDENTIALS_RES_PATH) \
		and DirAccess.rename_absolute(CREDENTIALS_RES_PATH, CREDENTIALS_BACKUP_RES_PATH) == OK

	# Disable processing first so re-entering the tree does not register the node twice.
	var was_processing := ee.is_processing()
	ee.set_process(false)
	ee.notification(Node.NOTIFICATION_ENTER_TREE)
	ee.set_process(was_processing)

	if credentials_moved:
		DirAccess.rename_absolute(CREDENTIALS_BACKUP_RES_PATH, CREDENTIALS_RES_PATH)

	# Disk must now mirror the editor: everything it held, plus the appended preset.
	_copy_preset_section(stored, section, live, "preset.%d" % _next_preset_index(live))
	if live.save(PRESETS_RES_PATH) != OK:
		_restore_presets_file(original)
	_notify_editor_export_process()
	_stop_editor_export_save_timer()

func _copy_preset_section(src: ConfigFile, src_section: String, dst: ConfigFile, dst_section: String) -> void:
	for key in src.get_section_keys(src_section):
		dst.set_value(dst_section, key, src.get_value(src_section, key))
	var options := src_section + ".options"
	if not src.has_section(options):
		return
	for key in src.get_section_keys(options):
		dst.set_value(dst_section + ".options", key, src.get_value(options, key))

## EditorExport::_save() is only reachable through its save timer's timeout.
func _flush_editor_export_to_disk(ee: Node) -> bool:
	var timer := _editor_export_save_timer(ee)
	if timer == null:
		return false
	timer.stop()
	timer.emit_signal("timeout")
	return true

func _restore_presets_file(contents: String) -> void:
	var file := FileAccess.open(PRESETS_RES_PATH, FileAccess.WRITE)
	if file == null:
		EdgegapLogger.error("Failed to restore export_presets.cfg: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(contents)
	file.close()

func _find_any_editor_plugin() -> EditorPlugin:
	var root := EditorInterface.get_base_control().get_tree().root
	var plugins := root.find_children("*", "EditorPlugin", true, false)
	if plugins.is_empty():
		return null
	return plugins[0] as EditorPlugin

func _find_editor_export() -> Node:
	var root := EditorInterface.get_base_control().get_tree().root
	var found := root.find_children("*", "EditorExport", true, false)
	if found.is_empty():
		return null
	return found[0] as Node

func _editor_export_save_timer(ee: Node) -> Timer:
	for child in ee.get_children():
		if child is Timer:
			return child as Timer
	return null

func _stop_editor_export_save_timer() -> void:
	var ee := _find_editor_export()
	if ee == null:
		return
	var timer := _editor_export_save_timer(ee)
	if timer:
		timer.stop()

func _notify_editor_export_process() -> void:
	var ee := _find_editor_export()
	if ee:
		ee.notification(Node.NOTIFICATION_PROCESS)
