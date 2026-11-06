class_name BotPatronNovice
extends BotArtisanTrade
## H12 Patrón (docs/gdd/04d_otras_clases.md 4.22.4.9, the bot «farmer»): the novice of the patron's start
## (patron_farmer), a sensible farmer. Criterion 1 of H12 (each profession has a bot that earns money with it):
## patron_novice in tools/sim_runner.gd, its targets in data/targets.json (goldflow.start_farmer, the band of the
## forge's start; no animal starved; the debt paid). It keeps BotArtisanTrade's habits (the debt paid early keeping
## DEBT_RESERVE, the trips to the board and the stalls while the market is open, the upkeep kept when buying) and
## works the Granja instead of a workshop:
##   fields:   a ready field first (the one that rots soonest), then a plowed one in a sowing season with the seed,
##             then a fallow or rotten one to plow; while one waits to be harvested or sown it does not go out.
##   wheat:    keeps the seed of the fields to sow (5 a field), the winter feed of the pen (a head a day of winter
##             left) and the board's wheat contracts; sells the rest from autumn on (the wheat is cheap in spring and
##             summer, 1.5 in winter) or when it needs the gold for the debt; buys the seed it lacks. It never sells
##             the flock nor next year's seed to pay: a famine year (or Hard's debt) may end in the extension of 4.16.
##   animals:  sells the wool every trip, the pigs over a breeding pair; from year 2 (SHEEP_DAY), with the debt
##             paid and SHEEP_GOLD, buys two sheep at the livestock stall (sent to the pen, the objective «buy two
##             sheep»): the herd grows once the first year is safe.
##   contracts: takes the board's wheat and wool contracts it can serve from the stock (and the wool to come).
## Only real orders, read through the same queries as the UI (Fields.view, Herds.view, Production.recipe_options).

const PLOW: String = "farm_plow"
const SOW: String = "farm_sow_wheat"
const HARVEST: String = "farm_harvest"
const SEED_PER_FIELD: int = 5
const KEEP_PIGS: int = 2            # the breeding pair
const SHEEP_GOLD: int = 220         # gold (after the debt) at which it buys two sheep
const SHEEP_DAY: int = 8            # from the first day of year 2 (the herd grows after the first year's accounts)
const LIVESTOCK: String = "livestock"

var _sheep_bought: bool = false


func _learn(sim: Sim) -> void:
	super._learn(sim)
	_raw = ["sheep", "wheat"]


# --- Fields ----------------------------------------------------------------------------------------------------------

func _wanted(sim: Sim) -> Dictionary:
	var rows := Fields.view(sim, BLD)
	var ready: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["state"]) == "ready")
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["days_left"]) < int(b["days_left"]) or (int(a["days_left"]) == int(b["days_left"])
			and str(a["zone"]) < str(b["zone"])))
	for r: Dictionary in ready:
		if _status(sim, str(r["zone"]), HARVEST) == "ok":
			return {"zone": str(r["zone"]), "recipe": HARVEST, "mode": "normal"}
	for r: Dictionary in rows:
		if str(r["state"]) == "plowed" and _status(sim, str(r["zone"]), SOW) == "ok":
			return {"zone": str(r["zone"]), "recipe": SOW, "mode": "normal"}
	for r: Dictionary in rows:
		if str(r["state"]) in ["fallow", "rotten"] and _status(sim, str(r["zone"]), PLOW) == "ok":
			return {"zone": str(r["zone"]), "recipe": PLOW, "mode": "normal"}
	return {}


## A harvest or a sowing waiting (with its seed) keeps it home.
func _may_leave(sim: Sim) -> bool:
	if not super._may_leave(sim):
		return false
	var w := _wanted(sim)
	return w.is_empty() or str(w["recipe"]) == PLOW


