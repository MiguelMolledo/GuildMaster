extends SceneTree
## Test starts on the towns made by the town builder (tools/city/ciudad.py generar, docs/protocolos/generar-ciudad.md):
## for each map of data/maps with "generated", a real new game of the start artisan_blacksmith (normal, seed 1) with
## the start's map swapped for that one in the loaded catalog only (data/starts/ is not touched: the player's starts
## stay on town_e), saved as data/scenarios/<map>_start.json.
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_city_scenarios.gd [-- --maps=a,b]
## Same code + same data = same files. Re-run after regenerating a town or changing the start.

const OUT: String = "res://data/scenarios"
const START: String = "artisan_blacksmith"


func _init() -> void:
	var cat := Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_city_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			only = a.substr(7).split(",", false)
	var ids: Array = cat.maps().keys()
	ids.sort()
	var ok := true
	var n := 0
	for id: String in ids:
		if not (cat.maps()[id] as Dictionary).has("generated") or (not only.is_empty() and not id in only):
			continue
		ok = _make(cat, str(id)) and ok
		n += 1
	print("make_city_scenarios: %d escenarios" % n)
	quit(0 if ok else 1)


func _make(cat: Catalog, map_id: String) -> bool:
	var start: Dictionary = cat.starts()[START]
	var before := str(start["map"])
	start["map"] = map_id  # this run only: the catalog in memory, not data/starts/
	var r := NewGame.from_start(cat, START, "normal", {}, 1)
	start["map"] = before
	if not r["ok"]:
		print("make_city_scenarios: %s: %s" % [map_id, r["error"]])
		return false
	var st: WorldState = r["state"]
	var gen: Dictionary = cat.maps()[map_id]["generated"]
	st.meta = {"title": "%s_start" % map_id, "start": START, "origin": "tools/scenarios/make_city_scenarios.gd",
		"description": "Partida nueva de %s (normal, semilla 1) en la ciudad generada %s (trazado %s, semilla %s)." % [
			START, map_id, gen.get("layout", "?"), gen.get("seed", "?")]}
	var path := OUT.path_join(map_id + "_start.json")
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), path)
	print("make_city_scenarios: %s (%s): %d personajes, %d edificios, %d familias" % [path, error_string(e),
		st.characters.size(), st.buildings.size(), st.families.size()])
	return e == OK
