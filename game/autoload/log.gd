extends Node
## Logs by system, only in debug builds (GDD 05 §5.7): "[System] action: detail (k=v)".

func info(system: String, msg: String) -> void:
	if OS.is_debug_build():
		print("[%s] %s" % [system, msg])
