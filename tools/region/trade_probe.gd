extends SceneTree
## Caravan and quota economics against selling at home (Equilibrio 7 follow-up): from a real game state, what N swords
## give sold at home now (the town's demand as it is, each unit lowering it) and what they give in a city by caravan
## (its price and tariff, the tolls of both ways, the cart's upkeep for the days away and the chance of losing the cargo
## to an ambush on the way out), and what a quota treaty gives a season against the same swords at home.
##   godot --headless --path . -s tools/region/trade_probe.gd -- [--scenario=travel_start] [--city=capital]
##       [--home-demand=<d>] [--qty=4,8,12]
## Read only: every figure is taken on copies of the state.

func _init() -> void:
	var scenario := "travel_start"
	var city := "capital"
	var home_d := -1.0
	var qtys := [4, 8, 12]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="): scenario = a.substr(11)
		elif a.begins_with("--city="): city = a.substr(7)
		elif a.begins_with("--home-demand="): home_d = a.substr(14).to_float()
		elif a.begins_with("--qty="): qtys = Array(a.substr(6).split(",")).map(func(x: String) -> int: return x.to_int())
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario(scenario, 1)
	if not r["ok"]:
		print("trade_probe: %s" % r["error"])
		quit(2)
		return
	var base := Sim.new(r["state"], cat)
	var fam := str(base.state.characters["chr_0001"]["family"])
	if home_d >= 0.0:
		if not base.state.market.get("demand") is Dictionary:
			base.state.market["demand"] = {}
		base.state.market["demand"]["sword"] = home_d
	var path := Region.path(base, Region.home(base), city)
	var tolls := 0
	var hours := 0.0
	var p_keep := 1.0
	for rid: String in path:
		var rt := Region.route(base, rid)
		tolls += int(rt.get("toll", 0))
		hours += Region.leg_minutes(base, rt) / 60.0
		p_keep *= 1.0 - float(rt.get("risk", 0)) * float(cat.trade.get("travel", {}).get("ambush_per_risk", 0.04))
	var cv: Dictionary = cat.trade.get("caravans", {})
	var away_days := (2.0 * hours + float(cv.get("stay_hours", 2))) / 24.0
	var upkeep := roundi(ceilf(away_days) * float(cv.get("cart_upkeep", 2)))
	print("trade_probe: %s -> %s: %s, %.1f h each way, tolls %d each way, keeps the cargo %.0f %% of the time, %d of upkeep; home sword demand %.2f, %s demand %.2f, tariff %.0f %%" % [
		Region.home(base), city, path, hours, tolls, p_keep * 100.0, upkeep, Market.demand(base, "sword"), city,
		Region.demand(base, city, "sword"), Region.tariff(base, city, fam) * 100.0])
	for q: int in [Inventory.NORMAL, Inventory.GOOD]:
		for n: int in qtys:
			var home := Market.sell_preview(base, "chr_0001", "armory", "sword", q, n)
			var away := Sim.new(WorldState.from_dict(base.state.to_dict()), cat)
			var s := CityTrade.sell_units(away, city, fam, "sword", q, n)
			var net := roundi(float(s["total"]) * p_keep) - 2 * tolls - upkeep
			print("  %d swords (quality %d): home now %d (%d..%d each) · %s %d (tariff %d), expected after the road %d -> %+d (%+.0f %%)" % [
				n, q, int(home["total"]), int(home["prices"][0]), int(home["prices"][-1]), city, int(s["total"]),
				int(s["tariff"]), net, net - int(home["total"]), 100.0 * (net - int(home["total"])) / maxf(1.0, float(home["total"]))])
	var k: Dictionary = cat.trade.get("treaties", {}).get("kinds", {}).get("quota", {})
	var qn := int(k.get("qty", 4))
	var qp := roundi(float(cat.item("sword").get("base_price", 0)) * float(k.get("price_mult", 1.0)))
	var seasons := int(k.get("seasons", 4))
	var home_q := Market.sell_preview(base, "chr_0001", "armory", "sword", Inventory.NORMAL, qn)
	var per := roundi(float(qn * qp) * p_keep) - 2 * tolls - upkeep
	print("  quota: %d swords a season at %d (no tariff) over %d seasons, fee %d, penalty %d: a season %d after the road against %d at home now (%+d); the treaty %+d over its %d seasons" % [
		qn, qp, seasons, int(k.get("fee", 0)), int(k.get("penalty", 0)), per, int(home_q["total"]),
		per - int(home_q["total"]), seasons * (per - int(home_q["total"])) - int(k.get("fee", 0)), seasons])
	quit(0)
