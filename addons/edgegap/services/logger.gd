extends RefCounted
class_name EdgegapLogger

static func info(message: String) -> void:
	print("[Edgegap] ", message)

static func warn(message: String) -> void:
	push_warning("[Edgegap] %s" % message)

static func error(message: String) -> void:
	push_error("[Edgegap] %s" % message)
