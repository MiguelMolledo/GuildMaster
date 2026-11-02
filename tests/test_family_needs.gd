extends "res://tests/test_case.gd"
## H14 needs and morale (GDD 4.2.6; docs/contratos/h14_ia_familiar.md): they change by the hour with what the family
## member does, events raise social, morale is their mean and slows the work down below full_at, notices.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String) -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func _wife(sim: Sim) -> String:
	return str(sim.state.characters[HERO]["spouse"])


func test_needs_change_by_the_hour() -> void:
	var sim := _sim("kin_trader")
	var st := sim.state
	st.characters[HERO]["location"] = FORGE
	check(not Needs.tracked(sim, HERO), "Hugo without a routine (only manual orders): his needs stay still")
	st.characters[HERO]["schedule"] = {"dawn": {"action": "rest"}, "day": {"action": "rest"}, "dusk": {"action": "rest"},
		"night": {"action": "rest"}}
	check(Needs.tracked(sim, HERO), "with a routine they move")
	var n0: Dictionary = Needs.of(sim, HERO).duplicate()
	eq(Needs.situation(sim, HERO), "home", "Hugo idle in the forge (his home)")
	sim.run_minutes(60)
	var n1: Dictionary = Needs.of(sim, HERO)
	eq(int(n1["hunger"]), mini(100, int(n0["hunger"]) + 12), "at home: +12 hunger an hour")
	eq(int(n1["fun"]), int(n0["fun"]) - 1, "fun drops 1 an hour")
	check(not Needs.tracked(sim, "chr_0002"), "the rival smith has no needs (only the human family)")
	var c: String = Population.townsfolk(st)[0]
	check(not Needs.tracked(sim, c), "nor the townsfolk")


func test_morale_and_productivity() -> void:
	var sim := _sim("kin_trader")
	var st := sim.state
	st.characters[HERO]["needs"] = {"hunger": 80, "rest": 80, "social": 80, "fun": 80}
	eq(Needs.morale(sim, HERO), 80, "the mean")
	near(Needs.productivity(sim, HERO), 1.0, 0.0001, "full speed")
	st.characters[HERO]["needs"] = {"hunger": 0, "rest": 0, "social": 0, "fun": 0}
	near(Needs.productivity(sim, HERO), 0.8, 0.0001, "morale 0: x0.8")
	st.characters[HERO]["needs"] = {"hunger": 20, "rest": 20, "social": 20, "fun": 20}
	near(Needs.productivity(sim, HERO), 0.9, 0.0001, "morale 20: halfway to full_at 40")
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	Inventory.add(inv, cat, "iron", 0, 4)
	Inventory.add(inv, cat, "coal", 0, 4)
	st.characters[HERO]["location"] = FORGE
	st.characters[HERO]["schedule"] = Schedules.default_schedule(sim, HERO)
	var r := Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"})
	check(r["ok"], "works (%s)" % r["reason"])
	var job: Dictionary = st.buildings[FORGE]["zones"]["furnace"]["job"]
	var full := Production.owner_cycle_minutes(sim, FORGE, cat.recipes()["forge_ingot"], "normal")
	eq(int(job["end"]) - int(job["start"]), roundi(float(full) / 0.9), "a slower cycle with morale 20")


func test_events_raise_social() -> void:
	var sim := _sim("kin_trader")
	sim.state.characters[HERO]["schedule"] = Schedules.default_schedule(sim, HERO)
	var s0 := int(Needs.of(sim, HERO)["social"])
	sim.events = [{"type": "npc_action", "actor": HERO, "target": "chr_0005", "action": "talk", "ok": true}]
	Needs.step(sim)
	eq(int(Needs.of(sim, HERO)["social"]), s0 + 10, "talking: +10 social")


func test_notices() -> void:
	var sim := _sim("kin_tired")
	var keys: Array = []
	for i: int in 70:
		sim.step([])
	for n: Dictionary in sim.state.notices:
		keys.append(str(n.get("key", "")))
	check("notice.kin_exhausted" in keys or "notice.kin_low_morale" in keys, "a tired spouse: a notice (%s)" % [keys])
	var count := keys.filter(func(k: String) -> bool: return k == "notice.kin_exhausted").size()
	check(count <= 1, "once a day")
