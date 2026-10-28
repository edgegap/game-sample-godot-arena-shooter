extends RefCounted
class_name EdgegapProcess

const EdgegapLogger = preload("logger.gd")

signal output_line(line: String)
signal finished(exit_code: int)

func run(command: String, args: PackedStringArray, _working_dir: String = "") -> int:
	EdgegapLogger.info("Running: %s %s" % [command, " ".join(args)])
	var output: Array = []
	var exit_code := OS.execute(command, args, output, true, false)
	for line in output:
		var text := str(line).rstrip("\r")
		if text.is_empty():
			continue
		EdgegapLogger.info(text)
		output_line.emit(text)
	finished.emit(exit_code)
	return exit_code
