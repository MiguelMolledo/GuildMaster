extends "res://tests/test_case.gd"
## H10 offices (GDD 4.12.3, 4.19; docs/contratos/h10_cargos.md): the inspector regulates a price and the market shows
## it (criterion of H10), salaries, taxes and the collector's commission, the fine, powers that come later, taking an
## office (chronicle and reputation), the passives and the title ceremony's approver.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"
const INSPECTOR: String = "market_inspector"
const COLLECTOR: String = "tax_collector"

var cat := Catalog.load_from()


func _inspector() -> Sim:
	return Sim.new(NewGame.from_scenario("office_inspector", 1)["state"], cat)


## Criterion of H10: the inspector regulates a price and it shows in the market (buy, sell and the stall's offer).
func test_inspector_regulates_a_price_and_the_market_shows_it() -> void:
	var sim := _inspector()
	var st := sim.state
	var sell0 := Market.price(sim, "sword", 0, "sell")
	var buy0 := Market.price(sim, "iron", 0, "buy")
	var raw_sell := float(cat.item("sword")["base_price"]) * float(cat.market["quality_mult"][0]) \
		* Market.demand(sim, "sword") * float(cat.market["sell_ratio"])
	var r := Orders.apply(sim, {"type": "use_office_power", "actor": HERO, "power": "regulate_price",
		"args": {"item": "sword", "percent": 10}})
	check(r["ok"], "regulate swords +10 %% (%s)" % r["reason"])
	eq(Market.price(sim, "sword", 0, "sell"), roundi(raw_sell * 1.1), "the market pays 10 % more for swords")
	check(Market.price(sim, "sword", 0, "sell") > sell0, "more than before (%d > %d)" % [Market.price(sim, "sword", 0,
		"sell"), sell0])
	eq(Market.price(sim, "iron", 0, "buy"), buy0, "other items do not move")
	eq(Offices.regulation(sim, "sword"), 10, "in force")
	eq(Offices.power_status(sim, HERO, "regulate_price", {"item": "iron", "percent": -10}), "power_cooldown",
		"one regulation per season")
	st.offices[INSPECTOR]["seats"][0]["cooldowns"] = {}
	eq(Offices.power_status(sim, HERO, "regulate_price", {"item": "sword", "percent": -10}), "already_regulated",
		"one regulation per item")
	eq(Offices.power_status(sim, HERO, "regulate_price", {"item": "iron", "percent": 30}), "bad_args", "only ±10 %")
	check(Orders.apply(sim, {"type": "use_office_power", "actor": HERO, "power": "regulate_price",
		"args": {"item": "iron", "percent": -10}})["ok"], "iron −10 %")
	check(Market.price(sim, "iron", 0, "buy") < buy0, "iron is cheaper to buy")
	var n := 0
	for nt: Dictionary in st.notices:
		if str(nt.get("key", "")) == "notice.price_regulated":
			n += 1
	eq(n, 2, "the human family is told")
	st.clock["minute"] = int(st.clock["minute"]) + 2 * Clock.MINUTES_PER_DAY
	eq(Offices.regulation(sim, "sword"), 0, "after 2 days the regulation ends")
	eq(Market.price(sim, "sword", 0, "sell"), roundi(raw_sell), "the price is back")


func test_regulated_sale_pays_more() -> void:
	var a := _inspector()
	var b := _inspector()
	Orders.apply(b, {"type": "use_office_power", "actor": HERO, "power": "regulate_price",
		"args": {"item": "sword", "percent": 10}})
	var got: Array = []
	for sim: Sim in [a, b]:
		var st := sim.state
		Inventory.add(st.characters[HERO]["inventory"], cat, "sword", 0, 1)
		st.characters[HERO]["location"] = st.characters[HERO]["location"]
		got.append(Market.trade_price(sim, HERO, "armory", "sword", 0, "sell"))
	check(int(got[1]) > int(got[0]), "the armory pays more for a regulated sword (%d > %d)" % [got[1], got[0]])


func test_salary_at_dawn() -> void:
	var sim := _inspector()
	var st := sim.state
	var gold := Money.gold(st, FAM)
	while Clock.phase(int(st.clock["minute"]), cat.time) != "dawn":
		sim.step([])
	var paid := 0
	for e: Dictionary in st.ledger["entries"]:
		if str(e["family"]) == FAM and str(e["category"]) == Money.OFFICES:
			paid += int(e["amount"])
	eq(paid, int(cat.offices()[INSPECTOR]["salary"]), "the inspector's salary (2/day, ledger offices)")
	check(gold > 0, "sanity")
	var judge: String = Offices.holders(sim, "judge")[0]
	var jf := str(st.characters[judge]["family"])
	var jpaid := 0
	for e: Dictionary in st.ledger["entries"]:
		if str(e["family"]) == jf and str(e["category"]) == Money.OFFICES and str(e["ref"]) == "office_judge":
			jpaid += int(e["amount"])
	eq(jpaid, 5, "the NPC judge is paid too")