func _work(sim: Sim) -> Dictionary:
	var w := _wanted(sim)
	if w.is_empty() or Production.job_zone(sim, ACTOR, BLD) != "":
		return {}  # a field cycle under way ends by itself (it never repeats)
	return {"type": "work_at", "actor": ACTOR, "building": BLD, "zone": w["zone"], "recipe": w["recipe"],
		"mode": "normal"}


# --- Stock -----------------------------------------------------------------------------------------------------------

## The wheat it keeps: the seed of the fields still to sow, the pen's winter feed left and the wheat contracts.
func _wheat_kept(sim: Sim) -> int:
	var keep := 0
	for r: Dictionary in Fields.view(sim, BLD):
		if str(r["state"]) in ["fallow", "plowed", "rotten"]:
			keep += SEED_PER_FIELD
	keep += _winter_feed_left(sim)
	for c: Dictionary in _contracts_by_due(sim):
		if str(c["item"]) == "wheat":
			keep += int(c["qty"])
	return keep


## The pen's wheat for the winter days still to come this year (none before autumn: the harvest brings it).
func _winter_feed_left(sim: Sim) -> int:
	var time := sim.catalog.time
	var season := Clock.season(_now(sim), time)
	if not season in ["autumn", "winter"]:
		return 0
	var per_day := int(Herds.feed_per_day(sim, BLD, "winter").get("wheat", 0))
	var days := 0
	var dpy := Clock.days_per_year(time)
	for n: int in range(1, dpy):
		var s := Clock.season((_today(sim) + n) * Clock.MINUTES_PER_DAY, time)
		if s == "winter":
			days += 1
		elif days > 0:
			break
	if season == "winter":
		days += 0  # today's feed was eaten at dawn
	return per_day * (days + 1)  # a day of margin


func _wheat_held(sim: Sim) -> int:
	return Inventory.count(sim.state.buildings[BLD]["inventory"], "wheat") \
		+ Inventory.count(sim.state.characters[ACTOR]["inventory"], "wheat")


func _is_product(_sim: Sim, item: String) -> bool:
	return item in ["wheat", "wool", "pig"]


## What it sells now: the wool, the pigs over the pair, the wheat over what it keeps (from autumn, or for the debt).
func _to_sell(sim: Sim) -> Array:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	var out: Array = []
	var wool := Inventory.count(inv, "wool") - _contract_qty(sim, "wool")
	if wool > 0:
		out.append({"item": "wool", "quality": Inventory.NORMAL, "qty": wool})
	var pigs := Inventory.count(inv, "pig") - KEEP_PIGS
	if pigs > 0:
		out.append({"item": "pig", "quality": Inventory.NORMAL, "qty": pigs})
	var wheat := Inventory.count(inv, "wheat") - maxi(0, _wheat_kept(sim) - Inventory.count(
		sim.state.characters[ACTOR]["inventory"], "wheat"))
	if wheat > 0 and (WorldEvents.price_mult(sim, "wheat") >= 1.0 - 0.0001 or _needs_cash(sim)):
		out.append({"item": "wheat", "quality": Inventory.NORMAL, "qty": wheat})
	return out


func _sellable_in_bag(sim: Sim) -> Array:
	var out: Array = []
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for item: String in ["pig", "wheat", "wool"]:
		var n := Inventory.count(bag, item) - _bag_kept(sim, item)
		if n > 0:
			out.append({"item": item, "quality": Inventory.NORMAL, "qty": n})
	return out


## What of `item` in the bag is not for sale (the contracts' and, for the wheat, what it keeps beyond the storage).
func _bag_kept(sim: Sim, item: String) -> int:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	match item:
		"wheat":
			return maxi(0, _wheat_kept(sim) - Inventory.count(inv, "wheat"))
		"wool":
			return maxi(0, _contract_qty(sim, "wool") - Inventory.count(inv, "wool"))
	return 0


func _contract_qty(sim: Sim, item: String) -> int:
	var n := 0
	for c: Dictionary in _contracts_by_due(sim):
		if str(c["item"]) == item:
			n += int(c["qty"])
	return n


