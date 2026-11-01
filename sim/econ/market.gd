class_name Market
extends RefCounted
## The market square (GDD 4.5.1-4.5.3, 4.5.7): buying and selling at the stalls and the armory, demand per item,
## opening hours and errands (deliveries to an own building). Owner: subgrim «mercado».
## Contract: docs/contratos/h3_mercado.md. Figures in data/market.json (Catalog.market) and data/difficulty.json.
## Gold only moves through Money.change (purchases, errands, market_sales).


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "buy", "actor", "stall", "item", "quality", "qty", "deliver_to"?: bld_id}.
static func order_buy(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "sell", "actor", "stall", "item", "quality", "qty"}.
static func order_sell(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


# --- Step ------------------------------------------------------------------------------------------------------------

## Errands that arrive this minute; demand recovery at dawn.
static func step(_sim: Sim) -> void:
	pass


# --- Queries for the UI and the AI -----------------------------------------------------------------------------------

## Whether the market is open now (data/market.json open_phases). Done in the base (pure data).
static func is_open(sim: Sim) -> bool:
	var ph := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)
	return ph in (sim.catalog.market.get("open_phases", []) as Array)


## The demand of `item` now (state.market.demand; data/market.json demand.start if nobody touched it yet).
static func demand(sim: Sim, item: String) -> float:
	var d: Dictionary = sim.state.market.get("demand", {})
	return float(d.get(item, sim.catalog.market.get("demand", {}).get("start", 1.0)))


## Unit price of `item` at `quality` now (GDD 4.5.3, phase 1). Done in the base (pure data):
##   buy  = round(base_price × quality_mult[quality] × demand × buy_price_mult of the difficulty)
##   sell = round(base_price × quality_mult[quality] × demand × sell_ratio)   (the difficulty only touches buying)
## 0 for an unknown item or quality.
static func price(sim: Sim, item: String, quality: int, side: String) -> int:
	var def := sim.catalog.item(item)
	var qm: Array = sim.catalog.market.get("quality_mult", [])
	if def.is_empty() or quality < 0 or quality >= qm.size():
		return 0
	var p := float(def.get("base_price", 0)) * float(qm[quality]) * demand(sim, item)
	if side == "buy":
		p *= float(sim.catalog.difficulty_levels(sim.state.difficulty).get("buy_price_mult", 1.0))
	else:
		p *= float(sim.catalog.market.get("sell_ratio", 0.7))
	return roundi(p)


## What `actor` can do at `stall` now: {open, reason, buy: [{item, quality, price, max_qty, status}],
## sell: [{item, quality, qty, price}], deliver_to: [bld_id]}.
static func offers(_sim: Sim, _actor: String, _stall: String) -> Dictionary:
	return {"open": false, "reason": "not_implemented", "buy": [], "sell": [], "deliver_to": []}


## The stall `actor` is at ("" if none): a map stall's service tile, or inside a shop whose type has market_stall.
static func stall_at(_sim: Sim, _actor: String) -> String:
	return ""
