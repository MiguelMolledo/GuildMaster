class_name Upgrades
extends RefCounted
## Building upgrade trees (GDD 4.8): the order to buy one, the works (one at a time per building, 0.5-2 days, the
## building does not produce meanwhile) and the single registry of upgrade effects that every other system asks.
## Contract: docs/contratos/h5_mejoras.md. Data: data/upgrades/<tree>/<id>.json and data/upgrade_rules.json.
##
## State (save v6), in each building: upgrades [ids] (finished, in the order they finished), upgrade_work (null or
## {upgrade, actor, start, end}: absolute clock minutes), inspection (Inspections' memory, new_inspection()).
##
## Effects: each upgrade declares effects {kind, <value>} whose kind is in data/upgrade_rules.json effect_kinds.
## "query" kinds are read by other systems through mult() / amount() / unlocks() / flag(); "complete" kinds are applied
## once to the stored state by complete() (employee places, storage stacks, new stations, loyalty, reputation).
## Stacking: "branch_top" = in each branch only the highest finished level that has the kind counts (the levels of a
## branch replace each other), then branches combine (mult multiply, amounts add); "all" = every finished upgrade.
##
## Base (H5): queries, complete() and the shape of the UI query are done; order_buy and step belong to subgrim «arbol».


## The inspection memory of a new building (save v6): last_day (last dawn rolled, -1 none), caught (times caught),
## escaped (times the hidden passage saved it), fines (gold fined in total), escape_ready_day (first day the passage
## can be used again).
static func new_inspection() -> Dictionary:
	return {"last_day": -1, "caught": 0, "escaped": 0, "fines": 0, "escape_ready_day": 0}


# --- Orders -----------------------------------------------------------------------------------------------------

