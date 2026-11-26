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


## The town's view (docs/3d/plan.md §3): --view=2d|3d, else "2d" for the gallery and the capture scripts that are not
## 3D ones (`smoke_3d`; `script_id` "" = none), else data/view.json view_mode. A flow (--flow=<id>, script "flow")
## plays in the view its data/flows/<id>.json names ("view": "3d"; without it, the 2D: not ported yet).
static func view_mode(args: PackedStringArray, script_id: String, smoke_3d: Array) -> String:
	for a: String in args:
		if a.begins_with("--view="):
			return "3d" if a.substr(7) == "3d" else "2d"
	if script_id == "flow":
		for a: String in args:
			if a.begins_with("--flow="):
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/flows/%s.json" % a.substr(7)))
				return "3d" if d is Dictionary and str((d as Dictionary).get("view", "2d")) == "3d" else "2d"
		return "2d"
	if args.has("--gallery") or (script_id != "" and not smoke_3d.has(script_id)):
		return "2d"
	return "3d" if str(value("view_mode", "2d")) == "3d" else "2d"
