class_name Production
extends RefCounted
## Work cycles at stations, quality, work modes and master touch (GDD 4.4, D11). Owner: subgrim «produccion».
## Contract: docs/contratos/h2_forja.md. Figures in data/production.json (Catalog.production) and data/recipes/.
##
## A job lives in state.buildings[bld].zones[zone].job:
##   {actor, recipe, mode, start, end, inputs: [{item, quality, qty}], window: [start, end] | null, touched: bool,
##    result: null | {item, quality, qty}, blocked: bool}
## Minutes are absolute clock minutes. The inputs are taken from the building storage when the cycle starts; the
## output enters it when the cycle ends (quality rolled then). If the output does not fit, the job keeps its result,
## the station is blocked (event station_blocked) and it retries every minute. After delivering, the cycle repeats
## on its own while the actor stays at the station, has no queued orders (active pause, GDD 4.1), may work and the
## inputs and room are there.
## Interrupting (stop_work, leaving the station or the building) returns what the job holds (D11): inputs, or the
## finished result of a blocked job, to the storage; what does not fit to the actor's inventory; what does not fit
## there either to the "floor" of the station: zones[zone].floor = [{item, quality, qty}] (nobody picks it up yet).
## H4 (subgrim «cola», docs/contratos/h4_empleados.md): an employee's cycle lasts duration / rank speed and gives
## max(1, round(qty × efficiency)) units; it does not repeat on its own: WorkQueue.cycle_done is told and the queue
## hands the next work.

