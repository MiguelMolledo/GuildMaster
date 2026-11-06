extends "res://tests/test_case.gd"
## Forja viva (docs/gdd/03b_diversion_y_ritmo.md §3b.2) and contracts with specs (§3b.3): the three decisions, the
## bench (playing well gives more quality, not playing gives what mode normal gives, playing badly loses: O-C10),
## masterworks with a name in the chronicle, what a family learns, the grace at the end of the cycle, save/load mid
## cycle, specs that do not move state.rng, delivering with the pieces made to the spec, and the v20 migration.

const HUGO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(seed: int = 7) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	(r["state"] as WorldState).families["fam_0003"]["ai_profile"] = ""  # the rival smith off: its rolls share state.rng
	var sim := Sim.new(r["state"], cat)
	var ch: Dictionary = sim.state.characters[HUGO]
	ch["location"] = FORGE
	ch["station"] = ""
	ch["position"] = sim.state.buildings[FORGE]["door"].duplicate()
	return sim


func _stock(sim: Sim, n: int) -> void:
	var st: Dictionary = sim.state.buildings[FORGE]["inventory"]
	st["stacks"] = []
	Inventory.add(st, cat, "iron_ingot", Inventory.NORMAL, n)
	Inventory.add(st, cat, "coal", Inventory.NORMAL, n)


