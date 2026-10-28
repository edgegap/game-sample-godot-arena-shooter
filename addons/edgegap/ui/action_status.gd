@tool
extends VBoxContainer

## Progress under the action; OK/error replaces the bound button's left icon.

const OK_COLOR := Color(0.2, 0.82, 0.38)
const ERR_COLOR := Color(0.95, 0.28, 0.28)

var progress: ProgressBar
var _button: Button
var _base_tooltips := {}
var _base_icons := {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 0
	progress.visible = false
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.custom_minimum_size = Vector2(0, 16)
	add_child(progress)

func bind(button: Button) -> void:
	_button = button
	if _button == null:
		return
	if not _base_tooltips.has(_button):
		_base_tooltips[_button] = _button.tooltip_text
		_base_icons[_button] = _button.icon

func clear() -> void:
	progress.visible = false
	progress.value = 0
	_restore_button()

func clear_all() -> void:
	progress.visible = false
	progress.value = 0
	for btn in _base_icons.keys():
		_button = btn
		_restore_button()
	_button = null

func set_busy(_message: String = "", pct: float = 10.0) -> void:
	_restore_button()
	progress.visible = true
	progress.value = clampf(pct, 0.0, 100.0)
	if _button and not _message.is_empty():
		_button.tooltip_text = _message

func set_progress(pct: float, message: String = "") -> void:
	progress.visible = true
	progress.value = clampf(pct, 0.0, 100.0)
	if _button and not message.is_empty():
		_button.tooltip_text = message

func set_success(message: String = "") -> void:
	progress.visible = false
	progress.value = 100
	_apply_result(OK_COLOR, true, message)

func set_error(message: String = "") -> void:
	progress.visible = false
	_apply_result(ERR_COLOR, false, message)

func _apply_result(color: Color, ok: bool, message: String) -> void:
	if _button == null:
		return
	_button.icon = _make_icon(color, ok)
	_button.expand_icon = false
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.add_theme_constant_override("icon_max_width", 16)
	_button.add_theme_color_override("icon_normal_color", color)
	_button.add_theme_color_override("icon_hover_color", color)
	_button.add_theme_color_override("icon_pressed_color", color)
	_button.add_theme_color_override("icon_disabled_color", color)
	if not message.is_empty():
		_button.tooltip_text = message

func _restore_button() -> void:
	if _button == null:
		return
	_button.icon = _base_icons.get(_button, null)
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.tooltip_text = str(_base_tooltips.get(_button, ""))
	_button.remove_theme_color_override("icon_normal_color")
	_button.remove_theme_color_override("icon_hover_color")
	_button.remove_theme_color_override("icon_pressed_color")
	_button.remove_theme_color_override("icon_disabled_color")

func _make_icon(color: Color, ok: bool) -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if ok:
		for i in 5:
			img.set_pixel(3 + i, 8 + i, color)
			img.set_pixel(3 + i, 9 + i, color)
			img.set_pixel(4 + i, 8 + i, color)
		for i in 8:
			img.set_pixel(6 + i, 12 - i, color)
			img.set_pixel(6 + i, 11 - i, color)
			img.set_pixel(7 + i, 12 - i, color)
	else:
		for i in 10:
			img.set_pixel(3 + i, 3 + i, color)
			img.set_pixel(4 + i, 3 + i, color)
			img.set_pixel(3 + i, 12 - i, color)
			img.set_pixel(4 + i, 12 - i, color)
	return ImageTexture.create_from_image(img)
