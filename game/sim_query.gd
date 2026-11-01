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
		"enter_building", "work_at":
			var b := building_label(state, catalog, str(o.get("building", "")))
			if t == "enter_building":
				return t_("ui.order.enter_building") % b
			return t_("ui.order.work_at") % [mode_name(str(o.get("mode", "normal"))),
				recipe_name(catalog, str(o.get("recipe", "")))]
		"go_to_station":
			return t_("ui.order.go_to_station") % zone_name(str(o.get("zone", "")))
		"transfer":
			return t_("ui.order.transfer") % [int(o.get("qty", 0)),
				item_label(catalog, str(o.get("item", "")), int(o.get("quality", 0)))]
		"equip":
			return t_("ui.order.equip") % item_name(catalog, str(o.get("item", "")))
		"buy", "sell":
			var line := t_("ui.order." + t) % [int(o.get("qty", 0)), item_label(catalog, str(o.get("item", "")),
				int(o.get("quality", 0)))]
			if str(o.get("deliver_to", "")) != "":
				line += " → " + building_label(state, catalog, str(o["deliver_to"]))
			return line
	var key := "ui.order." + t
	var s := t_(key)
	return t if s == key else s


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


# --- H3 · market, board, money, notices --------------------------------------------------------------------------------

## The family the player controls (the first one with controlled_by "human"), "" if none.
static func player_family(state: WorldState) -> String:
	var ids: Array = state.families.keys()
	ids.sort()
	for id: String in ids:
		if str(state.families[id].get("controlled_by", "")) == "human":
			return str(id)
	return ""


## Who of the player's family acts for orders that need any member (repay_loan, read_notices): `preferred` if it
## is a living member of `fam`, else the first living member. "" if none.
static func family_actor(state: WorldState, fam: String, preferred: String = "") -> String:
	var ch: Dictionary = state.characters.get(preferred, {})
	if not ch.is_empty() and str(ch.get("family", "")) == fam and bool(ch.get("alive", true)):
		return preferred
	var ids: Array = state.characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = state.characters[id]
		if str(c.get("family", "")) == fam and bool(c.get("alive", true)):
			return str(id)
	return ""


## The name on a building's sign: "Forja" for the player's own and public ones, "Forja de Ferrer" when it belongs to
## another family (the rival's forge is told apart, GDD 4.5.5).
static func building_label(state: WorldState, catalog: Catalog, building: String) -> String:
	var n := building_name(state, catalog, building)
	var owner := str(state.buildings.get(building, {}).get("owner", ""))
	var fam: Dictionary = state.families.get(owner, {})
	if fam.is_empty() and state.characters.has(owner):
		fam = state.families.get(str(state.characters[owner].get("family", "")), {})
	if fam.is_empty() or str(fam.get("controlled_by", "")) == "human":
		return n
	return t_("ui.building_of").format({"building": n, "family": str(fam.get("name", ""))})


## Whether `building` is a public shop (no owner, its type public: true).
static func is_public(state: WorldState, catalog: Catalog, building: String) -> bool:
	var b: Dictionary = state.buildings.get(building, {})
	return str(b.get("owner", "")) == "" and bool(catalog.buildings().get(str(b.get("type", "")), {}).get("public", false))


## The market stall a shop building serves ("" if it is not a shop): its type's market_stall.
static func shop_stall(state: WorldState, catalog: Catalog, building: String) -> String:
	var type := str(state.buildings.get(building, {}).get("type", ""))
	return str(catalog.buildings().get(type, {}).get("market_stall", ""))


## The outdoor stalls and the board of the current map: [{kind: "stall"|"board", id, tile: Vector2i, service:
## Vector2i}] (data/maps/<map>.json "stalls" and "board").
static func map_services(state: WorldState, catalog: Catalog) -> Array:
	var out: Array = []
	var m: Dictionary = catalog.maps().get(state.map_id, {})
	var stalls: Dictionary = m.get("stalls", {})
	var ids: Array = stalls.keys()
	ids.sort()
	for id: String in ids:
		var s: Dictionary = stalls[id]
		out.append({"kind": "stall", "id": str(id), "tile": _v2i(s.get("tile", [])), "service": _v2i(s.get("service", []))})
	var b: Dictionary = m.get("board", {})
	if not b.is_empty():
		out.append({"kind": "board", "id": "board", "tile": _v2i(b.get("tile", [])), "service": _v2i(b.get("service", []))})
	return out


