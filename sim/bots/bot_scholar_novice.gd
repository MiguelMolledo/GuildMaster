class_name BotScholarNovice
extends BotArtisanTrade
## H12.2 (docs/gdd/04d_otras_clases.md 4.22.5.8): the novice of the scholar's start (scholar_physician), a sensible
## physician. Criterion 1 of H12 (each profession has a bot that earns money with it): scholar_novice in
## tools/sim_runner.gd, its targets in data/targets.json (goldflow.start_physician, the band of the forge's start).
## It keeps BotArtisanTrade's habits (the debt paid early keeping DEBT_RESERVE, the trips to the board and the stalls
## while the market is open, the upkeep kept when buying) and works the Consulta instead of a workshop:
##   price:    on the first day it asks PRICE_MULT × the reference for the consultation (set_service_price: the
##             objective «change the price», and 4.22.3.2 pays a little more for fewer patients).
##   patients: a waiting patient first: a grave one (severity over the consultation's) with a surgery it may do (salve
##             and Arcane), else the consultation; it never throws away a cycle under way at the mortar.
##   bandages: without patients, bandages at the mortar while it has fewer than the patients' RESERVE + the board's
##             contracts + MAX_HELD to sell; else it waits at the cot.
##   trips:    as the trade's: cloth at the materials stall, a SALVE when it has none and SALVE_GOLD, the bandages
##             over the reserve to the apothecary's stall, the board's bandage contracts.
## Only real orders, read through the same queries as the UI (Services.waiting / has_client, Production.recipe_options).

const VISIT: String = "doctor_visit"
const SURGERY: String = "doctor_surgery"
const BANDAGES: String = "doctor_bandages"
const COT: String = "cot"
const RESERVE: int = 4               # bandages kept for the patients (one per consultation)
const PRICE_MULT: float = 1.25       # the consultation's price over the reference (20 -> 25)
const SALVE_GOLD: int = 90           # gold at which it buys a salve for a grave patient

var _priced: bool = false


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not _priced and st.characters.has(ACTOR) and st.buildings.has(BLD) and st.ending.is_empty():
		_priced = true
		var ref := int(Services.cfg(sim, "doctor").get("ref_price", 20))
		return [{"type": "set_service_price", "actor": ACTOR, "building": BLD, "service": "doctor",
			"price": roundi(float(ref) * PRICE_MULT)}]
	return super.orders(sim)


func _learn(sim: Sim) -> void:
	super._learn(sim)
	if not _raw.has("salve"):
		_raw.append("salve")
		_raw.sort()


## A service job waiting for a patient is not a cycle under way: the bot may switch or go out.
func _busy(sim: Sim) -> bool:
	var job := _job(sim)
	if job.is_empty():
		return false
	if bool(job.get("service", false)):
		return str(job.get("client", "")) != ""
	return super._busy(sim)


func _job(sim: Sim) -> Dictionary:
	var zone := Production.job_zone(sim, ACTOR, BLD)
	if zone == "":
		return {}
	var job: Variant = sim.state.buildings[BLD]["zones"][zone].get("job")
	return job if job is Dictionary else {}


## The station work wanted now: a patient, the bandages it lacks, or waiting at the cot.
func _wanted(sim: Sim) -> Dictionary:
	var rs: Dictionary = sim.catalog.recipes()
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	if rs.has(SURGERY) and Services.has_client(sim, BLD, rs[SURGERY]) and not Services.has_client(sim, BLD, rs[VISIT]) \
			and _status(sim, COT, SURGERY) == "ok":
		return {"zone": COT, "recipe": SURGERY, "mode": "normal"}
	if Services.has_client(sim, BLD, rs[VISIT]) and _status(sim, COT, VISIT) == "ok":
		return {"zone": COT, "recipe": VISIT, "mode": "normal"}
	var want := RESERVE + MAX_HELD
	for c: Dictionary in _contracts_by_due(sim):
		if str(c["item"]) == "bandages":
			want += int(c["qty"])
	if Inventory.count(inv, "bandages") < want and _status(sim, _zone(sim, BANDAGES), BANDAGES) == "ok":
		return {"zone": _zone(sim, BANDAGES), "recipe": BANDAGES, "mode": "normal"}
	return {}  # nothing to do: it waits at the cot (_work) and may go out to buy or sell (_plan_trip, idle)


func _work(sim: Sim) -> Dictionary:
	var w := _wanted(sim)
	var job := _job(sim)
	if w.is_empty():
		if job.is_empty() and _status(sim, COT, VISIT) == "ok":
			w = {"zone": COT, "recipe": VISIT, "mode": "normal"}  # waits for the next patient at the cot
		else:
			return {}
	if not job.is_empty():
		if str(job["recipe"]) == str(w["recipe"]):
			return {}
		if bool(job.get("service", false)):
			if str(job.get("client", "")) != "":
				return {}  # a patient under way
		elif not _fresh(sim, job):
			return {}  # never throws away a cycle under way
	return {"type": "work_at", "actor": ACTOR, "building": BLD, "zone": w["zone"], "recipe": w["recipe"],
		"mode": w["mode"]}


## The bandages over the patients' reserve go to the stall.
func _to_sell(sim: Sim) -> Array:
	var out: Array = []
	for s: Dictionary in super._to_sell(sim):
		if str(s["item"]) == "bandages":
			var n := int(s["qty"]) - RESERVE
			if n > 0:
				out.append({"item": "bandages", "quality": int(s["quality"]), "qty": n})
			continue
		out.append(s)
	return out


func _sellable_in_bag(sim: Sim) -> Array:
	return super._sellable_in_bag(sim)


## The cloth of the bandages it will make and, for a grave patient, one salve.
func _raw_needs(sim: Sim) -> Dictionary:
	var need := super._raw_needs(sim)
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	var want := RESERVE + MAX_HELD
	for c: Dictionary in _contracts_by_due(sim):
		if str(c["item"]) == "bandages":
			want += int(c["qty"])
	var cloth := Inventory.count(inv, "cloth") + Inventory.count(bag, "cloth")
	for d: Dictionary in Market.pending(sim, _fam(sim)):
		if str(d["item"]) == "cloth":
			cloth += int(d["qty"])
	var short := want - Inventory.count(inv, "bandages") - Inventory.count(bag, "bandages")
	var cloth_need := ceili(float(maxi(0, short)) / 3.0) - cloth
	var gold := Money.gold(sim.state, _fam(sim)) - _kept(sim) - int(sim.catalog.buildings().get(_type, {}).get("upkeep", 0))
	if cloth_need > 0 and gold > 0:
		var price := maxi(1, Market.price(sim, "cloth", Inventory.NORMAL, "buy"))
		need["cloth"] = maxi(int(need.get("cloth", 0)), mini(cloth_need, gold / price))
	if Inventory.count(inv, "salve") + Inventory.count(bag, "salve") == 0 and Money.gold(sim.state, _fam(sim)) >= SALVE_GOLD \
			and int(sim.state.characters[ACTOR]["stats"].get("arcane", 0)) >= int(sim.catalog.recipes()[SURGERY].get("min_stat", 1)):
		need["salve"] = 1
	if int(need.get("cloth", 0)) <= 0:
		need.erase("cloth")
	return need