## {"type": "buy_upgrade", "actor", "building", "upgrade"}: management order (no walking). Checks status_of() ==
## "available", pays the gold (Money, category upgrades, ref = the upgrade id) and the materials from the building's
## storage, and starts the works (upgrade_work). Owner: «arbol».
static func order_buy(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


# --- Step -------------------------------------------------------------------------------------------------------

## Every minute, after Buildings and before Staff: works whose end has come finish (complete()). Owner: «arbol».
static func step(_sim: Sim) -> void:
	pass


# --- State queries ----------------------------------------------------------------------------------------------

## The finished upgrades of a building (a copy, in the order they finished).
static func owned(st: WorldState, bld: String) -> Array:
	var out: Array = []
	for u: Variant in st.buildings.get(bld, {}).get("upgrades", []):
		out.append(str(u))
	return out


static func has(st: WorldState, bld: String, id: String) -> bool:
	return id in owned(st, bld)


## The works in progress of a building ({} if none): {upgrade, actor, start, end}.
static func work(st: WorldState, bld: String) -> Dictionary:
	var w: Variant = st.buildings.get(bld, {}).get("upgrade_work", null)
	return w if w is Dictionary else {}


static func under_works(st: WorldState, bld: String) -> bool:
	return not work(st, bld).is_empty()


## The upgrade tree of a building's type ("" if it has none).
static func tree_of(sim: Sim, bld: String) -> String:
	var b: Dictionary = sim.state.buildings.get(bld, {})
	var t: Variant = sim.catalog.buildings().get(str(b.get("type", "")), {}).get("upgrade_tree", null)
	return "" if t == null else str(t)


## What the UI shows for one upgrade, and what buy_upgrade checks: "owned", "in_works" (this one is being built),
## "available", or the reason it cannot be bought now, in this order: unknown_actor, unknown_building,
## not_your_building, unknown_upgrade, wrong_tree, busy (other works in progress), needs_upgrade (a required upgrade is
## missing), stat_too_low (the actor's attribute), title_too_low (the family's title), missing_materials (the
## building's storage, any quality), not_enough_gold (the family's purse).
static func status_of(sim: Sim, actor: String, bld: String, id: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.buildings.has(bld):
		return "unknown_building"
	if not Buildings.owns(st, actor, bld):
		return "not_your_building"
	var u := sim.catalog.upgrade(id)
	if u.is_empty():
		return "unknown_upgrade"
	if str(u.get("tree", "")) != tree_of(sim, bld):
		return "wrong_tree"
	if has(st, bld, id):
		return "owned"
	var w := work(st, bld)
	if not w.is_empty():
		return "in_works" if str(w.get("upgrade", "")) == id else "busy"
	var req: Dictionary = u.get("requires", {})
	for r: Variant in req.get("upgrades", []):
		if not has(st, bld, str(r)):
			return "needs_upgrade"
	var stat: Variant = req.get("stat", null)
	if stat is Dictionary:
		var have := int(st.characters[actor].get("stats", {}).get(str(stat["id"]), 0))
		if have < int(stat.get("min", 0)):
			return "stat_too_low"
	var title: Variant = req.get("title", null)
	if title != null and title_rank(sim, family_title(sim, Money.family_of(st, bld))) < title_rank(sim, str(title)):
		return "title_too_low"
	var inv: Dictionary = st.buildings[bld].get("inventory", {})
	for c: Dictionary in u.get("cost", {}).get("items", []):
		if Inventory.count(inv, str(c["item"])) < int(c["qty"]):
			return "missing_materials"
	if not Money.can_pay(st, Money.family_of(st, bld), int(u.get("cost", {}).get("gold", 0))):
		return "not_enough_gold"
	return "available"


## The title of a family (GDD 4.12.2; the field arrives with H9: until then data's default_title).
static func family_title(sim: Sim, fam: String) -> String:
	var t := str(sim.state.families.get(fam, {}).get("title", ""))
	return t if t != "" else str(sim.catalog.upgrade_rules.get("default_title", "common"))


## Position of a title in the ladder (data/upgrade_rules.json titles), -1 if unknown.
static func title_rank(sim: Sim, title: String) -> int:
	return (sim.catalog.upgrade_rules.get("titles", []) as Array).find(title)


## The tree panel (UI query, fixed shape): {building, tree, owned: [ids], work: {} | {upgrade, actor, start, end,
## progress (0..1), minutes_left}, branches: [{id, name_key, upgrades: [{id, name_key, branch, level, status, cost
## {gold, items}, requires {upgrades, stat, title}, build_days, effects, visual {interior_node, exterior_overlay}}]}]}.
## Branches in data order, upgrades by level. status = status_of(actor, ...).
static func tree_view(sim: Sim, actor: String, bld: String) -> Dictionary:
	var st := sim.state
	var tree := tree_of(sim, bld)
	var out := {"building": bld, "tree": tree, "owned": owned(st, bld), "work": {}, "branches": []}
	var w := work(st, bld)
	if not w.is_empty():
		var now := int(st.clock["minute"])
		var span := maxi(1, int(w.get("end", 0)) - int(w.get("start", 0)))
		var view := w.duplicate(true)
		view["progress"] = clampf(float(now - int(w.get("start", 0))) / float(span), 0.0, 1.0)
		view["minutes_left"] = maxi(0, int(w.get("end", 0)) - now)
		out["work"] = view
	for br: Variant in sim.catalog.upgrade_rules.get("branches", []):
		var ups: Array = []
		for id: String in sim.catalog.upgrade_tree(tree):
			var u := sim.catalog.upgrade(id)
			if str(u.get("branch", "")) != str(br):
				continue
			ups.append({"id": id, "name_key": str(u.get("name_key", "")), "branch": str(br),
				"level": int(u.get("level", 0)), "status": status_of(sim, actor, bld, id),
				"cost": (u.get("cost", {}) as Dictionary).duplicate(true),
				"requires": (u.get("requires", {}) as Dictionary).duplicate(true),
				"build_days": float(u.get("build_days", 0.0)),
				"effects": (u.get("effects", []) as Array).duplicate(true),
				"visual": (u.get("visual", {}) as Dictionary).duplicate(true)})
		ups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) < int(b["level"]))
		if not ups.is_empty():
			(out["branches"] as Array).append({"id": str(br), "name_key": "branch.%s" % br, "upgrades": ups})
	return out


