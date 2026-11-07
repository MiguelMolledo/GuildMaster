class_name Fields
extends RefCounted
## The fields of a farm (H12 Patrón, docs/gdd/04d_otras_clases.md 4.22.4.1, P1/P2): a field is a station of kind
## "field" (zone_kind: the building's zones with "like": "field", and the upgrades' new ones) worked with the recipes
## of kind "field" (action plow | sow | harvest) through the same work_at as every station. Crops: data/crops/<id>.json.
##
## State: buildings[bld].fields[zone] = {state, crop, growth, ready_day, sown_day, yield_mult} (read with defaults:
## a field with no entry is fallow; no save version).
##   fallow --plow--> plowed --sow (takes the seed: the recipe's inputs)--> growing
##   growing --(each dawn: growth += the crop's growth[season], from the day after sowing)--> ready (growth >= grow)
##   ready --harvest (the crop's yield into the storage)--> fallow
##   ready --(rot_days dawns without harvest)--> rotten --plow--> plowed
## The yield: crop.yield.qty × yield_mult × the field_yield upgrades × WorldEvents.production_mult (famine ×0.5, a good
## harvest ×1.5) × the difficulty's harvest_mult (good land or poor), rounded; the second day of ready ×
## late_harvest_mult (0.75). No quality (normal).
## Speed: the recipe's duration / (1 + (stat − 5) × per_point) of who works it (constitution: the field tires); the
## recipe's tool equipped (the hoe for plowing) × tool_speed. Employees do not work the fields at night (the rule of
## 4.4.3 for every station); the family does.
## Notices to the owner family: ready (warning; urgent on its last day), the last sowing day of a season with fields
## not sown, rotten. Figures: data/crops/*.json and data/buildings/farm.json "fields" [balance].

const FIELD: String = "field"
const STATES: Array[String] = ["fallow", "plowed", "growing", "ready", "rotten"]


static func is_field(recipe: Dictionary) -> bool:
	return str(recipe.get("kind", "craft")) == FIELD


## The field stations of `bld`, sorted.
static func zones(sim: Sim, bld: String) -> Array:
	var out: Array = []
	var b: Dictionary = sim.state.buildings.get(bld, {})
	for z: String in (b.get("zones", {}) as Dictionary).keys():
		if Upgrades.zone_kind(sim, bld, z) == FIELD:
			out.append(z)
	out.sort()
	return out


## Whether `bld` has fields.
static func has_fields(sim: Sim, bld: String) -> bool:
	return not zones(sim, bld).is_empty()


## The state of field `zone` of `bld` (created fallow the first time it is written).
static func field(st: WorldState, bld: String, zone: String) -> Dictionary:
	var b: Dictionary = st.buildings[bld]
	if not b.get("fields") is Dictionary:
		b["fields"] = {}
	var f: Dictionary = b["fields"]
	if not f.get(zone) is Dictionary:
		f[zone] = blank()
	return f[zone]


static func blank() -> Dictionary:
	return {"state": "fallow", "crop": "", "growth": 0.0, "ready_day": -1, "sown_day": -1, "yield_mult": 1.0}


## The field read only (a blank fallow one if it has no entry).
static func peek(st: WorldState, bld: String, zone: String) -> Dictionary:
	var f: Variant = st.buildings.get(bld, {}).get("fields", {})
	if f is Dictionary and (f as Dictionary).get(zone) is Dictionary:
		return f[zone]
	return blank()


static func _cfg(sim: Sim, bld: String) -> Dictionary:
	var t := str(sim.state.buildings.get(bld, {}).get("type", ""))
	return sim.catalog.buildings().get(t, {}).get("fields", {})


## "" if `recipe` (kind field) can start now at field `zone` of `bld`, else the reason: field_not_fallow (plow needs a
## fallow or rotten field), field_not_plowed, not_sowing_season, unknown_crop (sow), field_not_ready, storage_full
## (harvest: the yield would not fit; it would block the station).
static func reason(sim: Sim, bld: String, zone: String, recipe: Dictionary) -> String:
	var f := peek(sim.state, bld, zone)
	var s := str(f.get("state", "fallow"))
	match str(recipe.get("action", "")):
		"plow":
			return "" if s in ["fallow", "rotten"] else "field_not_fallow"
		"sow":
			if s != "plowed":
				return "field_not_plowed"
			var crop: Dictionary = sim.catalog.crops().get(str(recipe.get("crop", "")), {})
			if crop.is_empty():
				return "unknown_crop"
			if not _season(sim) in (crop.get("sow_seasons", []) as Array):
				return "not_sowing_season"
			return ""
		"harvest":
			if s != "ready":
				return "field_not_ready"
			var y := harvest_of(sim, bld, zone)
			if not y.is_empty() and not Inventory.can_add(sim.state.buildings[bld]["inventory"], sim.catalog,
					str(y["item"]), Inventory.NORMAL, int(y["qty"])):
				return "storage_full"
			return ""
	return "unknown_action"