func _work(sim: Sim, recipe: String, mode: String, extra: Dictionary = {}) -> Dictionary:
	var o := {"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "anvil", "recipe": recipe, "mode": mode}
	o.merge(extra, true)
	return Orders.apply(sim, o)


func _live(step: String, choice: String = "") -> Dictionary:
	return {"type": "live_forge", "actor": HUGO, "building": FORGE, "zone": "anvil", "step": step, "choice": choice}


## The next decision of a player who plays `how`: "perfect", "skip" (Resolver sin jugar at once) or "bad" (burnt,
## all finish strikes, the wrong medium). [] if there is nothing to decide now.
func _decide(sim: Sim, how: String) -> Array:
	var v := LiveForge.view(sim, FORGE, "anvil")
	if v.is_empty() or str(v["stage"]) == "done":
		return []
	var rdef := LiveForge.recipe_def(sim, str(v["recipe"]))
	if how == "skip":
		return [_live("skip")]
	var part: Dictionary = sim.state.buildings[FORGE]["zones"]["anvil"]["job"]["live"]
	match str(v["stage"]):
		"heat":
			return [_live("heat", str(rdef["heat"]) if how == "perfect" else "white")]
		"strike":
			var t := LiveForge.template_of(sim, rdef, part)
			var i: int = (v["strikes"] as Array).size()
			return [_live("strike", str(t[i]) if how == "perfect" else ("finish" if str(t[i]) != "finish" else "strong"))]
		"quench":
			var want := LiveForge.wanted_quench(rdef, part)
			return [_live("quench", want if how == "perfect" else ("water" if want != "water" else "air"))]
	return []


## Makes `pieces` hammers (or `recipe`) in `mode`, playing `how`; returns {qualities: [int], masterworks, events}.
func _make(seed: int, pieces: int, mode: String, how: String, recipe: String = "forge_hammer") -> Dictionary:
	var sim := _sim(seed)
	_stock(sim, (pieces + 4) * 2)
	check(_work(sim, recipe, mode)["ok"], "starts %s" % mode)
	var qs: Array = []
	var mws := 0
	var guard := pieces * 400
	while qs.size() < pieces and guard > 0:
		guard -= 1
		var orders: Array = _decide(sim, how) if mode == LiveForge.MODE else []
		for e: Dictionary in sim.step(orders):
			match str(e["type"]):
				"order_refused":
					failures.append("refused %s: %s" % [e["order"], e["reason"]])
				"work_done":
					qs.append(int(e["quality"]))
					Inventory.remove(sim.state.buildings[FORGE]["inventory"], str(e["item"]), int(e["quality"]), 1)
				"masterwork_made":
					mws += 1
		if sim.state.buildings[FORGE]["zones"]["anvil"].get("job") == null and qs.size() < pieces:
			var rr := _work(sim, recipe, mode)  # a skipped live cycle repeats in normal: back to live
			if not rr["ok"]:
				failures.append("restarts %s: %s" % [mode, rr["reason"]])
				break
	eq(qs.size(), pieces, "%d pieces in %s/%s" % [pieces, mode, how])
	return {"qualities": qs, "masterworks": mws, "sim": sim}


func _mean(a: Array) -> float:
	var t := 0.0
	for q: Variant in a:
		t += float(q)
	return t / maxf(1.0, float(a.size()))


# --- Rules -----------------------------------------------------------------------------------------------------------

func test_live_only_by_hand_and_for_its_recipes() -> void:
	var sim := _sim()
	_stock(sim, 6)
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "iron", Inventory.NORMAL, 4)
	var r := Orders.apply(sim, {"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "live"})
	eq(r["reason"], "no_live_forge", "the ingot has no Forja viva")
	sim.state.characters[HUGO]["controlled_by"] = "ai"
	eq(_work(sim, "forge_hammer", "live")["reason"], "not_by_hand", "only whoever the player controls")
	sim.state.characters[HUGO]["controlled_by"] = "human"
	check(_work(sim, "forge_hammer", "live")["ok"], "the hammer by hand")
	var job: Dictionary = sim.state.buildings[FORGE]["zones"]["anvil"]["job"]
	check(job.get("live") is Dictionary, "the job keeps its decisions")
	eq(job.get("window"), null, "no master-touch window in live")
	eq(Orders.apply(sim, _live("strike", "strong"))["reason"], "wrong_step", "heat first")
	eq(Orders.apply(sim, _live("heat", "blue"))["reason"], "unknown_choice", "a colour of the list")
	check(Orders.apply(sim, _live("heat", "orange"))["ok"], "heat")
	eq(LiveForge.view(sim, FORGE, "anvil")["verdicts"]["heat"], "right", "orange is the hammer's colour")
	eq(LiveForge.learned(sim, HUGO, "forge_hammer").get("heat"), "orange", "the family learns the colour")
	check(Orders.apply(sim, _live("skip"))["ok"], "Resolver sin jugar")
	eq(Orders.apply(sim, _live("quench", "oil"))["reason"], "live_done", "nothing after skipping")
	check(Orders.is_management("live_forge"), "a decision never touches the order queue")


func test_verdicts_and_steps() -> void:
	var sim := _sim()
	var rdef := LiveForge.recipe_def(sim, "forge_sword")
	eq(LiveForge.heat_verdict(sim, rdef, "cherry"), "right", "cherry")
	eq(LiveForge.heat_verdict(sim, rdef, "orange"), "near", "a neighbour")
	eq(LiveForge.heat_verdict(sim, rdef, "yellow"), "wrong", "two away")
	eq(LiveForge.heat_verdict(sim, LiveForge.recipe_def(sim, "forge_hammer"), "white"), "wrong", "burnt")
	var t: Array = rdef["strikes"]
	eq(LiveForge.strikes_verdict(t, t), "right", "the template")
	eq(LiveForge.strikes_verdict(t, ["strong", "measured", "strong", "finish"]), "near", "one off")
	eq(LiveForge.strikes_verdict(t, ["finish", "finish", "strong", "finish"]), "wrong", "more off")
	eq(LiveForge.steps_of(sim, {"heat": "right", "strikes": "right", "quench": "right"}), 1, "three right: +1")
	eq(LiveForge.steps_of(sim, {"heat": "right", "strikes": "near", "quench": "right"}), 0, "two right: 0")
	eq(LiveForge.steps_of(sim, {"heat": "wrong", "strikes": "near", "quench": "wrong"}), -1, "two wrong: -1")
	eq(LiveForge.steps_of(sim, {"heat": "", "strikes": "", "quench": ""}), 0, "nothing decided: 0")


## The bench of §3b.2: same seed, same pieces. Not playing (skip) gives exactly mode normal, piece by piece (the same
## rolls); playing well gives more; playing badly loses (O-C10).
func test_bench_play_well_more_skip_equal_bad_less() -> void:
	var n := 60
	var normal := _make(31, n, "normal", "")
	var skip := _make(31, n, LiveForge.MODE, "skip")
	var perfect := _make(31, n, LiveForge.MODE, "perfect")
	var bad := _make(31, n, LiveForge.MODE, "bad")
	eq(skip["qualities"], normal["qualities"], "Resolver sin jugar = mode normal, piece by piece")
	var mn := _mean(normal["qualities"])
	var mp := _mean(perfect["qualities"])
	var mb := _mean(bad["qualities"])
	print("[test_forja_live] banco %d martillos (Artesanía 7): normal=%.3f sin jugar=%.3f bien=%.3f mal=%.3f obras=%d" % [
		n, mn, _mean(skip["qualities"]), mp, mb, int(perfect["masterworks"])])
	check(mp > mn + 0.3, "playing well gives more (%.3f > %.3f)" % [mp, mn])
	check(mb < mn, "playing badly loses (%.3f < %.3f)" % [mb, mn])
	check(int(perfect["masterworks"]) > 0, "craft 7 and three right: some masterworks")
	eq(int(skip["masterworks"]) + int(bad["masterworks"]), 0, "no masterwork without playing well")


func test_masterwork_named_in_the_chronicle() -> void:
	var practice := int(cat.live_forge["masterwork"].get("practice", 0))
	var chance := float(cat.live_forge["masterwork"]["chance"])
	cat.live_forge["masterwork"]["practice"] = 0  # the naming and the chronicle, the practice and the odds aside
	cat.live_forge["masterwork"]["chance"] = 0.5
	var r := _make(5, 20, LiveForge.MODE, "perfect", "forge_sword")
	cat.live_forge["masterwork"]["practice"] = practice
	cat.live_forge["masterwork"]["chance"] = chance
	var sim: Sim = r["sim"]
	var pieces := LiveForge.masterworks_of(sim.state, "fam_0001")
	check(not pieces.is_empty(), "named swords")
	var m: Dictionary = pieces[0]
	eq(m["item"], "sword", "a sword")
	check(str(m["patron"]) in (cat.live_forge["patrons"] as Array), "a patron of the list")
	eq(m["family_name"], sim.state.families["fam_0001"]["name"], "of the family's name")
	check((m["traits"] as Array).has("master_mark") and (m["traits"] as Array).has("oil_tempered"), "its traits")
	var chron := sim.state.chronicle.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "masterwork")
	eq(chron.size(), pieces.size(), "each one in the chronicle")
	var learned := LiveForge.learned(sim, HUGO, "forge_sword")
	eq(learned.get("heat"), "cherry", "learned the colour")
	eq(learned.get("quench"), "oil", "learned the quench")
	eq(learned.get("strikes"), cat.live_forge["recipes"]["forge_sword"]["strikes"], "learned the template")
	sim.state.characters[HUGO]["stats"]["craft"] = 6
	check(int(LiveForge.view(sim, FORGE, "anvil").get("template", []).size()) >= 0, "a view")


## Equilibrio (03b §3b.2, 2026-11-05): no masterwork before `practice` perfect pieces of the recipe; after, they come.
func test_masterwork_asks_for_practice() -> void:
	var practice := int(cat.live_forge["masterwork"].get("practice", 0))
	check(practice > 0, "a practice threshold in the data")
	var chance := float(cat.live_forge["masterwork"]["chance"])
	cat.live_forge["masterwork"]["chance"] = 1.0
	cat.live_forge["masterwork"]["practice"] = 3
	var r := _make(5, 3, LiveForge.MODE, "perfect", "forge_sword")
	var sim: Sim = r["sim"]
	eq(LiveForge.masterworks_of(sim.state, "fam_0001").size(), 0, "three perfect swords: still practice")
	eq(int(sim.state.masterworks["practice"]["fam_0001"]["forge_sword"]), 3, "counted")
	r = _make(5, 4, LiveForge.MODE, "perfect", "forge_sword")
	eq(LiveForge.masterworks_of((r["sim"] as Sim).state, "fam_0001").size(), 1, "the fourth can be one")
	cat.live_forge["masterwork"]["chance"] = chance
	cat.live_forge["masterwork"]["practice"] = practice


func test_grace_then_resolves_and_repeats_in_normal() -> void:
	var sim := _sim()
	_stock(sim, 6)
	check(_work(sim, "forge_hammer", "live")["ok"], "starts")
	var job: Dictionary = sim.state.buildings[FORGE]["zones"]["anvil"]["job"]
	var end := int(job["end"])
	var grace := roundi(float(cat.live_forge["grace_hours"]) * 60.0)
	var done_at := -1
	var next_mode := ""
	for i: int in end - int(sim.state.clock["minute"]) + grace + 5:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "work_done":
				done_at = int(sim.state.clock["minute"])
			if str(e["type"]) == "work_started":
				next_mode = str(e["mode"])
	eq(done_at, end + grace, "waits the grace for the decisions, then resolves")
	eq(next_mode, "normal", "not played: the next cycle is normal")


func test_save_and_load_mid_live_cycle() -> void:
	var sim := _sim()
	_stock(sim, 6)
	check(_work(sim, "forge_sword", "live")["ok"], "starts")
	sim.step([_live("heat", "cherry")])
	sim.step([_live("strike", "strong")])
	var text := JSON.stringify(sim.state.to_dict())
	var back := SaveFile.from_text(text)
	check(back["ok"], "loads")
	var sim2 := Sim.new(back["state"], cat)
	var orders := [[_live("strike", "measured")], [_live("strike", "measured")], [_live("strike", "finish")],
		[_live("quench", "oil")]]
	for o: Array in orders:
		sim.step(o)
		sim2.step(o)
	for i: int in 300:
		sim.step()
		sim2.step()
	eq(sim2.state_hash(), sim.state_hash(), "the same game after a load mid cycle")


# --- Contracts with specs (§3b.3) ------------------------------------------------------------------------------------

func test_specs_do_not_move_the_rng() -> void:
	var a := _sim(11)
	var b := _sim(11)
	var t: Dictionary = cat.contracts()["blacksmith"].duplicate(true)
	t.erase("specs")
	var with_specs := 0
	for i: int in 20:
		a.state.contracts["board"] = []
		b.state.contracts["board"] = []
		var ida := Contracts.post_random(a)
		var cb := Contracts.post(b, {"client": "x", "item": "sword", "qty": 1, "min_quality": 0, "deadline_days": 1})
		LiveForge.attach_spec(b, cb, t)
		with_specs += 1 if a.state.contracts["board"][0].has("spec") else 0
		check(ida != "", "posted")
	var c := _sim(11)
	for i: int in 20:
		c.state.contracts["board"] = []
		Contracts.post_random(c)
	eq(a.state.rng.state, c.state.rng.state, "same rng after posting with specs on")
	check(with_specs > 0 and with_specs < 20, "some ask for a variant (%d of 20)" % with_specs)


func _spec_contract(sim: Sim, want: Dictionary, qty: int = 1) -> String:
	var cid := Contracts.post(sim, {"client": "guard_captain", "item": "sword", "qty": qty, "min_quality": 0,
		"deadline_days": 3})
	var c: Dictionary = sim.state.contracts["board"].back()
	var w := want.duplicate()
	w["id"] = "left_knight"
	c["spec"] = w
	c["spec_pay"] = 30
	c["made"] = []
	c["family"] = "fam_0001"
	c["actor"] = HUGO
	c["accepted"] = int(sim.state.clock["minute"])
	c["due"] = int(sim.state.clock["minute"]) + 3 * Clock.MINUTES_PER_DAY
	sim.state.contracts["board"].pop_back()
	(sim.state.contracts["accepted"] as Array).append(c)
	return cid


func test_made_to_spec_goes_to_the_contract_and_pays_more() -> void:
	var sim := _sim()
	_stock(sim, 8)
	var want := {"length": "long", "guard": "plain", "temper": "oil"}
	var cid := _spec_contract(sim, want, 1)
	eq(_work(sim, "forge_sword", "normal", {"contract": cid, "variant": {"length": "long", "guard": "fancy"}})["reason"],
		"bad_variant", "a variant of the list")
	eq(_work(sim, "forge_hammer", "normal", {"contract": cid, "variant": {}})["reason"], "wrong_item", "its item")
	check(_work(sim, "forge_sword", "normal", {"contract": cid,
		"variant": {"length": "long", "guard": "plain", "temper": "oil"}})["ok"], "made to the spec without playing")
	var job: Dictionary = sim.state.buildings[FORGE]["zones"]["anvil"]["job"]
	var base := Production.owner_cycle_minutes(sim, FORGE, cat.recipes()["forge_sword"], "normal")
	eq(int(job["end"]) - int(job["start"]), roundi(base * 1.15), "the long blade takes longer")
	var pieces: Array = []
	for i: int in 400:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "spec_piece":
				pieces.append(e)
	check(not pieces.is_empty() and bool(pieces[0]["match"]), "the piece matches and is kept for the client")
	var c := LiveForge.accepted_contract(sim, HUGO, cid)
	eq(LiveForge.crate_units(c, 0), 1, "kept in the contract")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword"), maxi(0, pieces.size() - 1),
		"the next ones (no spec once full) to the storage")
	# Deliver at the board: nothing in the bag, the kept one goes.
	var board := Contracts.board_service(sim)
	var ch: Dictionary = sim.state.characters[HUGO]
	ch["location"] = ""
	ch["station"] = ""
	ch["position"] = [int(board[0]), int(board[1])]
	ch["path"] = []
	(sim.state.buildings[FORGE]["zones"]["anvil"] as Dictionary)["job"] = null
	sim.state.buildings[FORGE]["zones"]["anvil"]["occupant"] = ""
	var gold := int(sim.state.families["fam_0001"]["gold"])
	var pay := int(c["pay"])
	var r := Orders.apply(sim, {"type": "deliver_contract", "actor": HUGO, "contract": cid})
	check(r["ok"], "delivered with the kept piece (%s)" % r["reason"])
	eq(int(sim.state.families["fam_0001"]["gold"]) - gold, pay + 30, "pay + spec_pay")