## The visual nodes of a building's finished upgrades (for the views): {interior: [{upgrade, node}], exterior:
## [{upgrade, node}]}, in the order they finished. node = an id of game/visuals/ (docs/contratos/h5_mejoras.md).
static func visuals(sim: Sim, bld: String) -> Dictionary:
	var out := {"interior": [], "exterior": []}
	for id: String in owned(sim.state, bld):
		var v: Dictionary = sim.catalog.upgrade(id).get("visual", {})
		if v.get("interior_node", null) != null:
			(out["interior"] as Array).append({"upgrade": id, "node": str(v["interior_node"])})
		if v.get("exterior_overlay", null) != null:
			(out["exterior"] as Array).append({"upgrade": id, "node": str(v["exterior_overlay"])})
	return out


# --- Effects registry -------------------------------------------------------------------------------------------

## The effects of `kind` that count for a building, by the kind's stack rule: [{upgrade, branch, level, effect}],
## ordered by upgrade id. Unknown upgrades in the state (data removed) are skipped.
static func effects(sim: Sim, bld: String, kind: String) -> Array:
	var stack := str(sim.catalog.effect_kind(kind).get("stack", "all"))
	var ids := owned(sim.state, bld)
	ids.sort()
	var found: Array = []
	var top := {}  # branch -> index in found of its highest level (branch_top)
	for id: String in ids:
		var u := sim.catalog.upgrade(id)
		if u.is_empty():
			continue
		var mine: Array = []
		for e: Dictionary in u.get("effects", []):
			if str(e.get("kind", "")) == kind:
				mine.append(e)
		if mine.is_empty():
			continue
		var row := {"upgrade": id, "branch": str(u.get("branch", "")), "level": int(u.get("level", 0)), "effects": mine}
		if stack == "branch_top":
			var br := str(row["branch"])
			if top.has(br) and int(found[int(top[br])]["level"]) >= int(row["level"]):
				continue
			if top.has(br):
				found[int(top[br])] = row
			else:
				top[br] = found.size()
				found.append(row)
		else:
			found.append(row)
	var out: Array = []
	for row: Dictionary in found:
		for e: Dictionary in row["effects"]:
			out.append({"upgrade": row["upgrade"], "branch": row["branch"], "level": row["level"], "effect": e})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["upgrade"]) < str(b["upgrade"]))
	return out


## Product of the `mult` of the effects of `kind` that count (1.0 with none). E.g. mult(sim, bld, "production_speed").
static func mult(sim: Sim, bld: String, kind: String) -> float:
	var m := 1.0
	for e: Dictionary in effects(sim, bld, kind):
		m *= float(e["effect"].get("mult", 1.0))
	return m


## Sum of the `amount` of the effects of `kind` that count (0.0 with none). E.g. amount(sim, bld, "quality_bonus").
static func amount(sim: Sim, bld: String, kind: String) -> float:
	var a := 0.0
	for e: Dictionary in effects(sim, bld, kind):
		a += float(e["effect"].get("amount", 0.0))
	return a


## The ids an id-valued kind unlocks (new_zone -> zones, unlock_recipe -> recipes, allow_rank -> ranks), sorted.
static func unlocks(sim: Sim, bld: String, kind: String) -> Array:
	var field := str(sim.catalog.effect_kind(kind).get("value", ""))
	var out: Array = []
	for e: Dictionary in effects(sim, bld, kind):
		var v := str(e["effect"].get(field, ""))
		if v != "" and not v in out:
			out.append(v)
	out.sort()
	return out


## Whether some finished upgrade has a flag kind (counter_sales, inspection_escape) — or any effect of `kind`.
static func flag(sim: Sim, bld: String, kind: String) -> bool:
	return not effects(sim, bld, kind).is_empty()


