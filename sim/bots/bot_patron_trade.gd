class_name BotPatronTrade
extends BotArtisanTrade
## H12 Patrón (docs/gdd/04d_otras_clases.md 4.22.4.9): the novice of the patron's other trades (miller_novice,
## baker_novice, butcher_novice in tools/sim_runner.gd, from their starts patron_<trade>): BotArtisanTrade's habits,
## with the stock it keeps counted in batches, not in units (a batch of bread is five loaves, a pig six cuts of meat:
## MAX_HELD batches of the recipe's output), and an intermediate that a stall buys is also sold (the butcher's meat:
## cut for the sausages and sold as it is). Everything else as the trade's novice.


func _learn(sim: Sim) -> void:
	super._learn(sim)
	for item: String in _inter:
		var rid := str(_inter[item])
		if _stall_of(sim, item) != "" and not rid in _products:
			_products.append(rid)
	_products.sort()


func _best_market_recipe(sim: Sim) -> String:
	var best := ""
	var best_rate := 0.0
	for rid: String in _products:
		if _status(sim, _zone(sim, rid), rid) in ["locked", ""]:
			continue
		var out := _output(sim, rid)
		var batch := maxi(1, int(sim.catalog.recipes()[rid].get("output", {}).get("qty", 1)))
		if _stall_of(sim, out) == "" or _held(sim, out) >= MAX_HELD * batch:
			continue
		var rate := _margin(sim, rid) / _hours(sim, rid, "normal")
		if rate > best_rate + 0.000001:
			best_rate = rate
			best = rid
	return best


## Sell price of a unit at the demand left after selling what it holds (each unit drops it by its demand_weight) − a
## unit's raw materials.
func _margin(sim: Sim, rid: String) -> float:
	var item := _output(sim, rid)
	var drop := 0.04 * sim.catalog.demand_weight(item)
	var d := maxf(Market.demand(sim, item) - drop * _held(sim, item), 0.5)
	var sell := float(sim.catalog.item(item).get("base_price", 0)) * d * float(sim.catalog.market.get("sell_ratio", 0.7))
	var raw := {}
	_add_raw(sim, rid, raw)
	var cost := 0.0
	for it: String in raw:
		cost += Market.price(sim, it, Inventory.NORMAL, "buy") * int(raw[it])
	return sell - cost
