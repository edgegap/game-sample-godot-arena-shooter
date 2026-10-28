@tool
extends EditorPlugin

var _panel: ScrollContainer

func _enter_tree() -> void:
	var panel_path := (get_script() as Script).resource_path.get_base_dir().path_join("ui/edgegap_panel.gd")
	# REPLACE_DEEP avoids keeping a previously failed parse cached in ResourceLoader.
	var panel_script := ResourceLoader.load(
		panel_path,
		"GDScript",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as GDScript
	if panel_script == null:
		push_error("Edgegap: failed to load %s" % panel_path)
		return

	var reload_err := panel_script.reload()
	if reload_err != OK:
		push_error(
			"Edgegap: panel script reload failed (%s). Open %s and check Output for parse errors." % [
				error_string(reload_err), panel_path
			]
		)
		return
	if not panel_script.can_instantiate():
		push_error(
			"Edgegap: panel script cannot be instantiated. Open %s and check Output for parse errors." % panel_path
		)
		return

	_panel = panel_script.new() as ScrollContainer
	_panel.name = "Edgegap"
	_panel.custom_minimum_size = Vector2(160, 0)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _panel)

	add_tool_menu_item("Edgegap…", _focus_dock)

func _exit_tree() -> void:
	remove_tool_menu_item("Edgegap…")
	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null

func _focus_dock() -> void:
	if _panel == null:
		return
	var parent := _panel.get_parent()
	if parent is TabContainer:
		var tabs := parent as TabContainer
		var idx := tabs.get_tab_idx_from_control(_panel)
		if idx >= 0:
			tabs.current_tab = idx
