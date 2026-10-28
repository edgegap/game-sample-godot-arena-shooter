extends RefCounted
class_name EdgegapExportTemplates

## Resolves Linux export templates for the *current* editor version.
## Matches Godot's VERSION_FULL_CONFIG rules (patch omitted when 0).
## Installation is delegated to Godot's built-in Export Template Manager
## so users can pick mirrors / install from file.

const EdgegapLogger = preload("logger.gd")

const LINUX_DEBUG := "linux_debug.x86_64"
const LINUX_RELEASE := "linux_release.x86_64"

func _version_info() -> Dictionary:
	return Engine.get_version_info()

## Godot version number used in release tags: "4.3" or "4.4.1".
func version_number() -> String:
	var v := _version_info()
	var major := int(v.get("major", 0))
	var minor := int(v.get("minor", 0))
	var patch := int(v.get("patch", 0))
	if patch == 0:
		return "%d.%d" % [major, minor]
	return "%d.%d.%d" % [major, minor, patch]

## Matches GODOT_VERSION_FULL_CONFIG, e.g. "4.3.stable" or "4.6.3.stable".
func version_full_config() -> String:
	var v := _version_info()
	return "%s.%s" % [version_number(), str(v.get("status", "stable"))]

func _is_dotnet_editor() -> bool:
	return OS.has_feature("mono") or OS.has_feature("dotnet")

func templates_root() -> String:
	return EditorInterface.get_editor_paths().get_data_dir().path_join("export_templates")

## Ordered folder candidates. Prefer mono when running a .NET editor.
func version_candidates() -> PackedStringArray:
	var base := version_full_config()
	var out: PackedStringArray = []
	if _is_dotnet_editor():
		out.append(base + ".mono")
	out.append(base)
	var mono := base + ".mono"
	if out.find(mono) < 0:
		out.append(mono)
	return out

func preferred_version() -> String:
	return version_candidates()[0]

func resolved_version() -> String:
	var root := templates_root()
	var fallback := preferred_version()
	for version in version_candidates():
		var dir := root.path_join(version)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		fallback = version
		if FileAccess.file_exists(dir.path_join(LINUX_DEBUG)) \
			and FileAccess.file_exists(dir.path_join(LINUX_RELEASE)):
			return version
	return fallback

func templates_dir() -> String:
	return templates_root().path_join(resolved_version())

func has_linux_debug() -> bool:
	return FileAccess.file_exists(templates_dir().path_join(LINUX_DEBUG))

func has_linux_release() -> bool:
	return FileAccess.file_exists(templates_dir().path_join(LINUX_RELEASE))

func is_installed() -> bool:
	return has_linux_debug() and has_linux_release()

func status_message() -> String:
	var v := _version_info()
	if int(v.get("major", 0)) < 4:
		return "Godot 4 or newer is required (running %s)." % str(v.get("string", "?"))
	var version := resolved_version()
	var dir := templates_dir()
	if is_installed():
		return "Linux debug & release templates found (%s)." % version
	var missing: PackedStringArray = []
	if not has_linux_debug():
		missing.append("debug")
	if not has_linux_release():
		missing.append("release")
	return "Missing Linux %s templates for %s\nLooking in: %s" % [
		" & ".join(missing), version, dir
	]

## Opens Editor > Manage Export Templates… (mirror picker + install from file).
func open_template_manager() -> bool:
	if _activate_manage_templates_menu():
		return true

	var base := EditorInterface.get_base_control()
	# Search from the editor root — ExportTemplateManager is owned by EditorNode.
	var search_root: Node = base.get_parent() if base.get_parent() else base
	var managers := search_root.find_children("*", "ExportTemplateManager", true, false)
	if managers.is_empty():
		managers = base.find_children("*", "ExportTemplateManager", true, false)
	if managers.is_empty():
		EdgegapLogger.warn(
			"Could not open Export Template Manager. Use Editor > Manage Export Templates… manually."
		)
		return false

	var manager: Object = managers[0]
	if manager.has_method("popup_manager"):
		manager.call("popup_manager")
		return true

	if manager is Window:
		(manager as Window).popup_centered_clamped(Vector2i(720, 280))
		return true

	EdgegapLogger.warn(
		"Could not open Export Template Manager. Use Editor > Manage Export Templates… manually."
	)
	return false

func _activate_manage_templates_menu() -> bool:
	var root := EditorInterface.get_base_control()
	var menus := root.find_children("*", "PopupMenu", true, false)
	for menu in menus:
		var path := str(menu.get_path())
		# Top-level Editor menu (not Project / Scene / etc.).
		if not path.ends_with("/Editor"):
			continue
		for i in menu.item_count:
			var text := str(menu.get_item_text(i))
			if text.begins_with("Manage Export Templates"):
				menu.id_pressed.emit(menu.get_item_id(i))
				return true
	return false