## The debt falls due in two days and the gold does not cover it: the wheat goes whatever the season.
func _needs_cash(sim: Sim) -> bool:
	return _kept(sim) > Money.gold(sim.state, _fam(sim))


## Sells the whole lot of an item at once (the wheat comes by the dozen).
func _stop_sell(sim: Sim, stall: String, loc: String) -> Dictionary:
	if not Market.is_open(sim):
		return {}
	for s: Dictionary in _sellable_in_bag(sim):
		if _stall_of(sim, str(s["item"])) != stall:
			continue
		var go := _go_stall(sim, stall, loc)
		if not go.is_empty():
			return go
		return {"type": "sell", "actor": ACTOR, "stall": stall, "item": s["item"], "quality": Inventory.NORMAL,
			"qty": int(s["qty"])}
	return {}


## The seed it lacks for the fields to sow (in a sowing season or the one before) and, once, two sheep.
func _raw_needs(sim: Sim) -> Dictionary:
	var need := {}
	var fam := _fam(sim)
	var gold := Money.gold(sim.state, fam) - _kept(sim) - int(sim.catalog.buildings().get(_type, {}).get("upkeep", 0))
	var pending := 0
	var sheep_coming := 0
	for d: Dictionary in Market.pending(sim, fam):
		if str(d["item"]) == "wheat":
			pending += int(d["qty"])
		elif str(d["item"]) == "sheep":
			sheep_coming += int(d["qty"])
	var short := _wheat_kept(sim) - _wheat_held(sim) - pending
	if short > 0 and gold > 0:
		var price := maxi(1, Market.price(sim, "wheat", Inventory.NORMAL, "buy"))
		need["wheat"] = mini(short, gold / price)
		gold -= int(need["wheat"]) * price
		if int(need["wheat"]) <= 0:
			need.erase("wheat")
	if not _sheep_bought and sheep_coming == 0 and _today(sim) >= SHEEP_DAY and _debt_paid(sim) and gold >= SHEEP_GOLD \
			and Herds.head_count(sim, BLD) + 2 <= Herds.capacity(sim, BLD):
		need["sheep"] = 2
	return need


func _debt_paid(sim: Sim) -> bool:
	for id: String in Loans.of_family(sim, _fam(sim)):
		if str(Loans.status(sim, id)["state"]) in ["active", "extended"]:
			return false
	return true


## The animals walk to the pen (errand with no surcharge); the seed, by hand or sent.
func _stop_buy(sim: Sim, stall: String, loc: String) -> Dictionary:
	if stall != LIVESTOCK:
		return super._stop_buy(sim, stall, loc)
	if not Market.is_open(sim):
		return {}
	var need := _raw_needs(sim)
	if not need.has("sheep"):
		return {}
	var go := _go_stall(sim, stall, loc)
	if not go.is_empty():
		return go
	var n := mini(int(need["sheep"]), Market.max_buy(sim, ACTOR, stall, "sheep", Inventory.NORMAL, BLD))
	if n <= 0:
		return {}
	_sheep_bought = true
	return {"type": "buy", "actor": ACTOR, "stall": stall, "item": "sheep", "quality": Inventory.NORMAL, "qty": n,
		"deliver_to": BLD}


# --- Contracts -------------------------------------------------------------------------------------------------------

## A wheat contract it can serve from the wheat over what it keeps; a wool one with the wool it has and the sheep give
## before the deadline.
func _can_make_in_time(sim: Sim, c: Dictionary) -> bool:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	var qty := int(c["qty"])
	match str(c["item"]):
		"wheat":
			return _wheat_held(sim) - _wheat_kept(sim) >= qty
		"wool":
			var days := maxi(0, int(c.get("deadline_days", 1)) - 1)
			return Inventory.count(inv, "wool") - _contract_qty(sim, "wool") + Inventory.count(inv, "sheep") * days >= qty
	return false
