extends "res://tests/test_case.gd"
## The rival smith (GDD 4.5.5, docs/contratos/h3_mercado.md): plays through real orders, sells while the demand holds,
## buys keeping its reserve, takes contracts it can make, deterministic and saved with the game.

var cat := Catalog.load_from()

const BERNAT := "chr_0006"
const FERRER := "fam_0003"
const ALLOWED: Array[String] = ["enter_building", "exit_building", "move_to", "buy", "sell", "work_at", "transfer",
	"accept_contract", "deliver_contract"]


func _sim(s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", s)["state"], cat)


func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func test_with_idle_the_rival_sells_and_the_demand_drops() -> void:
	var sim := _sim()
	var sold: Array = []
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "market_sold" and str(e["family"]) == FERRER:
				sold.append({"item": str(e["item"]), "after": Market.demand(sim, str(e["item"]))})
	check(sold.size() >= 1, "the rival sold something on day 1 (%d)" % sold.size())
	if sold.is_empty():
		return
	var drop := float(cat.market["demand"]["drop_per_unit"])
	near(float(sold[0]["after"]), 1.0 - drop, 0.0001, "the first sale drops the demand of %s by %.2f" % [sold[0]["item"],
		drop])
	var thr := RivalAI.sell_min_demand(sim, cat.ai_profiles()["rival_smith"])
	for s: Dictionary in sold:
		check(float(s["after"]) >= thr - drop - 0.0001, "never sells under the threshold (%s %.2f)" % [s["item"], s["after"]])


func test_only_real_orders_and_none_refused() -> void:
	var sim := _sim()
	var given: Array = []
	var refused := 0
	var cats := {}
	var last := ""
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "order_refused" and str(e["actor"]) == BERNAT:
				refused += 1
		var ai: Dictionary = sim.state.families[FERRER]["ai_state"]
		var now := "%s|%s" % [ai.get("last_order", ""), ai.get("last_fp", "")]
		if now != last and str(ai.get("last_order", "")) != "":
			given.append(str(JSON.parse_string(str(ai["last_order"]))["type"]))
		last = now
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["family"]) == FERRER:
			cats[str(e["category"])] = true
	check(not given.is_empty(), "it gave orders")
	for t: String in given:
		check(t in ALLOWED, "allowed order %s" % t)
	eq(refused, 0, "no order of the rival was refused")
	for c: String in cats:
		check(c in ["purchases", "market_sales", "contracts", "upkeep"], "gold only through its trade (%s)" % c)


func test_chooses_the_best_margin_its_craft_allows() -> void:
	var sim := _sim()
	eq(RivalAI.choose_recipe(sim, BERNAT, "bld_0002"), "forge_sword", "the sword pays best at demand 1")
	sim.state.market["demand"]["sword"] = 0.6
	eq(RivalAI.choose_recipe(sim, BERNAT, "bld_0002"), "forge_hammer", "with the sword cheap, the hammer")
	sim.state.market["demand"]["armor"] = 2.0
	check(RivalAI.choose_recipe(sim, BERNAT, "bld_0002") != "forge_armor", "armor needs craft 6")


## Fiestas (4.25.4, manager 2026-11-05): under the reserve it does not stand still; recovery mode buys just the inputs
## of one piece of its cheapest sellable recipe (with all its gold) instead of nothing.
func test_without_gold_it_stops_buying() -> void:
	var sim := _sim()
	sim.state.families[FERRER]["gold"] = 15  # under the reserve of 20
	(sim.state.buildings["bld_0002"]["inventory"]["stacks"] as Array).clear()
	var spent := 0
	for e: Dictionary in _run(sim, Clock.MINUTES_PER_DAY):
		if str(e["type"]) == "market_bought" and str(e["family"]) == FERRER:
			spent += int(e["cost"])
		check(Money.gold(sim.state, FERRER) >= 0, "never under 0")
	check(spent <= 15, "buys only what its 15 pay (%d)" % spent)
	check(Contracts.accepted_of(sim, FERRER).is_empty(), "nor takes contracts it cannot pay the inputs of")


