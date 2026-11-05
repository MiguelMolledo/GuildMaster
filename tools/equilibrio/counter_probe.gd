extends SceneTree
## Equilibrio 8 and D16 (rama equilibrio): what the counter with one employee leaves against that employee's wage.
##   /opt/homebrew/bin/godot --headless --path . -s tools/equilibrio/counter_probe.gd -- [--seeds=5] [--days=24]
##       [--life=on] [--set=<where>=<json>]...
## The expert of the forge with counter_shop = 1 (it buys the sales counter first and puts its employee there) and at
## most one employee, in a new game (artisan_blacksmith, Normal, fixed cast). From the day the employee stands at the
## counter: counter sales per day, the employee's wage per day, the ratio, the forge's net per day, and the market demand
## of the sword at the end. Prints one JSON line per seed and the means.

const FAM: String = "fam_0001"


func _init() -> void:
	var seeds := 5
	var days := 24
	var life := false
	var sets: Array = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = a.substr(8).to_int()
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a == "--life=on":
			life = true
		elif a.begins_with("--set="):
			sets.append(a.substr(6))
	var rows: Array = []
	for s: int in range(1, seeds + 1):
		var cat := Catalog.load_from()
		cat.life_tables["life"]["enabled"] = life
		cat.festivals["enabled"] = false
		for spec: Variant in sets:
			_apply(cat, str(spec))
		var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, s)["state"], cat)
		var bot := BotArtisanExpert.new()
		bot.counter_shop = 1
		bot.max_employees = 1
		var counter_gold := 0
		var wages := 0
		var counter_days := 0
		var counted := {}
		var gold_from := -1
		var net_from := 0
		for m: int in days * Clock.MINUTES_PER_DAY:
			var ev := sim.step(bot.orders(sim))
			var at := false
			for e: Dictionary in ev:
				if str(e["type"]) == "counter_sold" and str(e.get("family", "")) == FAM:
					counter_gold += int(e["price"])
				elif str(e["type"]) == "wage_paid" and str(e.get("family", "")) == FAM and gold_from >= 0:
					wages += int(e["amount"])
			var srv := Counter.server_of(sim, "bld_0001")
			if srv != "" and sim.state.characters[srv].get("job") is Dictionary:
				at = true
			var d := Clock.day(int(sim.state.clock["minute"]))
			if at and not counted.has(d):
				counted[d] = true
				counter_days += 1
				if gold_from < 0:
					gold_from = d
					net_from = Ledger.total(sim.state, FAM)
		var span := maxi(1, days - maxi(0, gold_from))
		var row := {"seed": s, "counter_from_day": gold_from, "counter_days": counter_days,
			"counter_gold_day": snappedf(float(counter_gold) / span, 0.1), "wage_day": snappedf(float(wages) / span, 0.1),
			"ratio": snappedf(float(counter_gold) / maxf(1.0, float(wages)), 0.01),
			"net_day_after": snappedf(float(Ledger.total(sim.state, FAM) - net_from) / span, 0.1),
			"sword_demand_end": snappedf(Market.demand(sim, "sword"), 0.01), "gold_end": Money.gold(sim.state, FAM)}
		rows.append(row)
		print(JSON.stringify(row))
	var keys := ["counter_gold_day", "wage_day", "ratio", "net_day_after", "sword_demand_end"]
	var mean := {}
	for k: String in keys:
		var t := 0.0
		for r: Dictionary in rows:
			t += float(r[k])
		mean[k] = snappedf(t / maxi(1, rows.size()), 0.01)
	print("MEAN " + JSON.stringify(mean))
	quit(0)


func _apply(cat: Catalog, spec: String) -> void:
	var eq := spec.find("=")
	var keys := spec.substr(0, eq).split(".")
	var node: Variant = cat.get(keys[0])
	for k: int in range(1, keys.size() - 1):
		node = node[keys[k]]
	node[keys[keys.size() - 1]] = JSON.parse_string(spec.substr(eq + 1))
