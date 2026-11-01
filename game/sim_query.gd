class_name SimQuery
extends RefCounted
## What the views ask the sim (docs/contratos/h2_forja.md, "Consultas para la UI") in one place, plus the texts of
## items, recipes, stations and orders. The rules live in the sim: these only forward to its query functions or read
## the state.


## [{recipe, status: "ok"|"locked"|"missing_inputs"|"no_room"}] of a station, for `actor` ([] without an actor).
static func recipe_options(sim: Sim, actor: String, building: String, zone: String) -> Array:
	return Production.recipe_options(sim, actor, building, zone)


## {} | {actor, recipe, mode, progress: 0..1, window_open, touched, blocked} of a station.
static func job_view(sim: Sim, building: String, zone: String) -> Dictionary:
	return Production.job_view(sim, building, zone)


static func carried_weight(sim: Sim, actor: String) -> float:
	return Equipment.carried_weight(sim, actor)


static func max_weight(sim: Sim, actor: String) -> float:
	return Equipment.max_weight(sim, actor)


## {ok, reason}: whether `actor` may go into `building` now.
static func can_enter(sim: Sim, actor: String, building: String) -> Dictionary:
	return Buildings.can_enter(sim, actor, building)


## The building whose footprint or door covers `tile`, "" if none.
static func building_at(state: WorldState, tile: Vector2i) -> String:
	var ids: Array = state.buildings.keys()
	ids.sort()
	for id: String in ids:
		var b: Dictionary = state.buildings[id]
		var o: Array = b.get("origin", [0, 0])
		var f: Array = b.get("footprint", [1, 1])
		var d: Array = b.get("door", [-999, -999])
		if Rect2i(int(o[0]), int(o[1]), int(f[0]), int(f[1])).has_point(tile) or Vector2i(int(d[0]), int(d[1])) == tile:
			return str(id)
	return ""


## Whether `building` belongs to `actor` or to its family (the sim's rule).
static func is_own(state: WorldState, actor: String, building: String) -> bool:
	return Buildings.owns(state, actor, building)


# --- texts -----------------------------------------------------------------------------------------------------------

static func t_(key: String) -> String:
	return String(TranslationServer.translate(key))


static func item_name(catalog: Catalog, item: String) -> String:
	var def := catalog.item(item)
	return t_(str(def.get("name_key", "item." + item)))


## "Espada buena" (GDD 4.3.3: quality as a suffix). Normal quality has no suffix.
static func item_label(catalog: Catalog, item: String, quality: int) -> String:
	var n := item_name(catalog, item)
	if quality <= 0:
		return n
	# Spanish adjectives agree with the item's grammatical gender (data/items "gender": "m" | "f").
	var gender := str(catalog.item(item).get("gender", "m"))
	return t_("ui.item_quality").format({"item": n,
		"quality": t_("quality.%d.%s" % [quality, gender])})


static func recipe_name(catalog: Catalog, recipe: String) -> String:
	return t_(str(catalog.recipes().get(recipe, {}).get("name_key", "recipe." + recipe)))


static func zone_name(zone: String) -> String:
	return t_("ui.zone." + zone)


static func building_name(state: WorldState, catalog: Catalog, building: String) -> String:
	var type := str(state.buildings.get(building, {}).get("type", ""))
	return t_(str(catalog.buildings().get(type, {}).get("name_key", "building." + type)))


static func mode_name(mode: String) -> String:
	return t_("ui.mode." + mode)


## One line of an order queue: "Entrar en Forja", "Trabajar con cuidado: Forjar espada"...
static func order_label(state: WorldState, catalog: Catalog, o: Dictionary) -> String:
	var t := str(o.get("type", ""))
	match t:
		"move_to":
			var tile: Array = o.get("tile", [0, 0])
			return t_("ui.order.move_to") % [int(tile[0]), int(tile[1])]
		"enter_building", "work_at", "buy_raw":
			var b := building_name(state, catalog, str(o.get("building", "")))
			if t == "enter_building":
				return t_("ui.order.enter_building") % b
			if t == "buy_raw":
				return t_("ui.order.buy_raw") % [int(o.get("qty", 0)), item_name(catalog, str(o.get("item", "")))]
			return t_("ui.order.work_at") % [mode_name(str(o.get("mode", "normal"))),
				recipe_name(catalog, str(o.get("recipe", "")))]
		"go_to_station":
			return t_("ui.order.go_to_station") % zone_name(str(o.get("zone", "")))
		"transfer":
			return t_("ui.order.transfer") % [int(o.get("qty", 0)),
				item_label(catalog, str(o.get("item", "")), int(o.get("quality", 0)))]
		"equip":
			return t_("ui.order.equip") % item_name(catalog, str(o.get("item", "")))
	var key := "ui.order." + t
	var s := t_(key)
	return t if s == key else s


## Gold `qty` units of a raw material cost in the provisional purchase of H2 (buy_raw), as the sim charges it.
static func raw_cost(sim: Sim, item: String, qty: int) -> int:
	return Production.raw_cost(sim.catalog, item, qty)


## The raw materials of the catalog (what buy_raw accepts), by id.
static func raw_items(catalog: Catalog) -> Array:
	var out: Array = []
	for id: String in catalog.items():
		if str(catalog.item(id).get("category", "")) == "raw":
			out.append(id)
	out.sort()
	return out


## The order queue of `actor` as text lines, in order (GDD 4.1, active pause): what the sim holds in its order_queue,
## then, while paused, the orders given since (they reach the queue on the next step).
static func queue_lines(sim: Sim, actor: String, pending: Array, paused: bool) -> PackedStringArray:
	var out: PackedStringArray = []
	var ch: Dictionary = sim.state.characters.get(actor, {})
	for o: Dictionary in ch.get("order_queue", []):
		out.append(SimQuery.order_label(sim.state, sim.catalog, o))
	if paused:
		for o: Dictionary in pending:
			if str(o.get("actor", "")) == actor:
				out.append(SimQuery.order_label(sim.state, sim.catalog, o))
	return out