func test_a_piece_off_spec_goes_to_the_storage() -> void:
	var sim := _sim()
	_stock(sim, 4)
	var cid := _spec_contract(sim, {"length": "long", "guard": "plain", "temper": "oil"})
	check(_work(sim, "forge_sword", LiveForge.MODE, {"contract": cid, "variant": {"length": "long", "guard": "plain"}})[
		"ok"], "in live")
	var t := LiveForge.template_of(sim, LiveForge.recipe_def(sim, "forge_sword"),
		sim.state.buildings[FORGE]["zones"]["anvil"]["job"]["live"])
	eq(t.size(), 5, "the long blade adds a strike")
	var miss: Array = []
	var orders := [[_live("heat", "cherry")]]
	for k: Variant in t:
		orders.append([_live("strike", str(k))])
	orders.append([_live("quench", "water")])  # the client wanted oil
	for o: Array in orders:
		sim.step(o)
	for i: int in 400:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "spec_piece":
				miss.append(e)
	check(not miss.is_empty() and not bool(miss[0]["match"]) and str(miss[0]["why"]) == "temper", "the temper misses")
	eq(LiveForge.crate_units(LiveForge.accepted_contract(sim, HUGO, cid), -1), 0, "nothing kept")
	check(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword") >= 1, "the sword to the storage")


# --- Save v20 --------------------------------------------------------------------------------------------------------

func test_migration_to_v20_keeps_everything_open() -> void:
	var r := NewGame.from_scenario("town_e_start", 3)
	var d: Dictionary = (r["state"] as WorldState).to_dict()
	d.erase("unlocks")
	d.erase("masterworks")
	d["version"] = 19
	var m := SaveFile.migrate(d)
	check(m["ok"], "migrates")
	var u: Dictionary = m["data"]["unlocks"]
	check(u.has("fam_0001") and (u["fam_0001"] as Dictionary).has("_all"), "a game from before keeps all open")
	eq(m["data"]["masterworks"], {"pieces": [], "learned": {}}, "no masterworks")
	var back := SaveFile.from_text(JSON.stringify(m["data"]))
	check(back["ok"], "loads")
	eq(int((back["state"] as WorldState).version), WorldState.VERSION, "v20")


## «Cerrar» after a result (verifica): live_forge stop interrupts the piece and gives its inputs back (D11); it is a
## management order, so given in pause it does not wait behind the work in the actor's queue.
func test_stop_gives_the_inputs_back() -> void:
	var sim := _sim()
	_stock(sim, 6)
	check(_work(sim, "forge_sword", LiveForge.MODE)["ok"], "starts")
	var st: Dictionary = sim.state.buildings[FORGE]["inventory"]
	eq(Inventory.count(st, "iron_ingot"), 4, "two ingots taken")
	check(Orders.is_management("live_forge"), "management")
	var ev := sim.step([_live("stop")])
	eq(sim.state.buildings[FORGE]["zones"]["anvil"]["job"], null, "no piece at the anvil")
	eq(Inventory.count(st, "iron_ingot"), 6, "the ingots back")
	check(ev.any(func(e: Dictionary) -> bool: return str(e["type"]) == "work_interrupted"), "interrupted")
	eq(Orders.apply(sim, _live("stop"))["reason"], "not_working", "nothing to stop now")


## verifica #18: the screen runs at ×1 while there is a decision to take; once the quench is given the player's speed
## comes back (the rest of the piece runs at it), and nothing changes it again when the screen closes.
func test_the_screen_gives_the_speed_back_after_the_quench() -> void:
	var g: Node = (load("res://game/autoload/game.gd") as GDScript).new()
	var sim := _sim()
	_stock(sim, 10)
	check(_work(sim, "forge_sword", LiveForge.MODE)["ok"], "a sword by hand")
	sim.step()
	g.call("set_speed", 4)
	var scr := (load("res://game/ui/forja/live_forge_screen.tscn") as PackedScene).instantiate() as LiveForgeScreen
	scr.game = g
	scr.open_for(sim, FORGE, "anvil")
	eq(int(g.get("speed")), 1, "deciding: ×1")
	for i: int in 12:
		var o := _decide(sim, "perfect")
		if o.is_empty():
			break
		check(Orders.apply(sim, o[0])["ok"], "decision %s" % [o[0]])
		scr.refresh()
		if str(LiveForge.view(sim, FORGE, "anvil").get("stage", "")) != "done":
			eq(int(g.get("speed")), 1, "still deciding: ×1")
	eq(str(LiveForge.view(sim, FORGE, "anvil")["stage"]), "done", "quenched: nothing left to decide")
	eq(int(g.get("speed")), 4, "the player's ×4 back while the piece ends")
	scr.close()
	eq(int(g.get("speed")), 4, "and it stays when the screen closes")
	scr.free()
	g.free()