## The stations an upgrade added: [{zone, like, upgrade}] (new_zone effects), by zone id. Where they stand in the
## interior is the view's (game/visuals/interiors/<type>.tscn, Stations/<zone>).
static func new_zones(sim: Sim, bld: String) -> Array:
	var out: Array = []
	for e: Dictionary in effects(sim, bld, "new_zone"):
		var ef: Dictionary = e["effect"]
		out.append({"zone": str(ef["zone"]), "like": str(ef.get("like", ef["zone"])), "upgrade": str(e["upgrade"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["zone"]) < str(b["zone"]))
	return out


## The station kind a zone works as: the zone itself for the building type's own zones ("anvil"), the `like` of an
## upgrade's new station ("anvil_2" -> "anvil"), "" if the building has no such zone. Recipes name the kind.
static func zone_kind(sim: Sim, bld: String, zone: String) -> String:
	var b: Dictionary = sim.state.buildings.get(bld, {})
	for z: Dictionary in sim.catalog.buildings().get(str(b.get("type", "")), {}).get("zones", []):
		if str(z.get("id", "")) == zone:
			return zone
	for nz: Dictionary in new_zones(sim, bld):
		if str(nz["zone"]) == zone:
			return str(nz["like"])
	return ""


## Whether the building's upgrades allow employees of `rank` (allow_rank effects). The H4 check (data/employees.json
## ranks.<rank>.requires_upgrade) still applies until «arbol» switches Staff to this.
static func allows_rank(sim: Sim, bld: String, rank: String) -> bool:
	return rank in unlocks(sim, bld, "allow_rank")


# --- Finishing an upgrade ---------------------------------------------------------------------------------------

## Finishes `id` in `bld` (end of the works; the scenario tools call it directly): adds it to upgrades, clears the
## works if they were for it and applies its "complete" effects once: max_employees -> employee_slots; extra_storage ->
## storage stacks; new_zone -> an empty station in zones; loyalty_bonus -> loyalty of the building's employees;
## reputation -> the owner family. Emits upgrade_done {family, building, upgrade}. false (nothing changes) if unknown,
## of another tree or already finished.
static func complete(sim: Sim, bld: String, id: String) -> bool:
	var st := sim.state
	var u := sim.catalog.upgrade(id)
	if not st.buildings.has(bld) or u.is_empty() or str(u.get("tree", "")) != tree_of(sim, bld) or has(st, bld, id):
		return false
	var b: Dictionary = st.buildings[bld]
	if not b.get("upgrades", null) is Array:
		b["upgrades"] = []
	(b["upgrades"] as Array).append(id)
	if str(work(st, bld).get("upgrade", "")) == id:
		b["upgrade_work"] = null
	var fam := Money.family_of(st, bld)
	for e: Dictionary in u.get("effects", []):
		var kind := str(e.get("kind", ""))
		if str(sim.catalog.effect_kind(kind).get("when", "")) != "complete":
			continue
		match kind:
			"max_employees":
				b["employee_slots"] = int(b.get("employee_slots", 0)) + int(e.get("amount", 0))
			"extra_storage":
				var inv: Dictionary = b.get("inventory", {})
				if str(inv.get("limit_kind", "")) == "stacks":
					inv["limit"] = int(inv.get("limit", 0)) + int(e.get("amount", 0))
				else:
					inv["limit"] = float(inv.get("limit", 0.0)) + float(e.get("amount", 0.0))
			"new_zone":
				var zones: Dictionary = b.get("zones", {})
				if not zones.has(str(e["zone"])):
					zones[str(e["zone"])] = {"occupant": "", "job": null}
			"loyalty_bonus":
				for c: String in Staff.employees_of(st, bld):
					Staff._add_loyalty(sim, c, int(e.get("amount", 0)), "upgrade")
			"reputation":
				if st.families.has(fam) and int(e.get("amount", 0)) != 0:
					st.families[fam]["reputation"] = int(st.families[fam].get("reputation", 0)) + int(e["amount"])
					sim.events.append({"type": "reputation_changed", "family": fam, "amount": int(e["amount"]),
						"reason": "upgrade"})
	sim.events.append({"type": "upgrade_done", "family": fam, "building": bld, "upgrade": id})
	if OS.is_debug_build():
		print("[Upgrades] %s termina %s (familia=%s, huecos=%d, almacén=%s, puestos=%s)" % [bld, id, fam,
			int(b.get("employee_slots", 0)), str(b.get("inventory", {}).get("limit", "")),
			str((b.get("zones", {}) as Dictionary).keys())])
	return true
