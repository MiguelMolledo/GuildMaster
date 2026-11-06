extends "res://tests/test_case.gd"
## Equilibrio 2 (docs/decisiones.json; GDD 4.16): a game never dies. With no gold nor goods the moneylender offers an
## emergency loan; upkeep debt over its threshold seizes a good that is not the home; with nothing to seize, ruin.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


## A new forge game with its start loan paid, no gold and nothing in the storage nor the bags.
func _broke() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	for id: String in st.loans:
		st.loans[id]["state"] = Loans.PAID
		st.loans[id]["outstanding"] = 0
	Money.change(sim, FAM, -Money.gold(st, FAM), Money.PURCHASES, "test")
	for b: String in st.buildings:
		if Money.family_of(st, b) == FAM:
			st.buildings[b]["inventory"]["stacks"] = []
	for c: Variant in st.families[FAM]["members"]:
		st.characters[str(c)]["inventory"]["stacks"] = []
		st.characters[str(c)]["equipment"] = {}
	st.deliveries = []
	return sim


func _has_notice(sim: Sim, key: String) -> bool:
	for n: Dictionary in sim.state.notices:
		if str(n.get("key", "")) == key:
			return true
	return false


func _to_next_dawn(sim: Sim) -> void:
	var day := Clock.day(int(sim.state.clock["minute"]))
	while Clock.day(int(sim.state.clock["minute"])) == day or not Ledger.is_dawn(sim):
		sim.run_minutes(1)


func test_offer_and_take() -> void:
	var sim := _broke()
	var st := sim.state
	check(Emergency.stock_value(sim, FAM) < 20, "nothing in stock")
	var offer := Emergency.offer_of(sim, FAM)
	eq(int(offer.get("amount", 0)), 60, "the offer stands")
	eq(int(offer.get("owed", 0)), 90, "dear: +50 %")
	sim.run_minutes(61)
	check(_has_notice(sim, "notice.emergency_offer"), "the notice says it")
	var r := Orders.apply(sim, {"type": "take_emergency_loan", "actor": HERO})
	eq(r["ok"], true, "taken")
	eq(Money.gold(st, FAM), 60, "the gold comes in")
	var found := ""
	for id: String in Loans.of_family(sim, FAM):
		if str(st.loans[id].get("kind", "")) == "emergency":
			found = id
	check(found != "", "an emergency loan is open")
	eq(int(st.loans[found]["outstanding"]), 90, "owed with its interest")
	eq(Orders.apply(sim, {"type": "take_emergency_loan", "actor": HERO})["reason"], "no_emergency", "one at a time")


func test_not_offered_with_gold_or_goods() -> void:
	var sim := _broke()
	Money.change(sim, FAM, 40, Money.MARKET_SALES, "test")
	check(Emergency.offer_of(sim, FAM).is_empty(), "40 gold is not broke")
	Money.change(sim, FAM, -40, Money.PURCHASES, "test")
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "sword", 0, 1)
	check(Emergency.offer_of(sim, FAM).is_empty(), "a sword to sell is not broke")


func test_upkeep_debt_seizes_a_good_not_the_home() -> void:
	var sim := _broke()
	var st := sim.state
	(Region.ensure(sim)["carts"] as Dictionary)[FAM] = 1
	st.buildings[FORGE]["upkeep_debt"] = 90
	_to_next_dawn(sim)
	eq(Caravans.carts(sim, FAM), 0, "the cart is seized (90 + the day's upkeep reach 100)")
	eq(str(st.buildings[FORGE].get("owner", "")), FAM, "never the home")
	check(st.ending.is_empty(), "the game goes on")
	check(_has_notice(sim, "notice.seized_cart"), "the notice says it")


func test_nothing_to_seize_is_ruin() -> void:
	var sim := _broke()
	var st := sim.state
	st.buildings[FORGE]["upkeep_debt"] = 90
	_to_next_dawn(sim)
	eq(str(st.ending.get("kind", "")), "ruin", "ruin with its end screen")


func test_emergency_loan_unpaid_seizes_before_ruin() -> void:
	var sim := _broke()
	var st := sim.state
	Orders.apply(sim, {"type": "take_emergency_loan", "actor": HERO})
	Money.change(sim, FAM, -Money.gold(st, FAM), Money.PURCHASES, "test")
	(Region.ensure(sim)["carts"] as Dictionary)[FAM] = 1
	var id := ""
	for l: String in Loans.of_family(sim, FAM):
		id = l
	st.loans[id]["due_minute"] = int(st.clock["minute"]) + 5
	sim.run_minutes(10)
	eq(str(st.loans[id]["state"]), Loans.EXTENDED, "first the extension")
	st.loans[id]["due_minute"] = int(st.clock["minute"]) + 5
	st.buildings[FORGE]["upkeep_debt"] = 0
	sim.run_minutes(10)
	eq(Caravans.carts(sim, FAM), 0, "then a good")
	check(st.ending.is_empty(), "not the ruin")


func test_roundtrip() -> void:
	var sim := _broke()
	Orders.apply(sim, {"type": "take_emergency_loan", "actor": HERO})
	var d := SaveFile.from_text(JSON.stringify(sim.state.to_dict()))
	eq(d["ok"], true, "loads")
	var st2: WorldState = d["state"]
	eq(SaveFile.canonical(st2.to_dict()), SaveFile.canonical(sim.state.to_dict()), "same state")
