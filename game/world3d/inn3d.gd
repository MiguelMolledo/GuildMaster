class_name Inn3D
extends RefCounted
## The Taberna-Posada open in place in the 3D town (docs/3d/plan.md M3D-3; the 2D room's InnLayer, 04f §4.27.4): its
## guests and its guest beds in the 3D interior. Reads only.
## - The guests of the turn (Inn.guests) join the roster of the open house as clients, so SituLive seats them on the
##   tavern's stools and benches (or by the bar when they are full), drinking. A guest who is a townsperson already
##   inside (in the roster) is not added twice; one who is offstage (a lodger) keeps that person's look; the others
##   are dressed in their group's colours (InnLayer.GROUP_COLORS).
## - The guest beds (the kit's "cama_huesped" pieces the interior placed: Interior3DBuilder.beds_placed, by floor and
##   position) stand for the sim's
##   beds in order: sim bed i is the i-th of them. A sim bed with no piece (the room has fewer than the sim) has no 3D
##   place: it is made from the panel (Habitaciones).
## InnLayer asks this for the screen points of guests and beds (it draws the orders, patience bars and bed states over
## them and picks them on a click).

const GUEST_BED: String = "cama_huesped"
const HEAD_LIFT: float = 2.0   # metres over a guest's root: where its order hangs
const BODY_LIFT: float = 1.0   # its chest: what a click aims at
const BED_LIFT: float = 0.6


## Adds the guests of the tavern open in place to `roster` (Town3D._roster_extra, once per frame).
static func add_guests(town: Town3D, roster: Dictionary) -> void:
	var b := str(town.live_bld)
	if town.sim == null or b == "" or not Inn.is_inn(town.sim, b):
		return
	var defs: Dictionary = town.get_meta("inn3d_defs", {})
	var seen := {}
	for g: Dictionary in Inn.guests(town.sim, b):
		var gid := str(g["id"])
		var chr := str(g.get("chr", ""))
		if chr != "" and roster.has(chr):
			continue  # a townsperson the sim already has inside: drawn as itself
		if int(g.get("seat", -1)) < 0:
			continue  # no seat (waiting at the door for one): not in the room
		seen[gid] = true
		if not defs.has(gid):
			defs[gid] = town._def_for(gid, _guest_entry(town, g))
		roster[gid] = {def = defs[gid], name = str((defs[gid] as Dictionary).get("name", "")), station = "", doing = "client"}
	for gid: String in defs.keys():
		if not seen.has(gid):
			defs.erase(gid)
	town.set_meta("inn3d_defs", defs)


## What _def_for needs of a guest: the townsperson it is (its trace entry), else a figure of its group.
static func _guest_entry(town: Town3D, g: Dictionary) -> Dictionary:
	var chr := str(g.get("chr", ""))
	if chr != "" and (town.trace.characters as Dictionary).has(chr):
		return town.trace.characters[chr]
	var n := int(g.get("name_n", 0))
	var c: Array = InnLayer.GROUP_COLORS.get(str(g.get("group", "")), ["#808080", "#c0c0c0"])
	return {"name": SimQuery.t_("inn.group." + str(g.get("group", ""))), "sex": "f" if n % 3 == 1 else "m",
		"family": "fam_visitors", "age": 30, "visual": {"hair": n % 6, "skin": n % 3,
			"dress": {"primary": str(c[0]), "secondary": str(c[1])}}}


## The guest beds of the open interior, in the sim's order: [{"at": global Vector3, "floor": int}].
static func beds(bridge: InteriorBridge3D) -> Array:
	if bridge == null or not bridge.ready():
		return []
	var v := bridge.view()
	if v.has_meta("inn3d_beds"):
		return v.get_meta("inn3d_beds")
	var out: Array = []
	for bp: Dictionary in v.B.beds_placed:
		if str(bp["id"]) == GUEST_BED:
			out.append({"at": (v.interior as Node3D).global_transform * (bp["pos"] as Vector3), "floor": int(bp["floor"])})
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		if int(a["floor"]) != int(c["floor"]):
			return int(a["floor"]) < int(c["floor"])
		var pa: Vector3 = a["at"]
		var pc: Vector3 = c["at"]
		return pa.x < pc.x if not is_equal_approx(pa.x, pc.x) else pa.z < pc.z)
	v.set_meta("inn3d_beds", out)
	ViewConfig.info("Inn3D", "%d guest beds in place (%s)" % [out.size(), bridge.building])
	return out


## The floor the open house shows (its top floor); the marks of other floors are not drawn.
static func shown_floor(bridge: InteriorBridge3D) -> int:
	return int(bridge.view().top) if bridge != null and bridge.ready() else 0


## Sim bed i on screen (Vector2.INF: no piece for it, on another floor, or behind the camera).
static func bed_screen(bridge: InteriorBridge3D, i: int) -> Vector2:
	var bs := beds(bridge)
	if i < 0 or i >= bs.size() or int(bs[i]["floor"]) != shown_floor(bridge):
		return Vector2.INF
	var p: Vector3 = (bs[i]["at"] as Vector3) + Vector3(0, BED_LIFT, 0)
	if bridge.town.cam.is_position_behind(p):
		return Vector2.INF
	return bridge.town.cam.unproject_position(p)


## A guest on screen at `lift` metres over its root (Vector2.INF: not drawn, on another floor, or walking out).
static func guest_screen(bridge: InteriorBridge3D, gid: String, lift: float) -> Vector2:
	if bridge == null or not bridge.ready() or not (bridge.view().live_actors as Dictionary).has(gid):
		return Vector2.INF
	var a: Dictionary = bridge.view().live_actors[gid]
	var n: Node3D = a.node
	if not n.is_visible_in_tree() or str(a.get("key", "")) == "out" or int(a.get("floor", 0)) != shown_floor(bridge):
		return Vector2.INF
	var p := n.global_position + Vector3(0, lift, 0)
	if bridge.town.cam.is_position_behind(p):
		return Vector2.INF
	return bridge.town.cam.unproject_position(p)


## The guest stands or sits at its place (not walking in or out).
static func guest_still(bridge: InteriorBridge3D, gid: String) -> bool:
	if bridge == null or not bridge.ready() or not (bridge.view().live_actors as Dictionary).has(gid):
		return false
	var a: Dictionary = bridge.view().live_actors[gid]
	return str(a.get("state", "")) != "walk" and (a.get("legs", []) as Array).is_empty() and str(a.get("key", "")) != "out"