func test_takes_a_contract_it_can_make_and_delivers_it() -> void:
	var sim := _sim()
	sim.state.clock["minute"] = 290  # just before dawn of day 0
	sim.state.characters[BERNAT]["location"] = "bld_0002"
	var inv: Dictionary = sim.state.buildings["bld_0002"]["inventory"]
	Inventory.add(inv, cat, "iron_ingot", Inventory.NORMAL, 4)
	var id := Contracts.post(sim, {"client": "carpenter", "item": "hammer", "qty": 2, "min_quality": 0,
		"deadline_days": 2})
	var scripted := Contracts.post(sim, {"client": "farmer", "item": "hammer", "qty": 1, "min_quality": 0,
		"deadline_days": 3, "script": "tutorial"})
	var accepted := ""
	var delivered := ""
	for e: Dictionary in _run(sim, 2 * Clock.MINUTES_PER_DAY):
		if str(e["type"]) == "contract_accepted" and str(e["family"]) == FERRER:
			accepted += str(e["contract"]) + " "
		if str(e["type"]) == "contract_delivered" and str(e["family"]) == FERRER:
			delivered += str(e["contract"]) + " "
	check(accepted.begins_with(id), "it accepted the hammer contract at dawn (%s)" % accepted)
	check(not scripted in accepted, "it leaves the scripted start contracts to the player")
	check(id in delivered, "and delivered it (%s)" % delivered)
	check(int(sim.state.families[FERRER]["reputation"]) >= 2, "+2 reputation")


func test_never_holds_more_contracts_than_its_profile() -> void:
	var sim := _sim()
	var most := int(cat.ai_profiles()["rival_smith"]["max_contracts"])
	var peak := 0
	for i: int in 4 * Clock.MINUTES_PER_DAY:
		sim.step()
		peak = maxi(peak, Contracts.accepted_of(sim, FERRER).size())
	check(peak <= most, "at most %d at a time (peak %d)" % [most, peak])


func test_determinism_with_the_rival() -> void:
	var a := _sim(7)
	var b := _sim(7)
	a.run_days(3)
	b.run_days(3)
	eq(a.state_hash(), b.state_hash(), "same seed, same game with the rival playing")
	check(Money.gold(a.state, FERRER) != 80 or not (a.state.market["demand"] as Dictionary).is_empty(),
		"the rival did something")


func test_save_and_load_mid_plan_goes_on_the_same() -> void:
	var sim := _sim(3)
	sim.run_minutes(Clock.MINUTES_PER_DAY + 400)  # day 2, mid-morning: walking, buying or working
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	check(not (back.families[FERRER]["ai_state"] as Dictionary).is_empty(), "its plan is in the save")
	var sim2 := Sim.new(back, cat)
	sim.run_days(2)
	sim2.run_days(2)
	eq(sim2.state_hash(), sim.state_hash(), "the loaded rival plays the same")


func test_its_memory_survives_a_save_exactly() -> void:
	# A save turns 30.0 into 30: what the AI remembers (last_fp) must not depend on the number type.
	var sim := _sim(1)
	for k: int in 12:
		sim.run_minutes(60)
		var sim2 := Sim.new(SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"], cat)
		sim.run_minutes(5)
		sim2.run_minutes(5)
		var a: Dictionary = sim.state.families[FERRER]["ai_state"]
		var b: Dictionary = sim2.state.families[FERRER]["ai_state"]
		var at := int(sim.state.clock["minute"])
		eq(str(b.get("last_fp", "")), str(a.get("last_fp", "")), "same fingerprint text after loading (minute %d)" % at)
		eq(SaveFile.canonical(b), SaveFile.canonical(a), "same memory after loading (minute %d)" % at)