## The speed factor of `actor` working `recipe`: 1 + (stat − 5) × per_point (at least min_speed), × tool_speed with
## the recipe's tool in the tool slot.
static func speed(sim: Sim, actor: String, bld: String, recipe: Dictionary) -> float:
	var cfg := _cfg(sim, bld)
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var stat := str(recipe.get("stat", "constitution"))
	var v := 1.0 + (int(ch.get("stats", {}).get(stat, 5)) - 5) * float(cfg.get("speed_per_point", 0.05))
	v = maxf(v, float(cfg.get("min_speed", 0.5)))
	var tool := str(recipe.get("tool", ""))
	var eq: Variant = ch.get("equipment", {}).get("tool")
	if tool != "" and eq is Dictionary and str(eq.get("item", "")) == tool:
		v *= float(recipe.get("tool_speed", 1.25))
	return v


## What harvesting field `zone` now would give: {item, qty} ({} if it is not ready or its crop is unknown).
static func harvest_of(sim: Sim, bld: String, zone: String) -> Dictionary:
	var f := peek(sim.state, bld, zone)
	if str(f.get("state", "")) != "ready":
		return {}
	var crop: Dictionary = sim.catalog.crops().get(str(f.get("crop", "")), {})
	if crop.is_empty():
		return {}
	var y: Dictionary = crop.get("yield", {})
	var item := str(y.get("item", ""))
	var q := float(y.get("qty", 0)) * float(f.get("yield_mult", 1.0)) * Upgrades.mult(sim, bld, "field_yield") \
		* WorldEvents.production_mult(sim, item) \
		* float(sim.catalog.difficulty_levels(sim.state.difficulty).get("harvest_mult", 1.0))
	if _today(sim) - int(f.get("ready_day", _today(sim))) >= 1:
		q *= float(crop.get("late_harvest_mult", 0.75))
	return {"item": item, "qty": maxi(0, roundi(q))}


## A finished cycle of `recipe` at field `zone`: plow and sow change the field; harvest is applied by Production once
## its yield is in the storage (harvested). Emits field_worked.
static func worked(sim: Sim, bld: String, zone: String, actor: String, recipe: Dictionary) -> void:
	var f := field(sim.state, bld, zone)
	var action := str(recipe.get("action", ""))
	match action:
		"plow":
			var keep := float(f.get("yield_mult", 1.0))
			f.merge(blank(), true)
			f["state"] = "plowed"
			f["yield_mult"] = keep
		"sow":
			f["state"] = "growing"
			f["crop"] = str(recipe.get("crop", ""))
			f["growth"] = 0.0
			f["ready_day"] = -1
			f["sown_day"] = _today(sim)
	_emit(sim, bld, zone, actor, action, f)


## The yield of a harvest went into the storage: the field goes back to fallow.
static func harvested(sim: Sim, bld: String, zone: String, actor: String, qty: int) -> void:
	var f := field(sim.state, bld, zone)
	var crop := str(f.get("crop", ""))
	f.merge(blank(), true)
	_emit(sim, bld, zone, actor, "harvest", f, {"crop": crop, "qty": qty})


static func _emit(sim: Sim, bld: String, zone: String, actor: String, action: String, f: Dictionary,
		extra: Dictionary = {}) -> void:
	var e := {"type": "field_worked", "building": bld, "zone": zone, "actor": actor, "action": action,
		"family": str(sim.state.buildings[bld].get("owner", "")), "state": str(f["state"]), "crop": str(f.get("crop", ""))}
	e.merge(extra, true)
	sim.events.append(e)
	if OS.is_debug_build():
		print("[Fields] %s %s el campo %s/%s (estado=%s, cultivo=%s %s)" % [actor, action, bld, zone, f["state"],
			f.get("crop", ""), str(extra)])


