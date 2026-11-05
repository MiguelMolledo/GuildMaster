extends "res://tests/test_case.gd"
## Fiestas (04f 4.25.3 «En la vista»): the festival card (FestivalPage: the crier with the sponsor buttons, the start,
## the wedding offer), the provisional illustration with its label, the sites of the decoration on town_e, the festive
## clothes and music of the festival in force, and the commission recipes that show at the workshop only with a contract.

const DAY: int = 1440

var cat := Catalog.load_from()


func _game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _to(sim: Sim, minute: int) -> Array:
	var seen: Array = []
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)
		seen.append_array(sim.events)
	return seen


func test_the_crier_card() -> void:
	var sim := _game()
	var evs := _to(sim, 13 * 60)
	var eve: Dictionary = evs.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "festival_eve")[0]
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["gold"] = 500
	var d := FestivalPage.data_for(sim, eve, fam)
	eq(str(d["template"]), "card", "a card of the page kit")
	eq(str(d["title"]), SimQuery.festival_name("mayday_corpus"), "its name")
	check(str(d.get("ribbon", "")) != "", "the crier's ribbon")
	check(d["image"] is Texture2D, "an illustration (or its greybox)")
	if VisualPaths.is_placeholder(d["image"]):
		eq(str((d["image"] as Texture2D).get_meta("label", "")), "mayday_corpus", "the greybox says what it stands for")
	var ids: Array = (d["buttons"] as Array).map(func(b: Dictionary) -> String: return str(b["id"]))
	eq(ids, ["ok", "sponsor:banquet", "sponsor:bulls", "sponsor:music"], "Entendido and the parts to sponsor")
	var o := FestivalPage.order_for("sponsor:bulls", d, Kin.head(sim.state, fam))
	eq(str(o["type"]), "festival_sponsor", "a button gives the sponsor order")
	check(Orders.apply(sim, o)["ok"], "and it works")
	var d2 := FestivalPage.data_for(sim, eve, fam)
	check(not (d2["buttons"] as Array).any(func(b: Dictionary) -> bool: return str(b["id"]) == "sponsor:bulls"),
		"what it already pays is not offered again")


func test_effect_lines_say_what_changes() -> void:
	var sim := _game()
	var lines: Array = []
	for f: Dictionary in Festivals.def_of(sim, "harvest_fair")["effects"]:
		var l := FestivalPage.effect_line(sim, f)
		if not l.is_empty():
			lines.append(str(l["text"]))
	check(lines.size() >= 5, "the fair tells its effects (%s)" % [lines])


func test_wedding_offer_card() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var d := FestivalPage.data_for(sim, {"type": "festival_wedding_offer", "family": fam,
		"couple": [Kin.head(sim.state, fam), ""]}, fam)
	var ids: Array = (d["buttons"] as Array).map(func(b: Dictionary) -> String: return str(b["id"]))
	eq(ids, ["plain", "host_wedding"], "a plain wedding or pay the banquet")
	eq(str(FestivalPage.order_for("host_wedding", d, "chr_0001")["type"]), "festival_host_wedding", "its order")


func test_decoration_sites_of_town_e() -> void:
	var sim := _game()
	var s := FestivalLayer.sites(sim.state, sim.catalog)
	for k: String in ["plaza_center", "plaza_ring", "plaza_edge", "main_street", "town_hall", "gates"]:
		check(not (s[k] as Array).is_empty(), "site %s has tiles" % k)
	eq(s, FestivalLayer.sites(sim.state, sim.catalog), "the same tiles every time")
	var board: Array = sim.catalog.maps()["town_e"]["board"]["service"]
	check(not Vector2i(int(board[0]), int(board[1])) in (s["plaza_ring"] as Array), "never on the board's tile")


func test_clothes_and_music_of_the_feast() -> void:
	var sim := _game()
	eq(FestivalLayer.clothes(sim), {}, "everyday clothes")
	_to(sim, 7 * DAY + 19 * 60)  # Carnival
	var look := FestivalLayer.clothes(sim)
	eq(str(look.get("id", "")), "carnival", "Carnival clothes")
	check(bool(look.get("mask", false)), "with masks")
	eq(FestivalLayer.music(sim), "music_fest_carnival", "its music id (audio.json pending_music until the file)")