const NIGHT: String = "night"


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "work_at", "actor", "building", "zone", "recipe", "mode"}. Puts the actor at the station if it is free.
## Working again at the station where the actor already works restarts the cycle with the new recipe/mode (the
## inputs of the running cycle come back first, D11). Working at another station of the building leaves the old one.
static func order_work_at(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld_id := str(o.get("building", ""))
	var zone := str(o.get("zone", ""))
	var recipe_id := str(o.get("recipe", ""))
	var mode := str(o.get("mode", "normal"))
	var why := _inside_reason(sim, actor, bld_id)
	if why != "":
		return Orders.fail(why)
	var ch: Dictionary = st.characters[actor]
	var bld: Dictionary = st.buildings[bld_id]
	var zones: Dictionary = bld.get("zones", {})
	if not zones.has(zone):
		return Orders.fail("unknown_station")
	var occupant := str(zones[zone].get("occupant", ""))
	if occupant != "" and occupant != actor:
		return Orders.fail("station_busy")
	var recipe: Dictionary = sim.catalog.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return Orders.fail("unknown_recipe")
	if str(recipe.get("building", "")) != str(bld.get("type", "")) \
			or str(recipe.get("zone", "")) != Upgrades.zone_kind(sim, bld_id, zone):
		return Orders.fail("wrong_station")  # H5: an upgrade's new station works as its `like` (anvil_2 -> anvil)
	if not _modes(sim).has(mode):
		return Orders.fail("unknown_mode")
	if mode != "normal" and _is_employee_at(sim, actor, bld_id):
		return Orders.fail("mode_not_allowed")  # H4: employees work in normal mode, without master touch (4.4.5)
	if str(bld.get("state", "normal")) != "normal":
		return Orders.fail("building_not_ready")
	why = may_work(sim, actor, bld_id)
	if why != "":
		return Orders.fail(why)
	why = _lock_reason(sim, ch, bld, recipe)
	if why != "":
		return Orders.fail(why)
	why = _stock_reason(sim.catalog, _storage_after_returns(sim, actor, bld_id), recipe)
	if why != "":
		return Orders.fail(why)
	# Valid: leave the current job (D11), take the station, start.
	var working := job_zone(sim, actor, bld_id)
	if working != "":
		interrupt(sim, bld_id, working)
	if str(ch.get("station", "")) != zone:
		var old := str(ch.get("station", ""))
		if zones.has(old) and str(zones[old].get("occupant", "")) == actor:
			zones[old]["occupant"] = ""
		zones[zone]["occupant"] = actor
		ch["station"] = zone
		sim.events.append({"type": "station_taken", "actor": actor, "building": bld_id, "zone": zone})
	_start_cycle(sim, bld_id, zone, actor, recipe_id, mode)
	return Orders.ok()


## {"type": "stop_work", "actor"}: interrupts the actor's job (D11). The actor stays at the station.
static func order_stop_work(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	if not sim.state.characters.has(actor):
		return Orders.fail("unknown_actor")
	var bld_id := str(sim.state.characters[actor].get("location", ""))
	var zone := job_zone(sim, actor, bld_id)
	if zone == "":
		return Orders.fail("not_working")
	interrupt(sim, bld_id, zone)
	return Orders.ok()


## {"type": "master_touch", "actor", "building", "zone"}: only in careful mode, inside the cycle's window, by the
## actor working at that station, once per cycle (GDD 4.4.5).
static func order_master_touch(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld_id := str(o.get("building", ""))
	var zone := str(o.get("zone", ""))
	var why := _inside_reason(sim, actor, bld_id)
	if why != "":
		return Orders.fail(why)
	var zones: Dictionary = st.buildings[bld_id].get("zones", {})
	if not zones.has(zone):
		return Orders.fail("unknown_station")
	if str(st.characters[actor].get("station", "")) != zone:
		return Orders.fail("not_at_station")
	var job: Variant = zones[zone].get("job")
	if not job is Dictionary or str(job["actor"]) != actor or job.get("result") is Dictionary:
		return Orders.fail("not_working")
	if not bool(_modes(sim)[str(job["mode"])].get("master_touch", false)):
		return Orders.fail("not_careful")
	if not window_open(job, int(st.clock["minute"])):
		return Orders.fail("no_window")
	if bool(job.get("touched", false)):
		return Orders.fail("already_touched")
	job["touched"] = true
	sim.events.append({"type": "master_touch_done", "actor": actor, "building": bld_id, "zone": zone})
	if OS.is_debug_build():
		print("[Production] %s da el toque de maestro en %s/%s" % [actor, bld_id, zone])
	return Orders.ok()


## Cost of `qty` units of a raw material in the old provisional purchase of H2 (the buy_raw order, retired in H3 for
## the market's buy). Kept only for the view until it moves to Market.offers.
static func raw_cost(catalog: Catalog, item: String, qty: int) -> int:
	var markup := float(catalog.production.get("raw_purchase_markup", 1.0))
	return ceili(float(catalog.item(item).get("base_price", 0)) * markup * qty - 0.0001)


# --- Step ------------------------------------------------------------------------------------------------------------

## One minute of every running job: master-touch window events, end of cycle (quality), delivery or block,
## auto-repeat. A job whose actor is no longer at its station is interrupted (D11).
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	for bld_id: String in _sorted_keys(st.buildings):
		var zones: Dictionary = st.buildings[bld_id].get("zones", {})
		for zone: String in _sorted_keys(zones):
			if zones[zone].get("job") is Dictionary:
				_step_job(sim, bld_id, zone, now)


static func _step_job(sim: Sim, bld_id: String, zone: String, now: int) -> void:
	var st := sim.state
	var bld: Dictionary = st.buildings[bld_id]
	var z: Dictionary = bld["zones"][zone]
	var job: Dictionary = z["job"]
	var actor := str(job["actor"])
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or str(ch.get("location", "")) != bld_id \
			or str(ch.get("station", "")) != zone:
		interrupt(sim, bld_id, zone)
		return
	var w: Variant = job.get("window")
	if w is Array and not job.get("result") is Dictionary:
		if now == int(w[0]) and int(w[1]) > int(w[0]):
			sim.events.append({"type": "master_window", "building": bld_id, "zone": zone, "open": true})
		elif now == int(w[1]) and int(w[1]) > int(w[0]):
			sim.events.append({"type": "master_window", "building": bld_id, "zone": zone, "open": false})
	if not job.get("result") is Dictionary:
		if now < int(job["end"]):
			return
		var recipe: Dictionary = sim.catalog.recipes()[str(job["recipe"])]
		var out: Dictionary = recipe["output"]
		var q := roll_quality(sim, actor, str(bld["type"]), str(job["mode"]), bool(job.get("touched", false)), bld_id)
		job["result"] = {"item": str(out["item"]), "quality": q, "qty": output_units(sim, actor, bld_id, recipe)}
	var res: Dictionary = job["result"]
	var inv: Dictionary = bld["inventory"]
	if not Inventory.add(inv, sim.catalog, str(res["item"]), int(res["quality"]), int(res["qty"])):
		if not bool(job.get("blocked", false)):
			job["blocked"] = true
			sim.events.append({"type": "station_blocked", "building": bld_id, "zone": zone, "reason": "storage_full"})
			if OS.is_debug_build():
				print("[Production] %s/%s bloqueado: almacén lleno (%s)" % [bld_id, zone, res["item"]])
		return
	sim.events.append({"type": "work_done", "actor": actor, "building": bld_id, "zone": zone, "item": res["item"],
		"quality": int(res["quality"]), "qty": int(res["qty"])})
	if OS.is_debug_build():
		print("[Production] %s termina %s en %s/%s (calidad=%d, modo=%s, toque=%s)" % [actor, res["item"], bld_id, zone,
			int(res["quality"]), job["mode"], job.get("touched", false)])
	z["job"] = null
	if _is_employee_at(sim, actor, bld_id):
		# H4: an employee does not repeat on its own; the queue hands it the next work (WorkQueue.step).
		WorkQueue.cycle_done(sim, bld_id, zone, actor, str(job["recipe"]), int(res["qty"]))
		return
	_repeat_or_idle(sim, bld_id, zone, actor, str(job["recipe"]), str(job["mode"]))


static func _repeat_or_idle(sim: Sim, bld_id: String, zone: String, actor: String, recipe_id: String,
		mode: String) -> void:
	var ch: Dictionary = sim.state.characters[actor]
	var bld: Dictionary = sim.state.buildings[bld_id]
	var why := ""
	if not (ch.get("order_queue", []) as Array).is_empty():
		why = "queued"  # active pause: the cycle counts as finished, OrderQueue goes on
	if why == "" and str(bld.get("state", "normal")) != "normal":
		why = "building_not_ready"
	if why == "":
		why = may_work(sim, actor, bld_id)
	var recipe: Dictionary = sim.catalog.recipes().get(recipe_id, {})
	if why == "":
		why = _lock_reason(sim, ch, bld, recipe)
	if why == "":
		why = _stock_reason(sim.catalog, bld["inventory"], recipe)
	if why == "":
		_start_cycle(sim, bld_id, zone, actor, recipe_id, mode)
		return
	sim.events.append({"type": "work_idle", "actor": actor, "building": bld_id, "zone": zone, "reason": why})
	if OS.is_debug_build():
		print("[Production] %s deja de repetir %s en %s/%s (motivo=%s)" % [actor, recipe_id, bld_id, zone, why])


static func _start_cycle(sim: Sim, bld_id: String, zone: String, actor: String, recipe_id: String,
		mode: String) -> void:
	var st := sim.state
	var bld: Dictionary = st.buildings[bld_id]
	var recipe: Dictionary = sim.catalog.recipes()[recipe_id]
	var taken: Array = []
	for inp: Dictionary in recipe.get("inputs", []):
		taken.append_array(_take_lowest(bld["inventory"], str(inp["item"]), int(inp["qty"])))
	var now := int(st.clock["minute"])
	var d := owner_cycle_minutes(sim, bld_id, recipe, mode)
	if _is_employee_at(sim, actor, bld_id):
		d = employee_cycle_minutes(sim, actor, recipe, mode)
	elif Needs.tracked(sim, actor):  # H14: low morale slows a family member down (GDD 4.2.6)
		var pr := Needs.productivity(sim, actor)
		if pr < 1.0:
			d = maxi(1, roundi(float(d) / pr))
	var job := {"actor": actor, "recipe": recipe_id, "mode": mode, "start": now, "end": now + d, "inputs": taken,
		"window": cycle_window(sim.catalog, mode, now, d), "touched": false, "result": null, "blocked": false}
	bld["zones"][zone]["job"] = job
	sim.events.append({"type": "work_started", "actor": actor, "building": bld_id, "zone": zone, "recipe": recipe_id,
		"mode": mode, "end": now + d})
	if window_open(job, now):
		sim.events.append({"type": "master_window", "building": bld_id, "zone": zone, "open": true})
	if OS.is_debug_build():
		print("[Production] %s empieza %s en %s/%s (modo=%s, min=%d-%d, ventana=%s, entradas=%s)" % [actor, recipe_id,
			bld_id, zone, mode, now, now + d, job["window"], taken])


## Ends the job at a station without finishing it and gives back what it holds (D11): storage, then the actor's
## inventory, then the station floor. Does not move anybody (the caller frees the station if the actor leaves).
## Returns [{item, quality, qty, to: "storage" | "actor" | "floor"}]. Buildings calls it on exit/station change.
static func interrupt(sim: Sim, bld_id: String, zone: String) -> Array:
	var st := sim.state
	if not st.buildings.has(bld_id):
		return []
	var z: Dictionary = st.buildings[bld_id].get("zones", {}).get(zone, {})
	var job: Variant = z.get("job")
	if not job is Dictionary:
		return []
	var actor := str(job["actor"])
	var returned: Array = []
	for s: Dictionary in _holdings(job):
		returned.append_array(_give_back(sim, bld_id, zone, actor, str(s["item"]), int(s["quality"]), int(s["qty"])))
	if window_open(job, int(st.clock["minute"])) and not job.get("result") is Dictionary:
		sim.events.append({"type": "master_window", "building": bld_id, "zone": zone, "open": false})
	z["job"] = null
	sim.events.append({"type": "work_interrupted", "actor": actor, "building": bld_id, "zone": zone,
		"returned": returned})
	if OS.is_debug_build():
		print("[Production] %s interrumpe %s en %s/%s (devuelto=%s)" % [actor, job["recipe"], bld_id, zone, returned])
	return returned


# --- Rules -----------------------------------------------------------------------------------------------------------

## "" if the actor may work now, or the refusal reason. GDD 4.4.3: characters controlled by the player work, also at
## night. H4: an employee works only at the building it works at, while its job is active (Staff.is_active) and in
## the schedule's work_phases (data/employees.json): night_rest at night, off_hours in the other phases (dusk), never
## at night whatever the building. H5: under_works for everybody while the building has works in progress.
## Anybody else not controlled by the player is refused with not_controlled, except (H3) the members of an AI family with an ai_profile, who work their family's building (night_rest still applies in
## buildings whose night_production is "manual_only").
static func may_work(sim: Sim, actor: String, bld_id: String) -> String:
	if Upgrades.under_works(sim.state, bld_id):
		return "under_works"  # H5 (GDD 4.8): nobody produces in a building under works, owner nor employees
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if str(ch.get("controlled_by", "")) == "human":
		return ""
	var phase := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)
	var night := phase == NIGHT
	if _is_employee_at(sim, actor, bld_id):
		if not Staff.is_active(sim, actor):
			return "not_controlled"  # hired today (starts tomorrow at dawn) or already gone
		if night:
			return "night_rest"
		var phases: Array = sim.catalog.employees.get("schedule", {}).get("work_phases", ["dawn", "day"])
		return "" if phase in phases else "off_hours"
	# H8 (GDD 4.10.6, 4.10.8): a member of the player's family works its family's buildings like the player, also at
	# night; from its coming of age (16).
	var own_fam: Dictionary = sim.state.families.get(str(ch.get("family", "")), {})
	if str(own_fam.get("controlled_by", "")) == "human" and Buildings.owns(sim.state, actor, bld_id):
		return "" if Kin.is_adult(sim, actor) else "too_young"
	var bdef: Dictionary = sim.catalog.buildings().get(str(sim.state.buildings.get(bld_id, {}).get("type", "")), {})
	if night and str(bdef.get("night_production", "")) == "manual_only":
		return "night_rest"
	# H3: a member of an AI family with a profile (the rival smith, GDD 4.5.5) works its own family's building by day,
	# like a hand-worked one; employees arrive with H5.
	var fam: Dictionary = sim.state.families.get(str(ch.get("family", "")), {})
	if str(ch.get("controlled_by", "")) == "ai" and str(fam.get("ai_profile", "")) != "":
		return ""
	return "not_controlled"


## Cycle length in whole minutes: duration_hours × 60 × duration_mult of the mode, at least 1.
static func cycle_minutes(catalog: Catalog, recipe: Dictionary, mode: String) -> int:
	var mult := float(catalog.production.get("modes", {}).get(mode, {}).get("duration_mult", 1.0))
	return maxi(1, roundi(float(recipe.get("duration_hours", 1.0)) * 60.0 * mult))


## H5: cycle length of whoever works by hand at `bld_id` (the owner, an AI family member): cycle_minutes / the
## building's production_speed upgrades (Upgrades.mult), at least 1 minute.
static func owner_cycle_minutes(sim: Sim, bld_id: String, recipe: Dictionary, mode: String) -> int:
	var mult := float(sim.catalog.production.get("modes", {}).get(mode, {}).get("duration_mult", 1.0))
	var up := maxf(Upgrades.mult(sim, bld_id, "production_speed"), 0.01)
	return maxi(1, roundi(float(recipe.get("duration_hours", 1.0)) * 60.0 * mult / up))


## H4: cycle length of an employee (GDD 4.4.1, 4.7.2): the recipe's duration / (rank speed × upgrades), at least 1
## minute. H5: upgrades = production_speed of the building it works at (Upgrades.mult).
static func employee_cycle_minutes(sim: Sim, actor: String, recipe: Dictionary, mode: String) -> int:
	var mult := float(sim.catalog.production.get("modes", {}).get(mode, {}).get("duration_mult", 1.0))
	var speed := maxf(Staff.speed(sim, actor), 0.01)
	var bld_id := Staff.employer(sim.state, actor)
	if bld_id != "":
		speed *= maxf(Upgrades.mult(sim, bld_id, "production_speed"), 0.01)
	return maxi(1, roundi(float(recipe.get("duration_hours", 1.0)) * 60.0 * mult / speed))


## Units a finished cycle of `recipe` gives: the recipe's output qty; H4, for an employee of `bld_id`,
## max(1, round(qty × Staff.efficiency)) (GDD 4.7.2: always at least 1 unit per cycle).
static func output_units(sim: Sim, actor: String, bld_id: String, recipe: Dictionary) -> int:
	var qty := int(recipe.get("output", {}).get("qty", 1))
	if not _is_employee_at(sim, actor, bld_id):
		return qty
	return maxi(1, roundi(float(qty) * Staff.efficiency(sim, actor)))


## Master-touch window [start, end) centred on the middle of the cycle, window_hours long and inside the cycle;
## null if the mode has no master touch.
static func cycle_window(catalog: Catalog, mode: String, start: int, minutes: int) -> Variant:
	if not bool(catalog.production.get("modes", {}).get(mode, {}).get("master_touch", false)):
		return null
	var w := roundi(float(catalog.production.get("master_touch", {}).get("window_hours", 1.0)) * 60.0)
	var ws := maxi(start, start + minutes / 2 - w / 2)
	return [ws, mini(start + minutes, ws + w)]


static func window_open(job: Dictionary, now: int) -> bool:
	var w: Variant = job.get("window")
	return w is Array and now >= int(w[0]) and now < int(w[1])


## Quality of a finished piece (GDD 4.4.2, 4.4.5): the quality table read with the actor's craft + the mode's
## craft_delta (1..10), then one extra roll per step-up bonus (right tool equipped, master touch given). Each success
## raises one step, up to excellent. Always the same rolls in the same order (determinism).
## H5: with `bld_id`, the building's quality_bonus upgrades add to that craft (before the 1..10 clamp).
static func roll_quality(sim: Sim, actor: String, building_type: String, mode: String, touched: bool,
		bld_id: String = "") -> int:
	var prod := sim.catalog.production
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var bonus := roundi(Upgrades.amount(sim, bld_id, "quality_bonus")) if bld_id != "" else 0
	var craft := clampi(int(ch.get("stats", {}).get("craft", 1)) + int(_modes(sim).get(mode, {}).get("craft_delta", 0))
		+ bonus, 1, 10)
	var chances := quality_chances(prod, craft)
	var total := 0.0
	for c: Variant in chances:
		total += float(c)
	var r := sim.state.rng.randf() * total
	var q := 0
	var acc := 0.0
	for i: int in chances.size():
		acc += float(chances[i])
		if r < acc:
			q = i
			break
		q = i
	if has_right_tool(sim, actor, building_type) \
			and sim.state.rng.randf() < float(prod.get("tool_step_up_chance", 0.0)):
		q += 1
	if touched and sim.state.rng.randf() < float(prod.get("master_touch", {}).get("step_up_chance", 0.0)):
		q += 1
	return mini(q, Inventory.EXCELLENT)


static func quality_chances(prod: Dictionary, craft: int) -> Array:
	for row: Dictionary in prod.get("quality_table", []):
		var span: Array = row["craft"]
		if craft >= int(span[0]) and craft <= int(span[1]):
			return row["chances"]
	return [100, 0, 0]


## Whether the actor has the building's tool (data/buildings/<type>.json "tool") in its tool slot.
static func has_right_tool(sim: Sim, actor: String, building_type: String) -> bool:
	var tool := str(sim.catalog.buildings().get(building_type, {}).get("tool", ""))
	var eq: Variant = sim.state.characters.get(actor, {}).get("equipment", {}).get("tool")
	return tool != "" and eq is Dictionary and str(eq.get("item", "")) == tool


# --- Queries (UI) ----------------------------------------------------------------------------------------------------

## The recipes of a station for an actor: [{recipe, status: "ok" | "locked" | "missing_inputs" | "no_room"}], by id.
static func recipe_options(sim: Sim, actor: String, building: String, zone: String) -> Array:
	var st := sim.state
	if not st.buildings.has(building) or not st.characters.has(actor):
		return []
	var bld: Dictionary = st.buildings[building]
	var ch: Dictionary = st.characters[actor]
	var inv := _storage_after_returns(sim, actor, building)
	var kind := Upgrades.zone_kind(sim, building, zone)
	var out: Array = []
	for rid: String in _sorted_keys(sim.catalog.recipes()):
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != str(bld.get("type", "")) or str(r.get("zone", "")) != kind:
			continue
		var status := "ok"
		if _lock_reason(sim, ch, bld, r) != "":
			status = "locked"
		else:
			match _stock_reason(sim.catalog, inv, r):
				"missing_inputs":
					status = "missing_inputs"
				"storage_full":
					status = "no_room"
		out.append({"recipe": rid, "status": status})
	return out


## The job at a station for the UI: {} or {actor, recipe, mode, progress 0..1, window_open, touched, blocked}.
static func job_view(sim: Sim, building: String, zone: String) -> Dictionary:
	var job: Variant = sim.state.buildings.get(building, {}).get("zones", {}).get(zone, {}).get("job")
	if not job is Dictionary:
		return {}
	var now := int(sim.state.clock["minute"])
	var span := maxi(1, int(job["end"]) - int(job["start"]))
	return {"actor": str(job["actor"]), "recipe": str(job["recipe"]), "mode": str(job["mode"]),
		"progress": clampf(float(now - int(job["start"])) / span, 0.0, 1.0),
		"window_open": window_open(job, now) and not job.get("result") is Dictionary,
		"touched": bool(job.get("touched", false)), "blocked": bool(job.get("blocked", false))}


## The station where `actor` has a running job in `bld_id` ("" if none).
static func job_zone(sim: Sim, actor: String, bld_id: String) -> String:
	if not sim.state.buildings.has(bld_id):
		return ""
	var zones: Dictionary = sim.state.buildings[bld_id].get("zones", {})
	for z: String in _sorted_keys(zones):
		var job: Variant = zones[z].get("job")
		if job is Dictionary and str(job["actor"]) == actor:
			return z
	return ""


# --- Helpers ---------------------------------------------------------------------------------------------------------

## Common checks of the orders done inside a building: actor exists and lives, building exists and is the actor's
## (or its family's) or, H4, the one it works at (Staff.works_at), the actor is inside it.
static func _inside_reason(sim: Sim, actor: String, bld_id: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not bool(st.characters[actor].get("alive", true)):
		return "dead"
	if not st.buildings.has(bld_id):
		return "unknown_building"
	if not Buildings.owns(st, actor, bld_id) and not _is_employee_at(sim, actor, bld_id):
		return "not_your_building"
	if str(st.characters[actor].get("location", "")) != bld_id:
		return "not_inside"
	return ""


## H4: whether `actor` is an employee of `bld_id` (character.job.building), not its owner.
static func _is_employee_at(sim: Sim, actor: String, bld_id: String) -> bool:
	return Staff.works_at(sim.state, actor, bld_id) and not Buildings.owns(sim.state, actor, bld_id)


## "skill_too_low" if the actor's craft is under min_craft; "needs_upgrade" if the recipe asks for an upgrade the
## building does not have (bld.upgrades, none until the upgrade tree arrives).
static func _lock_reason(_sim: Sim, ch: Dictionary, bld: Dictionary, recipe: Dictionary) -> String:
	if int(ch.get("stats", {}).get("craft", 0)) < int(recipe.get("min_craft", 1)):
		return "skill_too_low"
	var up := str(recipe.get("requires_upgrade", ""))
	if up != "" and not up in (bld.get("upgrades", []) as Array):
		return "needs_upgrade"
	return ""


## "missing_inputs" or "storage_full" for a recipe on a storage (not modified). Room: after taking the inputs, the
## output must fit in any quality it may come out with.
static func _stock_reason(catalog: Catalog, storage: Dictionary, recipe: Dictionary) -> String:
	for inp: Dictionary in recipe.get("inputs", []):
		if Inventory.count(storage, str(inp["item"])) < int(inp["qty"]):
			return "missing_inputs"
	var after := storage.duplicate(true)
	for inp: Dictionary in recipe.get("inputs", []):
		_take_lowest(after, str(inp["item"]), int(inp["qty"]))
	var out: Dictionary = recipe.get("output", {})
	for q: int in Inventory.QUALITIES:
		if not Inventory.can_add(after, catalog, str(out.get("item", "")), q, int(out.get("qty", 1))):
			return "storage_full"
	return ""


## A copy of the building storage with what the actor's running job there would give back already in it.
static func _storage_after_returns(sim: Sim, actor: String, bld_id: String) -> Dictionary:
	var bld: Dictionary = sim.state.buildings[bld_id]
	var inv: Dictionary = (bld["inventory"] as Dictionary).duplicate(true)
	var working := job_zone(sim, actor, bld_id)
	if working != "":
		for s: Dictionary in _holdings(bld["zones"][working]["job"]):
			var n := _max_fit(inv, sim.catalog, str(s["item"]), int(s["quality"]), int(s["qty"]))
			if n > 0:
				Inventory.add(inv, sim.catalog, str(s["item"]), int(s["quality"]), n)
	return inv


## What a job holds: its finished result if blocked, else the inputs it took.
static func _holdings(job: Dictionary) -> Array:
	if job.get("result") is Dictionary:
		return [job["result"]]
	return job.get("inputs", [])


## Takes `qty` of `item` from `inv`, lowest quality first. Returns the stacks taken [{item, quality, qty}].
static func _take_lowest(inv: Dictionary, item: String, qty: int) -> Array:
	var taken: Array = []
	var left := qty
	for q: int in Inventory.QUALITIES:
		if left == 0:
			break
		var n := mini(left, Inventory.count(inv, item, q))
		if n > 0:
			Inventory.remove(inv, item, q, n)
			taken.append({"item": item, "quality": q, "qty": n})
			left -= n
	return taken


static func _give_back(sim: Sim, bld_id: String, zone: String, actor: String, item: String, quality: int,
		qty: int) -> Array:
	var out: Array = []
	var left := qty
	var storage: Dictionary = sim.state.buildings[bld_id]["inventory"]
	var n := _max_fit(storage, sim.catalog, item, quality, left)
	if n > 0:
		Inventory.add(storage, sim.catalog, item, quality, n)
		out.append({"item": item, "quality": quality, "qty": n, "to": "storage"})
		left -= n
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if left > 0 and not ch.is_empty():
		# The bag's limit already leaves out the equipped weight (Equipment, contract), so can_add is enough.
		n = _max_fit(ch.get("inventory", {}), sim.catalog, item, quality, left)
		if n > 0:
			Inventory.add(ch["inventory"], sim.catalog, item, quality, n)
			out.append({"item": item, "quality": quality, "qty": n, "to": "actor"})
			left -= n
	if left > 0:
		var z: Dictionary = sim.state.buildings[bld_id]["zones"][zone]
		if not z.get("floor") is Array:
			z["floor"] = []
		var pile: Array = z["floor"]
		var merged := false
		for s: Dictionary in pile:
			if str(s["item"]) == item and int(s["quality"]) == quality:
				s["qty"] = int(s["qty"]) + left
				merged = true
				break
		if not merged:
			pile.append({"item": item, "quality": quality, "qty": left})
		out.append({"item": item, "quality": quality, "qty": left, "to": "floor"})
	return out


## How many of `qty` fit in `inv` (largest n <= qty).
static func _max_fit(inv: Dictionary, catalog: Catalog, item: String, quality: int, qty: int) -> int:
	if inv.is_empty():
		return 0
	for n: int in range(qty, 0, -1):
		if Inventory.can_add(inv, catalog, item, quality, n):
			return n
	return 0


static func _modes(sim: Sim) -> Dictionary:
	return sim.catalog.production.get("modes", {})


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys().map(func(k: Variant) -> String: return str(k))
	keys.sort()
	return keys