# --- Dawn ------------------------------------------------------------------------------------------------------------

## At dawn: the crops grow by the new day's season, the ready ones count their days and rot; the notices.
static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var today := _today(sim)
	var season := _season(sim)
	var ids: Array = st.buildings.keys()
	ids.sort()
	for bld: String in ids:
		var fz := zones(sim, bld)
		if fz.is_empty():
			continue
		var fam := str(st.buildings[bld].get("owner", ""))
		var unsown := 0
		for zone: String in fz:
			var f := peek(st, bld, zone)
			match str(f.get("state", "fallow")):
				"growing":
					_grow(sim, bld, zone, today, season, fam)
				"ready":
					_age(sim, bld, zone, today, fam)
				"fallow", "plowed":
					unsown += 1
		_sowing_notice(sim, bld, fam, unsown, today)


static func _grow(sim: Sim, bld: String, zone: String, today: int, season: String, fam: String) -> void:
	var f := field(sim.state, bld, zone)
	if int(f.get("sown_day", -1)) >= today:
		return  # sown today (before dawn): it starts growing tomorrow
	var crop: Dictionary = sim.catalog.crops().get(str(f.get("crop", "")), {})
	if crop.is_empty():
		return
	f["growth"] = float(f.get("growth", 0.0)) + float(crop.get("growth", {}).get(season, 0.0))
	if float(f["growth"]) + 0.0001 >= float(crop.get("grow", 1)):
		f["state"] = "ready"
		f["ready_day"] = today
		sim.events.append({"type": "field_ready", "building": bld, "zone": zone, "crop": str(f["crop"]), "family": fam})
		_notice(sim, fam, Notices.WARNING, "notice.field_ready", {"building": bld, "zone": zone,
			"item": _yield_item(sim, str(f["crop"])), "days": int(crop.get("rot_days", 2))}, bld)
	if OS.is_debug_build():
		print("[Fields] %s/%s crece (%s): %.1f de %s (estado=%s)" % [bld, zone, season, float(f["growth"]),
			crop.get("grow", 1), f["state"]])


static func _age(sim: Sim, bld: String, zone: String, today: int, fam: String) -> void:
	var f := field(sim.state, bld, zone)
	var crop: Dictionary = sim.catalog.crops().get(str(f.get("crop", "")), {})
	var rot := int(crop.get("rot_days", 2))
	var days := today - int(f.get("ready_day", today))
	if days >= rot:
		var c := str(f["crop"])
		f["state"] = "rotten"
		sim.events.append({"type": "field_rotten", "building": bld, "zone": zone, "crop": c, "family": fam})
		_notice(sim, fam, Notices.URGENT, "notice.field_rotten", {"building": bld, "zone": zone,
			"item": _yield_item(sim, c)}, bld)
		if OS.is_debug_build():
			print("[Fields] %s/%s: se pudre el %s (listo el día %d)" % [bld, zone, c, int(f["ready_day"])])
	elif days == rot - 1:
		_notice(sim, fam, Notices.URGENT, "notice.field_last_day", {"building": bld, "zone": zone,
			"item": _yield_item(sim, str(f["crop"]))}, bld)


## On the last day of a season in which some crop is sown and the next one is not a sowing season for it: «the
## sowing ends today: N fields not sown» (the fields fallow or plowed).
static func _sowing_notice(sim: Sim, bld: String, fam: String, unsown: int, today: int) -> void:
	if unsown <= 0:
		return
	var time := sim.catalog.time
	var dps := int(time["days_per_season"])
	if (today + 1) % dps != 0:
		return  # not the last day of the season
	var season := _season(sim)
	var next := Clock.season((today + 1) * Clock.MINUTES_PER_DAY, time)
	for cid: String in _sorted(sim.catalog.crops()):
		var sows: Array = sim.catalog.crops()[cid].get("sow_seasons", [])
		if season in sows and not next in sows:
			_notice(sim, fam, Notices.WARNING, "notice.sowing_ends", {"building": bld, "count": unsown,
				"item": _yield_item(sim, cid)}, bld)
			return


## The item a crop gives (the name the notices show: «el trigo»).
static func _yield_item(sim: Sim, crop: String) -> String:
	return str(sim.catalog.crops().get(crop, {}).get("yield", {}).get("item", crop))


