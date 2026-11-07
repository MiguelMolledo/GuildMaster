extends RefCounted
## Mechanics tests (production cycles, the queue, wages, upkeep, demand recovery) are written with round figures: the
## ones of the GDD before the H5 rebalance (D14). They pin them here on their own catalog, so a later change of a
## [balance] figure in data/ does not break a test of a rule. The figures in data/ are checked against the GDD in
## test_core_h4_base / test_core_h5_base and measured by the bots (tools/sim_runner.gd, data/targets.json).

const DURATIONS: Dictionary = {"forge_ingot": 1.0, "forge_sword": 3.0, "forge_hammer": 2.0, "forge_armor": 5.0,
	"forge_steel": 3.0}
const RANKS: Dictionary = {"apprentice": [1, 0.5], "journeyman": [3, 1.0], "master": [6, 1.5]}  # [wage, speed]


## `cat` with the pre-H5 figures: recipe durations, wages and speeds, forge upkeep 2, demand -0.1 per unit and +0.1 per
## dawn, carry 30 kg at the start, the upgrades' gold of GDD 4.8 (a fifth of data/) and works that close the building
## (before Equilibrio 9). Returns the same catalog.
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
	# the works of 4.8 before Equilibrio 9: every works closes the building (tests/test_equilibrio_works.gd: the new rule)
	cat.upgrade_rules["works"] = {"small_max_days": 1.0, "small_mode": "closed", "big_mode": "closed", "big_speed": 0.5}
	# and no houses' wages nor food (Equilibrio 15): the tests of the employees' flows count only theirs
	if cat.town.get("households") is Dictionary:
		cat.town["households"]["enabled"] = false
	# nor the first days' upkeep ramp, the sword at 68 nor the free errand of the resources stall (equilibrio,
	# 2026-11-07: the default game played as the tutorial teaches): the tests of upkeep, contracts and errands keep theirs
	cat.accounts["upkeep_ramp"] = []
	if cat.items().has("sword"):
		cat.items()["sword"]["base_price"] = 65
	(cat.market.get("stalls", {}).get("resources", {}) as Dictionary).erase("errand_surcharge")
	return cat


## Only the market's figures of the rule tests of selling and contracts: the sword at 65 (data/: 68 since the
## equilibrio of 2026-11-07) and the errand's surcharge at every stall. Returns the same catalog.
static func prices(cat: Catalog) -> Catalog:
	if cat.items().has("sword"):
		cat.items()["sword"]["base_price"] = 65
	(cat.market.get("stalls", {}).get("resources", {}) as Dictionary).erase("errand_surcharge")
	return cat


## Without the first days' upkeep ramp (data/accounts.json upkeep_ramp, equilibrio 2026-11-07): the tests that count a
## whole day's upkeep from the first dawn. Returns the same catalog.
static func no_ramp(cat: Catalog) -> Catalog:
	cat.accounts["upkeep_ramp"] = []
	return cat


## `cat` without sleep and food for the controlled characters (GDD 4.2.6): the H14 rule (a controlled one without a
## programmable routine moves no needs, no Rutina). For the tests of other rules that play the founder for days with
## manual orders (cycles, the queue, the shops' hours); the needs have their own tests (test_family_sleep_food).
## Returns the same catalog.
static func no_player_needs(cat: Catalog) -> Catalog:
	cat.family["needs"]["controlled"] = false
	return cat
