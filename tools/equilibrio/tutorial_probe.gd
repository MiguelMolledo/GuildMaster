extends SceneTree
## The tutorial route (BotTutorialRoute) in the default game, measured: the ledger by category in 10 days, the gold
## each dawn, the day the debt is paid, the most gold, the stock left (iron, ingots, swords) and the swords sold.
##   /opt/homebrew/bin/godot --headless --path . -s tools/equilibrio/tutorial_probe.gd -- [--seeds=1,2,3]
##       [--difficulty=normal] [--days=10] [--set=<table>.<key>...=<json>]...
## One JSON line per seed and MEAN with the means.

const FAM: String = "fam_0001"


func _init() -> void:
	var seeds: Array = [11]
	var diff := "normal"
	var days := 10
	var sets: Array = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = Array(a.substr(8).split(",")).map(func(x: String) -> int: return x.to_int())
		elif a.begins_with("--difficulty="):
			diff = a.substr(13)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--set="):
			sets.append(a.substr(6))
	var rows: Array = []
	for s: int in seeds:
		var cat := Catalog.load_from()
		for spec: Variant in sets:
			_apply(cat, str(spec))
		var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", diff, {"cast": "fixed"}, s)["state"], cat)
		var bot := BotTutorialRoute.new()
		var gold_by_day: Array = []
		var paid_day := -1
		var max_gold := 0
		var sold := 0
		var ruin := -1
		for m: int in days * Clock.MINUTES_PER_DAY:
			var ev := sim.step(bot.orders(sim))
			for e: Dictionary in ev:
				match str(e["type"]):
					"loan_repaid":
						if str(e.get("family", "")) == FAM and paid_day < 0:
							paid_day = Clock.day(int(sim.state.clock["minute"])) + 1
					"market_sold":
						if str(e.get("family", "")) == FAM and str(e.get("item", "")) == "sword":
							sold += int(e.get("qty", 1))
			if Ledger.is_dawn(sim):
				gold_by_day.append(Money.gold(sim.state, FAM))
			max_gold = maxi(max_gold, Money.gold(sim.state, FAM))
			if not sim.state.ending.is_empty() and ruin < 0:
				ruin = Clock.day(int(sim.state.clock["minute"])) + 1
		var by_cat := {}
		for e: Dictionary in sim.state.ledger.get("entries", []):
			if str(e.get("family", "")) == FAM:
				var c := str(e["category"])
				by_cat[c] = int(by_cat.get(c, 0)) + int(e["amount"])
		var inv: Dictionary = sim.state.buildings["bld_0001"]["inventory"]
		var row := {"seed": s, "paid_day": paid_day, "max_gold": max_gold, "gold_end": Money.gold(sim.state, FAM),
			"ruin_day": ruin, "swords_sold": sold, "by_cat": by_cat, "gold_dawn": gold_by_day,
			"stock_end": {"iron": Inventory.count(inv, "iron"), "ingot": Inventory.count(inv, "iron_ingot"),
				"coal": Inventory.count(inv, "coal"), "sword": Inventory.count(inv, "sword")},
			"loans": Loans.of_family(sim, FAM).map(func(id: String) -> String: return str(Loans.status(sim, id)["state"]))}
		rows.append(row)
		print("ROW " + JSON.stringify(row))
	var paid := rows.filter(func(r: Dictionary) -> bool: return int(r["paid_day"]) > 0 and int(r["paid_day"]) <= 8).size()
	var mean_gold := 0.0
	for r: Dictionary in rows:
		mean_gold += float(r["gold_end"])
	print("MEAN " + JSON.stringify({"paid_by_8": "%d/%d" % [paid, rows.size()], "gold_end": mean_gold / maxi(1, rows.size())}))
	quit(0)


func _apply(cat: Catalog, spec: String) -> void:
	var eq := spec.find("=")
	var keys := spec.substr(0, eq).split(".")
	var node: Variant = cat.get(keys[0])
	for k: int in range(1, keys.size() - 1):
		node = node[keys[k]]
	node[keys[keys.size() - 1]] = JSON.parse_string(spec.substr(eq + 1))