static func _v2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1])) if a.size() == 2 else Vector2i(-999, -999)


## Whether `actor` stands still on `tile` on the map (on it, no path, not inside a building).
static func stands_on(state: WorldState, actor: String, tile: Vector2i) -> bool:
	var ch: Dictionary = state.characters.get(actor, {})
	if ch.is_empty() or str(ch.get("location", "")) != "" or not (ch.get("path", []) as Array).is_empty():
		return false
	var p: Array = ch.get("position", [])
	return p.size() == 2 and Vector2i(int(p[0]), int(p[1])) == tile


static func stall_name(catalog: Catalog, stall: String) -> String:
	return t_(str(catalog.market.get("stalls", {}).get(stall, {}).get("name_key", "stall." + stall)))


## {open, reason, buy: [...], sell: [...], deliver_to: [bld]} of `stall` for `actor` (Market.offers).
static func market_offers(sim: Sim, actor: String, stall: String) -> Dictionary:
	return Market.offers(sim, actor, stall)


## The stall `actor` is at now ("" if none).
static func stall_at(sim: Sim, actor: String) -> String:
	return Market.stall_at(sim, actor)


## {at_board, open: [...], accepted: [...]} (Contracts.board_view).
static func board_view(sim: Sim, actor: String) -> Dictionary:
	return Contracts.board_view(sim, actor)


static func client_name(client: String) -> String:
	return t_("client." + client)


static func quality_name(quality: int) -> String:
	return t_("ui.quality.%d" % quality)


## "1 d 4 h" / "5 h" from game hours.
static func hours_label(hours: float) -> String:
	var h := maxi(0, int(ceil(hours)))
	if h >= 24:
		return t_("ui.days_hours") % [h / 24, h % 24]
	return t_("ui.hours") % h


static func category_name(category: String) -> String:
	var key := "ledger.cat." + category
	var s := t_(key)
	return category if s == key else s


## A notice's text: its key formatted with its params, ids turned into names (item, building, client, objective).
static func notice_text(state: WorldState, catalog: Catalog, n: Dictionary) -> String:
	var p: Dictionary = (n.get("params", {}) as Dictionary).duplicate()
	if p.has("item"):
		p["item"] = item_name(catalog, str(p["item"]))
	if p.has("building") and state.buildings.has(str(p["building"])):
		p["building"] = building_label(state, catalog, str(p["building"]))
	if p.has("client"):
		p["client"] = client_name(str(p["client"]))
	if p.has("objective"):
		p["objective"] = t_(str(catalog.objectives().get(str(p["objective"]), {}).get("name_key", "objective." + str(p["objective"]))))
	# H4: employees, ranks, recipes, roles and reasons of the staff and queue notices
	for k: String in ["employee", "character", "thief"]:
		if p.has(k) and state.characters.has(str(p[k])):
			p[k] = str(state.characters[str(p[k])].get("name", p[k]))
	for k: String in ["rank", "next_rank", "from_rank"]:
		if p.has(k) and not catalog.rank(str(p[k])).is_empty():
			p[k] = rank_name(catalog, str(p[k]))
	if p.has("recipe"):
		p["recipe"] = recipe_name(catalog, str(p["recipe"]))
	if p.has("role"):
		p["role"] = role_name(catalog, str(p["role"]))
	if p.has("zone"):
		p["zone"] = zone_name(str(p["zone"]))
	if p.has("reason"):
		p["reason"] = reason_text(str(p["reason"]))
	if p.has("upgrade"):  # H5: upgrade notices
		p["upgrade"] = upgrade_name(catalog, str(p["upgrade"]))
	return t_(str(n.get("key", ""))).format(p)


