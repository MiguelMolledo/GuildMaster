class_name BotCounterShop
extends BotArtisanExpert
## Equilibrio 8 and 14 (docs/decisiones.json): the expert of the forge with the sales counter first and one employee at
## it (counter_shop = 1, max_employees = 1), keeping counter_stock pieces of each product for its customers. Measures,
## from the day the employee first stands at the counter: counter_gold_day (counter sales a day), counter_wage_day (the
## employee's wage a day), counter_ratio (sales / wage: Equilibrio 8 asks >= 2), clientele_arrived_day and
## clientele_bought_day (the countryside's customers of 04g §4.6.5.7, Equilibrio 14), counter_left_empty_share (the
## customers who left with nothing to buy). Targets: data/targets.json counter_shop.

const SHOP: String = "bld_0001"

var _cs_from: int = -1
var _cs_gold: int = 0
var _cs_wages: int = 0
var _cs_in: int = 0
var _cs_bought: int = 0
var _cs_left: int = 0
var _cs_left_empty: int = 0


func _init() -> void:
	counter_shop = 1
	max_employees = 1


func orders(sim: Sim) -> Array:
	_watch(sim)
	return super.orders(sim)


func _watch(sim: Sim) -> void:
	if _cs_from < 0:
		var srv := Counter.server_of(sim, SHOP)
		if srv != "" and sim.state.characters[srv].get("job") is Dictionary:
			_cs_from = Clock.day(int(sim.state.clock["minute"]))
		return
	var fam := _fam(sim)
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"counter_sold":
				if str(e.get("family", "")) == fam:
					_cs_gold += int(e.get("price", 0))
					if bool(e.get("clientele", false)):
						_cs_bought += 1
			"wage_paid":
				if str(e.get("family", "")) == fam:
					_cs_wages += int(e.get("amount", 0))
			"customer_arrived":
				if str(e.get("building", "")) == SHOP and bool(e.get("clientele", false)):
					_cs_in += 1
			"customer_left":
				if str(e.get("building", "")) == SHOP:
					_cs_left += 1
					if str(e.get("reason", "")) == "no_product":
						_cs_left_empty += 1


func measures(sim: Sim) -> Dictionary:
	_watch(sim)
	var days := maxi(1, Clock.day(int(sim.state.clock["minute"])) - maxi(0, _cs_from))
	return {"counter_from_day": _cs_from, "counter_gold_day": snappedf(float(_cs_gold) / days, 0.1),
		"counter_wage_day": snappedf(float(_cs_wages) / days, 0.1),
		"counter_ratio": snappedf(float(_cs_gold) / maxf(1.0, float(_cs_wages)), 0.01),
		"clientele_arrived_day": snappedf(float(_cs_in) / days, 0.01),
		"clientele_bought_day": snappedf(float(_cs_bought) / days, 0.01),
		"counter_left_empty_share": snappedf(float(_cs_left_empty) / maxf(1.0, float(_cs_left)), 0.01)}
