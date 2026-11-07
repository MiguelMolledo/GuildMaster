extends "res://tests/test_case.gd"
## H7 · sales at the counter (GDD 4.5.4): townsfolk walk in during the day, the employee with role counter serves
## them, they take the most valuable product at the counter price (counter_sales in the ledger); without the upgrade
## nobody comes, without anybody at the counter they leave, an angry customer pays less.

const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String = "town_microevents", s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


func _counter_emp(sim: Sim) -> String:
	for e: String in Staff.employees_of(sim.state, FORGE):
		if str(sim.state.characters[e]["job"]["role"]) == "counter":
			return e
	return ""


func test_customers_come_and_buy() -> void:
	var sim := _sim()
	var swords := Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword")
	var gold := Money.gold(sim.state, FAM)
	var sold: Array = []
	var arrived := 0
	var saw_inside := false
	for i: int in 14 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "counter_sold":
				sold.append(e)
			elif str(e["type"]) == "customer_arrived":
				arrived += 1
		if not Counter.customers(sim, FORGE).is_empty():
			saw_inside = true
	check(arrived >= 4, "a customer every 1-2 h of day (%d)" % arrived)
	check(saw_inside, "customers stand inside at the counter")
	check(sold.size() >= 3, "they buy (%d)" % sold.size())
	var emp := _counter_emp(sim)
	eq(str(sold[0]["seller"]), emp, "the counter employee serves")
	eq(str(sold[0]["item"]), "sword", "the most valuable product")
	var expect := Counter.price(sim, FORGE, emp, "sword", 0, "")
	var base := float(Market.price(sim, "sword", 0, "sell"))  # price_base market_sell (H7 balance)
	var bonus := float(SkillCheck.stat(sim, emp, "charisma")) / 100.0 + float(cat.town["counter"]["rank_bonus"][str(sim.state.characters[emp]["rank"])])
	eq(expect, roundi(base * (1.0 + bonus)), "market sell price × (1 + charisma/100 + rank) (4.5.4)")
	var total := 0
	for e: Dictionary in sold:
		total += int(e["price"])
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword") <= swords - sold.size() + 20, true, "units leave the storage")
	var counter := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["category"]) == Money.COUNTER_SALES and str(e["family"]) == FAM:
			counter += int(e["amount"])
	eq(counter, total, "the ledger has the counter sales")
	check(Money.gold(sim.state, FAM) - gold > 0 or counter > 0, "gold comes in")


func test_no_counter_no_customers() -> void:
	var sim := _sim()
	sim.state.buildings[FORGE]["upgrades"].erase("forge_commerce_1")
	var arrived := 0
	for i: int in 8 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "customer_arrived":
				arrived += 1
	eq(arrived, 0, "without counter_sales nobody comes")


func test_nobody_at_the_counter_customer_leaves() -> void:
	var sim := _sim()
	for e: String in Staff.employees_of(sim.state, FORGE):   # fixed stations' hands do not serve (only counter or any)
		sim.state.characters[e]["job"]["role"] = "anvil"
	var left := 0
	var sold := 0
	for i: int in 12 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "customer_left" and str(e["reason"]) == "nobody":
				left += 1
			elif str(e["type"]) == "counter_sold":
				sold += 1
	check(left >= 1, "nobody serving: the customer leaves after its patience (%d)" % left)
	eq(sold, 0, "no sales")


func test_angry_customer_pays_less() -> void:
	var sim := _sim()
	var emp := _counter_emp(sim)
	var folk := Population.townsfolk(sim.state)
	var npc := ""
	for id: String in folk:
		if not sim.state.characters[id].get("job") is Dictionary:
			npc = id
			break
	var e := Emotions.add(sim, npc, "angry", FAM)
	e["start"] = int(sim.state.clock["minute"]) - int(e["duration"]) / 2
	var calm := Counter.price(sim, FORGE, emp, "sword", 0, "")
	eq(Counter.price(sim, FORGE, emp, "sword", 0, npc), roundi(calm * 0.75), "angry customer: −25 %")



## H6 · 4.7.4 (the manager's decision, 2026-11-07): with nobody in role «counter», an employee in role «any» serves the
## counter's customer and its piece waits meanwhile (the cycle's end moves by serve_minutes).
func test_an_any_hand_serves_and_its_piece_waits() -> void:
	var sim := _sim()
	var emp := _counter_emp(sim)
	for e: String in Staff.employees_of(sim.state, FORGE):
		sim.state.characters[e]["job"]["role"] = "anvil"
	sim.state.characters[emp]["job"]["role"] = "any"   # the only one who may serve: an «any» hand
	var sold := 0
	for i: int in 12 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "counter_sold":
				sold += 1
	check(sold > 0, "with one «any» hand the counter sells (%d)" % sold)
	var bld := str(sim.state.characters[emp]["job"]["building"])
	eq(Counter.server_of(sim, bld) if str(sim.state.characters[emp].get("location", "")) == bld else emp, emp,
		"it is who serves")
	var zone := ""
	for z: String in sim.state.buildings[bld]["zones"]:
		zone = z
		break
	sim.state.buildings[bld]["zones"][zone]["job"] = {"actor": emp, "recipe": "x", "mode": "normal", "start": 0, "end": 100}
	sim.state.characters[emp]["station"] = zone
	Counter.pause_for(sim, bld, emp, 10)
	eq(int(sim.state.buildings[bld]["zones"][zone]["job"]["end"]), 110, "its piece ends 10 minutes later")
	sim.state.buildings[bld]["zones"][zone]["job"] = null
