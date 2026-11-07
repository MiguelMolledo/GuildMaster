extends "res://tests/test_case.gd"
## H6 + H13 · the AI families' agenda builds and buys (sim/ai/build.gd, AIBuild): H6's candidates, valve and title
## limit (Construction, Plots), chosen at dawn by the family's profile (data/ai_profiles "build"), with its gold over
## its reserve; Construction's own pass is off (data/construction.json ai.enabled false) and AIBuild runs in its minute.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "fam_0002"

var cat := Catalog.load_from()


func _new() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


## The AI tailor sells its shop to the player and has to put up another one (H6's case).
func _seller(sim: Sim) -> String:
	var shop := str(Plots.get_plot(sim, "plot_16")["building"])
	var seller := str(sim.state.buildings[shop]["owner"])
	var head := Kin.head(sim.state, seller)
	sim.state.families[FAM]["gold"] = 5000
	sim.state.families[FAM]["title"] = "citizen"
	Emotions.change_relation(sim, head, HERO, 0 - Emotions.relation(sim.state, head, HERO), "test")
	Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": shop})
	sim.state.families[seller]["gold"] = 500
	return seller


func test_the_agenda_builds_not_construction() -> void:
	check(not bool(cat.construction["ai"]["enabled"]), "Construction's own AI pass is off")
	var sim := _new()
	cat.construction["valve"]["min_free"] = 0
	var seller := _seller(sim)
	eq(AIBuild.choose(sim, seller), Construction.choose(sim, seller), "without a build block in its profile: H6's choice")
	eq(AIBuild.orders(sim), [], "nothing before first_day")
	sim.state.clock["minute"] = 12 * Clock.MINUTES_PER_DAY + 400
	var o: Array = AIBuild.orders(sim)
	eq(o.size(), 1, "from first_day, at dawn, the order to build (%s)" % [o])
	if o.size() == 1:
		eq(str(o[0]["type"]), "build", "a build order")
		check(bool(Orders.apply(sim, o[0])["ok"]), "and the town takes it")
		eq(int(sim.state.families[seller]["ai_build_day"]), 12, "the day noted for its cooldown")
	cat.construction["valve"]["min_free"] = 2


func test_the_profile_weighs_buying_and_building() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["title"] = "citizen"
	sim.state.families[RIVAL]["gold"] = 5000
	cat.construction["ai"]["expand"] = true
	var spare := NewGame.make_building(sim.state, cat, "forge", [40, 40], [41, 39], "")
	sim.state.buildings[spare]["for_sale"] = true
	var prof: Dictionary = cat.ai_profiles()[str(sim.state.families[RIVAL]["ai_profile"])]
	var keep: Variant = prof.get("build")
	prof["build"] = {"buy": 100.0, "build": 0.01, "min_score": 0.0}
	eq(str(AIBuild.choose(sim, RIVAL).get("kind", "")), "buy", "a profile that would rather buy takes the forge for sale")
	prof["build"] = {"buy": 0.0, "build": 100.0, "min_score": 0.0}
	eq(str(AIBuild.choose(sim, RIVAL).get("kind", "")), "build", "one that would rather build raises its own")
	prof["build"] = {"min_score": 1000000.0}
	eq(AIBuild.choose(sim, RIVAL), {}, "nothing that clears its own min_score")
	if keep == null:
		prof.erase("build")
	else:
		prof["build"] = keep
	cat.construction["ai"]["expand"] = false


func test_on_the_economy_maps_it_keeps_its_reserve() -> void:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"city": "capital", "cast": "fixed"}, 1)["state"], cat)
	var f := Hostility._ai_families(sim.state)[0] as String
	sim.state.families[f]["gold"] = 300
	eq(AIBuild.budget(sim, f), 300 - AIEconomy.reserve(sim, f, Hostility._profile(sim, f)), "Bellcaire: gold over AIEconomy's reserve")
	var v := _new()
	eq(AIBuild.budget(v, RIVAL), Construction.budget(v, RIVAL), "Vilarrasa: H6's budget")