static func _notice(sim: Sim, fam: String, sev: String, key: String, params: Dictionary, target: String) -> void:
	if fam != "" and sim.state.families.has(fam):
		Notices.add(sim, fam, sev, key, params, target)


# --- Sales -----------------------------------------------------------------------------------------------------------

## What `fam` gets at the market for `item` × this: the market_price upgrades (the Commerce branch) of its building that
## makes it: its farm for a farm good (a crop's yield, an animal, what an animal produces), the mill for its flour. 1
## with no such upgrade.
static func sale_mult(sim: Sim, fam: String, item: String) -> float:
	if fam == "":
		return 1.0
	var best := 1.0
	var farm_good := is_farm_good(sim, item)
	for b: String in _sorted(sim.state.buildings):
		if str(sim.state.buildings[b].get("owner", "")) != fam:
			continue
		var makes := farm_good and (has_fields(sim, b) or Herds.has_pen(sim, b))
		if not makes:  # the patron's other trades (the mill's flour): what the building's recipes make
			var t := str(sim.state.buildings[b].get("type", ""))
			for r: Dictionary in sim.catalog.recipes().values():
				if str(r.get("building", "")) == t and str(r.get("output", {}).get("item", "")) == item:
					makes = true
					break
		if makes:
			best = maxf(best, Upgrades.mult(sim, b, "market_price"))
	return best


static func is_farm_good(sim: Sim, item: String) -> bool:
	if sim.catalog.animals().has(item):
		return true
	for a: Variant in sim.catalog.animals().values():
		if (a as Dictionary).get("produce") is Dictionary and str(a["produce"].get("item", "")) == item:
			return true
	for c: Variant in sim.catalog.crops().values():
		if str((c as Dictionary).get("yield", {}).get("item", "")) == item:
			return true
	return false


# --- View ------------------------------------------------------------------------------------------------------------

## Every field of `bld` for the UI and the bots: [{zone, state, crop, growth, grow, days_to_ready (-1 if not growing),
## days_left (to harvest before it rots, -1 if not ready), harvest {item, qty} (if ready)}].
static func view(sim: Sim, bld: String) -> Array:
	var out: Array = []
	for zone: String in zones(sim, bld):
		var f := peek(sim.state, bld, zone)
		var crop: Dictionary = sim.catalog.crops().get(str(f.get("crop", "")), {})
		var row := {"zone": zone, "state": str(f.get("state", "fallow")), "crop": str(f.get("crop", "")),
			"growth": float(f.get("growth", 0.0)), "grow": float(crop.get("grow", 0)), "days_to_ready": -1,
			"days_left": -1, "harvest": harvest_of(sim, bld, zone)}
		if row["state"] == "growing":
			row["days_to_ready"] = days_to_ready(sim, f)
		elif row["state"] == "ready":
			row["days_left"] = int(crop.get("rot_days", 2)) - (_today(sim) - int(f.get("ready_day", _today(sim))))
		out.append(row)
	return out


## The dawns until a growing field is ready, by the calendar (-1 if it never would in a year).
static func days_to_ready(sim: Sim, f: Dictionary) -> int:
	var crop: Dictionary = sim.catalog.crops().get(str(f.get("crop", "")), {})
	if crop.is_empty():
		return -1
	var g := float(f.get("growth", 0.0))
	var need := float(crop.get("grow", 1))
	var today := _today(sim)
	var start := maxi(today, int(f.get("sown_day", today)))
	var time := sim.catalog.time
	for n: int in range(1, Clock.days_per_year(time) + 1):
		var d := start + n
		if d <= today:
			continue
		g += float(crop.get("growth", {}).get(Clock.season(d * Clock.MINUTES_PER_DAY, time), 0.0))
		if g + 0.0001 >= need:
			return d - today
	return -1


## What sowing `crop` today would give: the days until it is ready (-1 if it is not a sowing season), for the
## calendar.
static func sow_preview(sim: Sim, crop_id: String) -> int:
	var crop: Dictionary = sim.catalog.crops().get(crop_id, {})
	if crop.is_empty() or not _season(sim) in (crop.get("sow_seasons", []) as Array):
		return -1
	return days_to_ready(sim, {"crop": crop_id, "growth": 0.0, "sown_day": _today(sim)})


static func _today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


static func _season(sim: Sim) -> String:
	return Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
