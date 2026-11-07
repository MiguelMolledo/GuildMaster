extends "res://tests/test_case.gd"
## H6 criterion (docs/gdd/10_hitos.md H6; 04c §4.21.9.2 «protecciones del jugador: primer año»): no price war (no
## attack at all) on the player in the first year. In Bellcaire (the hostility's map), every AI family at rivalry 95
## with the player, who sold every day what each of them makes: the eight dawns of year 1 give nothing; the first
## dawn of year 2 the same families announce a price war on the player (so the gate is what stops them). Once by
## calling each family's decision for each day, once through the real sim's dawn.

const START: String = "artisan_blacksmith"
const ME: String = "fam_0001"

var cat := Catalog.load_from()


func _capital(seed_value: int = 1) -> Sim:
	return Sim.new(NewGame.from_start(cat, START, "normal", {"city": "capital", "cast": "fixed"}, seed_value)["state"], cat)


## Every AI family hates the player (95) and the player sold, the day before `day`, 6 of each piece they make.
func _provoke(sim: Sim, day: int) -> void:
	var bk := Hostility.book(sim.state)
	var sold := {}
	for f: String in Hostility._ai_families(sim.state):
		bk["values"][f + "|" + ME] = 95
		sim.state.families[f]["gold"] = maxi(int(sim.state.families[f].get("gold", 0)), 2000)  # not in austerity
		var home := Hostility._workshop_of(sim.state, f)
		if home == "":
			continue
		var btype := str(sim.state.buildings[home]["type"])
		for rid: String in sim.catalog.recipes():
			var r: Dictionary = sim.catalog.recipes()[rid]
			if str(r.get("building", "")) == btype:
				sold[str(r.get("output", {}).get("item", ""))] = 6
	bk["sales"] = {str(day - 1): {ME: sold}}


func _on_player(sim: Sim) -> Array:
	var out: Array = []
	for f: String in Hostility._ai_families(sim.state):
		var m := Hostility._mem(sim, f)
		if m.get("presage") is Dictionary and str(m["presage"].get("target", "")) == ME:
			out.append(str(m["presage"]["kind"]))
	for a: Dictionary in Hostility.book(sim.state).get("attacks", []):
		if bool(a.get("player", false)):
			out.append(str(a.get("kind", "")))
	return out


func test_no_attack_on_the_player_in_the_first_year() -> void:
	var sim := _capital()
	var first := int(cat.ai_rules.get("attack", {}).get("first_days", 8))
	eq(first, 8, "the first year is 8 days (D1)")
	for day: int in first:
		_provoke(sim, day)
		for f: String in Hostility._ai_families(sim.state):
			Hostility._decide(sim, f, Hostility._mem(sim, f), day)
		eq(_on_player(sim), [], "day %d of year 1: no presage nor attack on the player" % day)
	_provoke(sim, first)
	for f: String in Hostility._ai_families(sim.state):
		Hostility._decide(sim, f, Hostility._mem(sim, f), first)
	check("price_war" in _on_player(sim), "the first dawn of year 2 a price war is announced on the player: %s"
		% [_on_player(sim)])


func test_the_same_through_the_dawn_of_the_sim() -> void:
	var sim := _capital()
	var n := Hostility._ai_families(sim.state).size()
	for day: int in [7, 8]:
		sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY
		_provoke(sim, day)
		var dawn := Hostility._phase_start(sim, day, "dawn")
		while int(sim.state.clock["minute"]) < dawn + 3 * n + 1:   # every family's staggered minute of the dawn
			sim.step()
		if day == 7:
			eq(_on_player(sim), [], "the last dawn of year 1, through the sim: nothing on the player")
		else:
			check("price_war" in _on_player(sim), "the first dawn of year 2, through the sim: a price war on the player")