func test_taxes_and_commission() -> void:
	var sim := _inspector()
	var st := sim.state
	Offices.leave(sim, INSPECTOR, 0, "term")
	Offices.take(sim, COLLECTOR, 0, HERO)
	eq(Offices.tax_percent(sim), 5, "a collector: 5 % by default")
	check(Orders.apply(sim, {"type": "use_office_power", "actor": HERO, "power": "set_tax", "args": {"percent": 10}})["ok"],
		"sets 10 %")
	eq(Offices.tax_percent(sim), 10, "10 %")
	eq(Offices.power_status(sim, HERO, "set_tax", {"percent": 20}), "power_cooldown", "cooldown first")
	st.offices[COLLECTOR]["seats"][0]["cooldowns"] = {}
	eq(Offices.power_status(sim, HERO, "set_tax", {"percent": 20}), "bad_args", "5-15 %")
	Money.change(sim, RIVAL_FAM, 200, Money.MARKET_SALES, "sell", "", RIVAL)
	Money.change(sim, FAM, 100, Money.COUNTER_SALES, "counter", "", HERO)
	var rg := Money.gold(st, RIVAL_FAM)
	var hg := Money.gold(st, FAM)
	st.clock["minute"] = (Offices.today(sim) + 1) * Clock.MINUTES_PER_DAY
	while Clock.phase(int(st.clock["minute"]), cat.time) != "dawn":
		sim.step([])
	var taxes := {}
	var commission := 0
	for e: Dictionary in st.ledger["entries"]:
		if str(e["category"]) == Money.TAXES:
			taxes[str(e["family"])] = int(taxes.get(str(e["family"]), 0)) + int(e["amount"])
		if str(e["category"]) == Money.OFFICES and str(e["ref"]) == "tax_commission":
			commission += int(e["amount"])
	eq(int(taxes.get(RIVAL_FAM, 0)), -20, "the rival pays 10 % of its sales of the day before")
	eq(int(taxes.get(FAM, 0)), -10, "the collector's family pays too")
	eq(commission, 2, "5 % of the 30 collected, to the collector's family")
	check(Money.gold(st, RIVAL_FAM) <= rg - 20, "out of the rival's purse")
	check(hg > 0, "sanity")


func test_fine_and_powers_that_come_later() -> void:
	var sim := _inspector()
	var st := sim.state
	var g := Money.gold(st, RIVAL_FAM)
	check(Orders.apply(sim, {"type": "use_office_power", "actor": HERO, "power": "fine_merchant",
		"args": {"family": RIVAL_FAM}})["ok"], "fines the rival smith")
	eq(Money.gold(st, RIVAL_FAM), g - mini(20, g), "20 gold (fines)")
	var home: String = ""
	for f: String in st.families:
		if TownLife.is_household(st, f):
			home = f
			break
	st.offices[INSPECTOR]["seats"][0]["cooldowns"] = {}
	eq(Offices.power_status(sim, HERO, "fine_merchant", {"family": home}), "not_a_merchant", "a household has no business")
	eq(Offices.power_status(sim, HERO, "fine_merchant", {"family": FAM}), "bad_args", "not one's own family")
	var judge: String = Offices.holders(sim, "judge")[0]
	eq(Offices.power_status(sim, judge, "pardon", {}), "not_banished", "H11: pardons are ready (nobody banished)")
	eq(Offices.power_status(sim, RIVAL, "regulate_price", {}), "not_office_holder", "no office, no powers")
	eq(Offices.power_status(sim, HERO, "set_tax", {"percent": 10}), "unknown_power", "not an inspector's power")
	var ps := Offices.powers(sim, HERO)
	eq(ps.map(func(p: Dictionary) -> String: return str(p["power"])), ["regulate_price", "fine_merchant"], "the panel")
	check(Orders.is_management("use_office_power"), "powers are management orders (the panel)")


func test_taking_an_office() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_campaign", 1)["state"], cat)
	var st := sim.state
	var rep := Reputation.of(st, FAM)
	Offices.take(sim, INSPECTOR, 0, HERO)
	eq(Reputation.of(st, FAM), rep + 5, "a minor office: +5 reputation (4.12.1)")
	var facts := st.chronicle.filter(func(f: Dictionary) -> bool: return str(f.get("kind", "")) == "office_won")
	eq(facts.size(), 1, "office_won in the chronicle")
	eq(str(facts[0].get("data", facts[0]).get("rank", "")), "minor", "a minor office for the dynasty score")
	eq(int(Dynasty.score(sim, FAM)["by_kind"].get("office_won", 0)), 30, "30 points (4.17: minor office)")
	eq(Offices.reputation_with_class(sim, FAM, "artisan"), roundi(Reputation.with_class(st, FAM, "artisan") * 1.1),
		"the inspector's passive: +10 % with the artisans")
	eq(Offices.reputation_with_class(sim, FAM, "scholar"), Reputation.with_class(st, FAM, "scholar"), "not the scholars")
	eq(Elections.run_status(sim, HERO, COLLECTOR, "basic"), "holds_office", "one office per person")


func test_the_ceremony_needs_the_mayor() -> void:
	var sim := Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)
	sim.step([])  # the government is handed out: no mayor nor councillors in town, approved by itself (as in H9)
	eq(Titles.status(sim, HERO)["reason"], "", "vacant approvers: he can ask")
	var st := sim.state
	var judge: String = Offices.holders(sim, "judge")[0]
	st.offices["mayor"]["seats"][0]["holder"] = judge
	eq(Titles.status(sim, HERO)["reason"], "title_not_approved", "a mayor with no affinity says no")
	Courtship.relation(st, judge, HERO)["affinity"] = 30
	eq(Titles.status(sim, HERO)["reason"], "", "affinity 30: yes (4.12.2)")