## "Día 3 · 14:05" of an absolute minute.
static func minute_label(minute: int) -> String:
	var d := Clock.day(minute)
	var m := minute - d * Clock.MINUTES_PER_DAY
	return t_("ui.day_time") % [d + 1, m / 60, m % 60]


## The open loans of `fam` with their status, sorted by id.
static func loans_of(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if not s.is_empty():
			out.append(s)
	return out


static func objective_name(catalog: Catalog, objective: String) -> String:
	return t_(str(catalog.objectives().get(objective, {}).get("name_key", "objective." + objective)))


# --- H4 · employees, production queue ----------------------------------------------------------------------------------

## The family that owns `building` ("" if public or unknown).
static func building_family(state: WorldState, building: String) -> String:
	return Money.family_of(state, building)


## Who signs the orders of `building`'s family (hire, fire, queue_*...): `preferred` if it is a living member of the
## owner family, else its first living member ("" if nobody).
static func building_actor(state: WorldState, building: String, preferred: String = "") -> String:
	var fam := building_family(state, building)
	return family_actor(state, fam, preferred) if fam != "" else ""


## [{character, name, female, rank, stats, wage, status}] (Staff.candidates).
static func candidates(sim: Sim, actor: String, building: String) -> Array:
	return Staff.candidates(sim, actor, building)


## [{character, name, rank, role, loyalty, band, wage, ..., routine, task}] (Staff.employees).
static func employees(sim: Sim, building: String) -> Array:
	return Staff.employees(sim, building)


static func slots(state: WorldState, building: String) -> int:
	return Staff.slots(state, building)


static func free_slots(state: WorldState, building: String) -> int:
	return Staff.free_slots(state, building)


## {entries: [{id, recipe, qty, done, status}], loop, paused, stalled} (WorkQueue.view).
static func queue_view(sim: Sim, building: String) -> Dictionary:
	return WorkQueue.view(sim, building)


## The employees of `building` at work with nothing to do (WorkQueue.idle_employees): the idle icon on the map.
static func idle_employees(sim: Sim, building: String) -> Array:
	return WorkQueue.idle_employees(sim, building)


## The recipes made in a building of `building`'s type (data/recipes "building"), by station order then id.
static func building_recipes(state: WorldState, catalog: Catalog, building: String) -> Array:
	var type := str(state.buildings.get(building, {}).get("type", ""))
	var zones: Array = []
	for z: Dictionary in catalog.buildings().get(type, {}).get("zones", []):
		zones.append(str(z.get("id", "")))
	var out: Array = []
	for id: Variant in catalog.recipes():
		if str(catalog.recipes()[id].get("building", "")) == type:
			out.append(str(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var za := zones.find(str(catalog.recipes()[a].get("zone", "")))
		var zb := zones.find(str(catalog.recipes()[b].get("zone", "")))
		if za != zb:
			return za < zb
		return a < b)
	return out


## The roles an employee of `building` can get (set_role): "any" first, then each station of its type that is a role
## in data/employees.json "roles", in the type's station order.
static func building_roles(state: WorldState, catalog: Catalog, building: String) -> Array:
	var roles: Dictionary = catalog.employees.get("roles", {})
	var out: Array = [str(catalog.employees.get("default_role", "any"))]
	var type := str(state.buildings.get(building, {}).get("type", ""))
	for z: Dictionary in catalog.buildings().get(type, {}).get("zones", []):
		var id := str(z.get("id", ""))
		if roles.has(id) and not id in out:
			out.append(id)
	return out


static func rank_name(catalog: Catalog, rank: String) -> String:
	return t_(str(catalog.rank(rank).get("name_key", "rank." + rank)))


static func role_name(catalog: Catalog, role: String) -> String:
	return t_(str(catalog.employees.get("roles", {}).get(role, {}).get("name_key", "role." + role)))


## A loyalty band's name ("leal", "descontento"...), "" for none.
static func band_name(band: String) -> String:
	return t_("ui.staff.band." + band) if band != "" else ""


## The text of a refusal / skip reason (reason.<id>), the id itself if it has no text.
static func reason_text(reason: String) -> String:
	var key := "reason." + reason
	var s := t_(key)
	return reason if s == key else s


## "∞" or the number of a queue entry's quantity.
static func qty_label(qty: int) -> String:
	return "∞" if qty < 0 else str(qty)


## The family whose building `chr` works at ("" without a job): the badge colour on the map.
static func employer_family(state: WorldState, chr: String) -> String:
	var b := Staff.employer(state, chr)
	return building_family(state, b) if b != "" else ""


# --- H5 · upgrades (docs/contratos/h5_mejoras.md) ----------------------------------------------------------------------

static func upgrade_name(catalog: Catalog, upgrade: String) -> String:
	return t_(str(catalog.upgrade(upgrade).get("name_key", "upgrade." + upgrade)))


static func branch_name(branch: String) -> String:
	return t_("branch." + branch)


static func title_name(title: String) -> String:
	var key := "title." + title
	var s := t_(key)
	return title if s == key else s


## The upgrade tree panel of `building` for `actor` (Upgrades.tree_view).
static func upgrade_tree(sim: Sim, actor: String, building: String) -> Dictionary:
	return Upgrades.tree_view(sim, actor, building)


## {risk, last_day, caught, escaped, fines, can_escape} of a building (Inspections.view).
static func inspection_view(sim: Sim, building: String) -> Dictionary:
	return Inspections.view(sim, building)


## The works in progress of a building as the tree panel shows them ({} if none): {upgrade, start, end, progress,
## minutes_left}.
static func upgrade_works(sim: Sim, building: String) -> Dictionary:
	if not Upgrades.under_works(sim.state, building):
		return {}
	return Upgrades.tree_view(sim, "", building).get("work", {})


## "12 h" / "1 d 4 h" of the game minutes left (rounded up to the hour).
static func minutes_left_label(minutes: int) -> String:
	return hours_label(float(maxi(0, minutes)) / 60.0)


## One effect of an upgrade as the panel says it (effect.<kind> with its value formatted: fractions of protection,
## customers and inspection risk as percentages, ids as names).
static func effect_text(catalog: Catalog, e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	var p := {}
	if e.has("mult"):
		p["mult"] = _num(float(e["mult"]))
	if e.has("amount"):
		var a := float(e["amount"])
		if kind in ["protection", "customer_bonus", "inspection_risk"]:
			p["amount"] = "%d %%" % roundi(a * 100.0)
		else:
			p["amount"] = _num(a)
	if e.has("recipe"):
		p["recipe"] = recipe_name(catalog, str(e["recipe"]))
	if e.has("rank"):
		p["rank"] = rank_name(catalog, str(e["rank"]))
	if e.has("zone"):
		p["zone"] = zone_name(str(e["zone"]))
	var key := "effect." + kind
	var s := t_(key)
	return kind if s == key else s.format(p)


## The visual nodes to show for a building's finished upgrades on one `side` ("interior" | "exterior"):
## Upgrades.visuals, keeping in the branches of data/view.json upgrades.latest_only_branches only the highest finished
## level (their visuals replace each other); the rest show every finished level. Node names, in finishing order.
static func upgrade_visual_nodes(sim: Sim, building: String, side: String) -> Array:
	var latest: Array = (ViewConfig.value("upgrades", {}) as Dictionary).get("latest_only_branches", [])
	var rows: Array = Upgrades.visuals(sim, building).get(side, [])
	var top := {}  # branch -> highest finished level with a visual on this side
	for v: Dictionary in rows:
		var u := sim.catalog.upgrade(str(v["upgrade"]))
		var br := str(u.get("branch", ""))
		if br in latest:
			top[br] = maxi(int(top.get(br, 0)), int(u.get("level", 0)))
	var out: Array = []
	for v: Dictionary in rows:
		var u := sim.catalog.upgrade(str(v["upgrade"]))
		var br := str(u.get("branch", ""))
		if br in latest and int(u.get("level", 0)) < int(top.get(br, 0)):
			continue
		out.append(str(v["node"]))
	return out


## "10" for whole numbers, "1.25" otherwise.
static func _num(x: float) -> String:
	return str(roundi(x)) if is_equal_approx(x, roundf(x)) else String.num(x, 2)
