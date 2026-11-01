class_name NewGame
extends RefCounted
## Starting a game: a fresh state, or a scenario (a saved game in data/scenarios/<id>.json) loaded as is.
## The opening of a real game (starting gold, forge, debt, first goal) arrives with H3 (GDD 04, start conditions).

const SCENARIOS_DIR: String = "res://data/scenarios"


static func fresh(catalog: Catalog, world_seed: int) -> WorldState:
	var s := WorldState.new()
	s.seed_rng(world_seed)
	s.clock["minute"] = int(catalog.time.get("start_minute", 0))
	s.meta = {"title": "new_game"}
	return s


## {"ok": true, "state": WorldState} or {"ok": false, "error": ...}; `world_seed` >= 0 replaces the scenario's seed.
static func from_scenario(id: String, world_seed: int = -1) -> Dictionary:
	var r := SaveFile.load_file(SCENARIOS_DIR.path_join(id + ".json"))
	if r["ok"] and world_seed >= 0:
		(r["state"] as WorldState).seed_rng(world_seed)
	return r


static func scenario_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(SCENARIOS_DIR):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f.get_basename())
	out.sort()
	return out
