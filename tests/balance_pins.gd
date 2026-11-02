extends RefCounted
## Mechanics tests (production cycles, the queue, wages, upkeep, demand recovery) are written with round figures: the
## ones of the GDD before the H5 rebalance (D14). They pin them here on their own catalog, so a later change of a
## [balance] figure in data/ does not break a test of a rule. The figures in data/ are checked against the GDD in
## test_core_h4_base / test_core_h5_base and measured by the bots (tools/sim_runner.gd, data/targets.json).

const DURATIONS: Dictionary = {"forge_ingot": 1.0, "forge_sword": 3.0, "forge_hammer": 2.0, "forge_armor": 5.0,
	"forge_steel": 3.0}
const RANKS: Dictionary = {"apprentice": [1, 0.5], "journeyman": [3, 1.0], "master": [6, 1.5]}  # [wage, speed]


## `cat` with the pre-H5 figures: recipe durations, wages and speeds, forge upkeep 2, demand -0.1 per unit and +0.1 per
## dawn, carry 30 kg at the start, the upgrades' gold of GDD 4.8 (a fifth of data/). Returns the same catalog.
static func classic(cat: Catalog) -> Catalog:
	for rid: String in DURATIONS:
		if cat.recipes().has(rid):
			cat.recipes()[rid]["duration_hours"] = DURATIONS[rid]
	for rk: String in RANKS:
		var r: Dictionary = cat.employees.get("ranks", {}).get(rk, {})
		if not r.is_empty():
			r["wage"] = int(RANKS[rk][0])
			r["speed"] = float(RANKS[rk][1])
	if cat.buildings().has("forge"):
		cat.buildings()["forge"]["upkeep"] = 2
	cat.market["demand"]["drop_per_unit"] = 0.1
	cat.market["demand"]["recover_per_day"] = 0.1
	if cat.starts().has("artisan_blacksmith"):
		cat.starts()["artisan_blacksmith"]["protagonist"]["carry_weight"] = 30.0
	for id: String in cat.upgrades():
		var cost: Dictionary = cat.upgrades()[id].get("cost", {})
		cost["gold"] = int(cost.get("gold", 0)) / 5
	return cat
