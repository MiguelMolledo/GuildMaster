class_name ViewConfig
extends RefCounted
## Presentation figures of the world view, from data/view.json (zoom levels, greybox block heights, day/night
## colours...). Only game/ reads them: they never change a rule. Loaded once and cached.

const PATH: String = "res://data/view.json"

static var _cfg: Dictionary = {}


static func get_all() -> Dictionary:
	if _cfg.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not json.data is Dictionary:
			push_error("view config: cannot read %s" % PATH)
			return {}
		_cfg = json.data
	return _cfg


static func value(key: String, default: Variant = null) -> Variant:
	return get_all().get(key, default)


static func color(hex: String) -> Color:
	return Color.from_string(hex, Color.MAGENTA)


## Game minutes a walker takes per tile (interpolation of D3): the sim's own figure (data/time.json).
static func minutes_per_tile(catalog: Catalog) -> int:
	return Movement.minutes_per_tile(catalog)


## Log line of the views, debug builds only, same format as the Log autoload ("[System] action: detail"). Views use
## this one so they also run in the windowless tests, where the autoloads do not exist yet.
static func info(system: String, msg: String) -> void:
	if OS.is_debug_build():
		print("[%s] %s" % [system, msg])
