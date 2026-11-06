extends "res://tests/test_case.gd"
## Equilibrio 6 (GDD 4.12.5.1): the misdeeds of the AI families. At dawn, keyed rolls (state.rng untouched), only AI
## families with a business, the less honest the more often; a seen one is a public fact the player can accuse with.

const FAM := "fam_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim(c: Catalog = null) -> Sim:
	var cc := c if c != null else cat
	return Sim.new(NewGame.from_start(cc, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cc)


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _dawn(sim: Sim, day: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 300
	sim.events = [{"type": "phase_changed", "phase": "dawn"}]


func test_the_chance_follows_honesty() -> void:
	var sim := _sim()
	var c := Misdeeds.cfg(sim)
	var ai := ""
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) == "rival_smith":
			ai = f
	check(ai != "", "there is a rival smith")
	sim.state.families[ai]["attitudes"]["honesty"] = int(c["pivot"])
	eq(snappedf(Misdeeds.chance(sim, ai), 0.0001), snappedf(float(c["base"]), 0.0001), "honesty at the pivot: base")
	sim.state.families[ai]["attitudes"]["honesty"] = int(c["pivot"]) - int(c["scale"])
	eq(snappedf(Misdeeds.chance(sim, ai), 0.0001), snappedf(minf(2.0 * float(c["base"]), float(c["max"])), 0.0001),
		"one scale less honest: twice")
	sim.state.families[ai]["attitudes"]["honesty"] = 100
	eq(Misdeeds.chance(sim, ai), 0.0, "very honest: never")


func test_a_seen_misdeed_is_a_public_fact_only_for_ai_families() -> void:
	var c := Catalog.load_from()
	c.justice["misdeeds"]["base"] = 10.0
	c.justice["misdeeds"]["max"] = 1.0
	c.justice["misdeeds"]["seen"] = 1.0
	var sim := _sim(c)
	var rng_before := sim.state.rng.state
	_dawn(sim, 2)
	Misdeeds.step(sim)
	var ev := _of(sim.events, "misdeed")
	check(not ev.is_empty(), "every AI family with a business does one")
	check(ev.all(func(e: Dictionary) -> bool: return str(e["family"]) != FAM), "never the human family")
	check(ev.all(func(e: Dictionary) -> bool: return bool(e["seen"]) and str(e["fact"]) != ""), "seen: a fact each")
	var f: Dictionary = ev[0]
	eq(Tribunal.facts_against(sim, str(f["family"])).size(), 1, "a public fact against it, not tried")
	eq(sim.state.rng.state, rng_before, "no draw from state.rng")
	check(_of(sim.events, "notice_added").any(func(e: Dictionary) -> bool:
		return str(e.get("family", "")) == FAM and str(e.get("key", "")) == "notice.misdeed_seen"), "the player is told")
	var target := Kin.head(sim.state, str(f["family"]))
	sim.state.families[FAM]["title"] = "citizen"
	eq(Tribunal.accuse_status(sim, HUGO, target, str(f["fact"]), "", false), "", "a citizen can accuse with it")


func test_only_at_dawn_and_the_same_days_each_time() -> void:
	var c := Catalog.load_from()
	c.justice["misdeeds"]["base"] = 10.0
	c.justice["misdeeds"]["max"] = 1.0
	var sim := _sim(c)
	sim.events = []
	Misdeeds.step(sim)
	eq(_of(sim.events, "misdeed").size(), 0, "not without the dawn")
	_dawn(sim, 3)
	Misdeeds.step(sim)
	var a := _of(sim.events, "misdeed").map(func(e: Dictionary) -> String: return "%s|%s|%s" % [e["family"], e["kind"], e["seen"]])
	var sim2 := _sim(c)
	_dawn(sim2, 3)
	Misdeeds.step(sim2)
	var b := _of(sim2.events, "misdeed").map(func(e: Dictionary) -> String: return "%s|%s|%s" % [e["family"], e["kind"], e["seen"]])
	eq(a, b, "keyed rolls: the same misdeeds the same day")


func test_contraband_only_below_its_honesty() -> void:
	var c := Catalog.load_from()
	c.justice["misdeeds"]["base"] = 10.0
	c.justice["misdeeds"]["max"] = 1.0
	c.justice["misdeeds"]["kinds"] = {"contraband": {"weight": 1, "max_honesty": 10}}
	var sim := _sim(c)
	for f: String in sim.state.families:
		sim.state.families[f]["attitudes"]["honesty"] = 20
	_dawn(sim, 2)
	Misdeeds.step(sim)
	eq(_of(sim.events, "misdeed").size(), 0, "honesty 20: no contraband")
	for f: String in sim.state.families:
		sim.state.families[f]["attitudes"]["honesty"] = 0
	_dawn(sim, 3)
	Misdeeds.step(sim)
	check(_of(sim.events, "misdeed").all(func(e: Dictionary) -> bool: return str(e["kind"]) == "contraband"),
		"honesty 0: contraband")
	check(not _of(sim.events, "misdeed").is_empty(), "and some")
