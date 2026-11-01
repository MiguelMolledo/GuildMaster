class_name NewGame
extends RefCounted
## Starting a game: a fresh state, or a scenario (a saved game in data/scenarios/<id>.json) loaded as is.
## A real game starts from a start (data/starts/<id>.json, GDD 4.16): from_start (subgrim «cuentas», H3).

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


## A new game from a start (GDD 4.16): the map and its public buildings, the protagonist (choices: name, female,
## free points, colours), the family purse, the forge with its stock, the debt by `difficulty`, the rival family,
## the scripted contracts and the objective chain. {"ok": true, "state": WorldState} or {"ok": false, "error": ...}.
## Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
static func from_start(_catalog: Catalog, _start_id: String, _difficulty: String, _choices: Dictionary,
		_world_seed: int) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}


static func scenario_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(SCENARIOS_DIR):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f.get_basename())
	out.sort()
	return out
