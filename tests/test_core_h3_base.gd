extends "res://tests/test_case.gd"
## H3 base (docs/contratos/h3_mercado.md): data loaded, the town_e map and scenario, the orders wired, the public
## armory and the rival allowed to work. The systems themselves are tested by their owners.

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


func test_h3_data_loads() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	eq((cat.market.get("stalls", {}) as Dictionary).keys().size(), 6, "3 stalls + the armory + (H12) the clothier and the goods stall")
	eq(int(cat.difficulty_levels("normal")["start_debt"]), 200, "normal debt")
	eq(int(cat.difficulty_levels("hard")["rival_craft"]), 6, "hard rival")
	check(cat.ai_profiles().has("rival_smith"), "rival profile")
	check(cat.contracts().has("blacksmith"), "blacksmith contracts")
	eq((cat.starts()["artisan_blacksmith"]["objectives"] as Array).size(), 6, "6 start objectives")
	for kind: String in ["starts", "objectives"]:
		for id: String in cat.tables[kind]:
			var key := str(cat.tables[kind][id].get("name_key", ""))
			check(TranslationServer.translate(key) != key, "%s/%s has text" % [kind, id])
	check(cat.buildings()["armory"]["public"], "the armory is public")


func test_town_e_map_has_the_market() -> void:
	var m: Dictionary = cat.maps()["town_e"]
	var grid := Grid.of(cat, "town_e")
	for st: String in ["resources", "food", "materials"]:
		var t: Array = m["stalls"][st]["tile"]
		var s: Array = m["stalls"][st]["service"]
		check(not grid.walkable(int(t[0]), int(t[1])), "%s stall is blocked" % st)
		check(grid.walkable(int(s[0]), int(s[1])), "%s service tile is walkable" % st)
	check(grid.walkable(int(m["board"]["service"][0]), int(m["board"]["service"][1])), "board service")
	eq(str(m["buildings"]["armory"]["type"]), "armory", "the armory site")


func test_scenario_has_rival_and_armory() -> void:
	var st := _sim().state
	eq(Money.gold(st, "fam_0001"), 100, "player family 100")
	eq(Money.gold(st, "fam_0002"), 50, "Vidal 50")
	eq(Money.gold(st, "fam_0003"), 80, "Ferrer 80")
	eq(str(st.families["fam_0003"]["ai_profile"]), "rival_smith", "rival profile")
	var bernat: Dictionary = st.characters["chr_0006"]
	eq([bernat["name"], bernat["family"], bernat["location"], int(bernat["stats"]["craft"])],
		["Bernat", "fam_0003", "bld_0002", 5], "Bernat in his forge")
	eq(str(st.buildings["bld_0002"]["owner"]), "fam_0003", "the rival forge")
	eq(Inventory.count(st.buildings["bld_0002"]["inventory"], "iron"), 8, "with iron")
	eq(str(st.buildings["bld_0003"]["type"]), "armory", "the armory")
	eq(str(st.buildings["bld_0003"]["owner"]), "", "the town's")
	check(st.loans.is_empty(), "no loan in the sandbox")


func test_anybody_may_enter_the_armory_not_the_rival_forge() -> void:
	var sim := _sim()
	check(Buildings.can_enter(sim, "chr_0001", "bld_0003")["ok"], "Hugo may enter the armory")
	check(Buildings.can_enter(sim, "chr_0006", "bld_0003").get("reason") == "inside_other_building",
		"Bernat is in his forge")
	eq(Buildings.can_enter(sim, "chr_0001", "bld_0002")["reason"], "not_your_building", "not the rival's forge")


func test_rival_may_work_his_forge_by_day() -> void:
	var sim := _sim()
	sim.state.clock["minute"] = 600
	eq(Production.may_work(sim, "chr_0006", "bld_0002"), "", "by day")
	sim.state.clock["minute"] = 1380
	eq(Production.may_work(sim, "chr_0006", "bld_0002"), "night_rest", "not at night")
	sim.state.clock["minute"] = 600
	eq(Production.may_work(sim, "chr_0004", "bld_0001"), "not_controlled", "an AI family without profile does not")


func test_h3_orders_are_wired() -> void:
	var sim := _sim()
	var base := {"actor": "chr_0001"}
	for t: String in ["buy", "sell", "repay_loan", "read_notices", "accept_contract", "deliver_contract", "abandon_contract"]:
		var r := Orders.apply(sim, base.merged({"type": t}))
		check(r["reason"] != "unknown_order", "%s is wired (%s)" % [t, r["reason"]])
	check(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1).has("ok"), "from_start answers")
	sim.run_minutes(Clock.MINUTES_PER_DAY)  # every H3 system runs a whole day without breaking anything


func test_market_price_and_hours() -> void:
	var sim := _sim()
	eq(Market.price(sim, "sword", 0, "buy"), 65, "base price at demand 1")
	eq(Market.price(sim, "sword", 0, "sell"), 46, "round(65 × 0.7)")
	eq(Market.price(sim, "sword", 2, "buy"), 104, "excellent ×1.6")
	sim.state.market["demand"]["sword"] = 0.5
	eq(Market.price(sim, "sword", 1, "buy"), 42, "round(65 × 1.3 × 0.5)")
	sim.state.difficulty = "hard"
	var iron := float(cat.item("iron")["base_price"])
	eq(Market.price(sim, "iron", 0, "buy"), roundi(iron * 1.1), "round(iron × 1.1)")
	eq(Market.price(sim, "iron", 0, "sell"), roundi(iron * 0.7), "the difficulty only touches buying: round(iron × 0.7)")
	eq(Market.price(sim, "dragon", 0, "buy"), 0, "unknown item")
	sim.state.clock["minute"] = 600
	check(Market.is_open(sim), "open by day")
	sim.state.clock["minute"] = 1380
	check(not Market.is_open(sim), "closed at night")


func test_notices_add() -> void:
	var sim := _sim()
	var id := Notices.add(sim, "fam_0001", Notices.WARNING, "objective.forge_sword", {}, "bld_0001")
	eq(id, "ntc_0001", "an id")
	var n: Dictionary = sim.state.notices[0]
	eq([n["family"], n["severity"], n["key"], n["target"], n["read"]],
		["fam_0001", "warning", "objective.forge_sword", "bld_0001", false], "the notice")
	eq(str(sim.events[-1]["type"]), "notice_added", "event")