func test_commission_recipes_show_with_a_contract() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var actor := Kin.head(sim.state, fam)
	var forge := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("owner", "")) == fam and str(sim.state.buildings[b].get("type", "")) == "forge":
			forge = b
	var ids := func() -> Array:
		return Production.recipe_options(sim, actor, forge, "anvil").map(func(o: Dictionary) -> String: return str(o["recipe"]))
	check(not "forge_horseshoe" in ids.call(), "no festival piece without a contract")
	(sim.state.contracts["accepted"] as Array).append({"id": "ctr_9999", "item": "horseshoe", "qty": 1, "family": fam,
		"race": true, "due": 99999, "accepted": 0, "client": "fair_warden", "min_quality": 0, "warned": []})
	check("forge_horseshoe" in ids.call(), "the horseshoes show once a contract asks for them")


func test_the_fixed_feasts_have_their_illustration() -> void:
	for f: Dictionary in Festivals.calendar(_game()):
		var id := str(f["id"])
		for small: bool in [false, true]:
			var t := VisualPaths.illustration_or_greybox("events", id, small)
			check(t != null and not VisualPaths.is_placeholder(t), "%s%s: its art (arte-fal-2, by alias)" % [id,
				" small" if small else ""])
			if t != null:
				eq(t.get_width(), 192 if small else 240, "%s: its size" % id)


## One alias table for the event illustrations (VisualPaths.EVENT_ILLUSTRATION_ALIAS): vida's incidents find theirs.
func test_the_incidents_find_their_illustration_by_the_same_alias() -> void:
	for id: String in ["altercation", "bandit_raid", "kidnapping"]:
		check(VisualPaths.illustration("events", id) != null, "%s: its art" % id)
		check(VisualPaths.illustration("events", id, true) != null, "%s: its small art" % id)
	var sim := _game()
	var d := IncidentPage.data_for(sim, {"def": "altercation", "card": {}}, "")
	check(d.get("image") is Texture2D and not VisualPaths.is_placeholder(d["image"]), "the incident card shows the art")


## The festival props of arte-fal-2 (VisualPaths.FESTIVAL_PROP_ALIAS) with their footprints; the animals keep the greybox.
func test_festival_props_have_their_scene_and_footprint() -> void:
	for id: String in VisualPaths.FESTIVAL_PROP_ALIAS:
		check(VisualPaths.has_scene("props", VisualPaths.festival_prop(id)), "%s: its scene" % id)
	eq(FestivalLayer.footprint("fair_stall"), Vector2i(2, 2), "the fair stall 2×2")
	eq(FestivalLayer.footprint("tilt_yard"), Vector2i(4, 1), "a stretch of the lists 4×1")
	eq(FestivalLayer.footprint("pen"), Vector2i(3, 3), "the pen 3×3")
	eq(FestivalLayer.footprint("lanterns"), Vector2i(1, 1), "a lantern 1×1")
	eq(FestivalLayer.footprint("pig"), Vector2i(1, 1), "no art: the greybox, 1×1")
	check(not VisualPaths.has_scene("props", VisualPaths.festival_prop("pig")), "the pig has no scene yet")
	var used := {}
	for f: Dictionary in Festivals.defs(_game()).values():
		for d: Dictionary in f.get("view", {}).get("decor", []):
			used[str(d["prop"])] = true
	for p: String in used:
		check(VisualPaths.FESTIVAL_PROP_ALIAS.has(p) or p in ["bull", "pig", "sheep", "horse"], "%s: art or a known gap" % p)


## Never on the map's dressing: the well in the middle of the plaza keeps its tile.
func test_decoration_keeps_off_the_well() -> void:
	var sim := _game()
	var s := FestivalLayer.sites(sim.state, sim.catalog)
	check(not Vector2i(19, 18) in (s["_free"] as Array), "the well's tile is not free ground")
	check(not Vector2i(19, 18) in (s["plaza_center"] as Array), "nor the middle of the plaza")
