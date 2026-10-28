extends RefCounted
class_name EdgegapHeadlessExport

const EdgegapLogger = preload("logger.gd")

var _pid: int = -1
var _abs_export := ""

func godot_executable() -> String:
	return OS.get_executable_path()

func is_running() -> bool:
	return _pid >= 0 and OS.is_process_running(_pid)

func export_output_path() -> String:
	return _abs_export

## Starts a non-blocking headless export. Poll with is_running() / take_exit_code().
func start_export_debug(preset_name: String, export_path: String) -> Error:
	if is_running():
		return ERR_BUSY

	var project_path := ProjectSettings.globalize_path("res://")
	_abs_export = export_path
	if not _abs_export.is_absolute_path():
		_abs_export = project_path.path_join(export_path)
	_abs_export = _abs_export.replace("\\", "/")

	DirAccess.make_dir_recursive_absolute(_abs_export.get_base_dir())

	var args := PackedStringArray([
		"--headless",
		"--path", project_path,
		"--export-debug", preset_name,
		_abs_export,
	])

	EdgegapLogger.info("Headless export starting: %s %s" % [godot_executable(), " ".join(args)])
	_pid = OS.create_process(godot_executable(), args, false)
	if _pid < 0:
		EdgegapLogger.error("Failed to start headless export process.")
		_pid = -1
		return ERR_CANT_CREATE

	EdgegapLogger.info("Export process pid=%d" % _pid)
	return OK

## Returns -1 while still running, otherwise the process exit code (and clears pid).
func take_exit_code() -> int:
	if _pid < 0:
		return FAILED
	if OS.is_process_running(_pid):
		return -1
	var code := OS.get_process_exit_code(_pid)
	_pid = -1
	return code
