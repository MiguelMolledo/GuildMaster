extends RefCounted
## The people the sim has inside a building, in its interior in place (interior3d.gd mounted by SituShell.open with
## {live = true}), for any building of the town. sim3d_chars.gd calls sync() once per frame with the roster of the
## open house: sim character id -> {def (CharBuilder), name, station, doing (the trace's: work, home, sleep...)}.
##
## The forge written by hand (no "cast" in its data) keeps interior3d's own live_sync. Every other interior brings
## its stations, named seats and beds and a scripted cast (docs/interior3d.md, «Gente por datos»): here the sim's
## people are driven as cast actors with one step each, made from what the sim says:
##   work at a station   -> that zone, with the animation the data's cast uses there (two at one zone: the second takes
##                          another free zone)
##   home                -> a seat (as the cast sits on it), the hearth, or standing by the kitchen spot
##   sleep               -> lying on a bed; with no bed left (or a baby: no baby body), not drawn
##   anything else       -> a client: at the "shop" spot facing the counter; in a tavern, drinking on a seat
## Who is new comes in by the door (or, with `snap`, is already at its place: the house was opened with people in it);
## who the sim no longer has inside walks out of the door and is freed.

const BABY_AGE := 3
const GOING := {"work": "va a su puesto", "home": "en casa", "sleep": "se va a dormir", "client": "entra"}


static func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[SituLive] " + msg)


static func generic(view: Node) -> bool:
	return view.B != null and (view.B.d as Dictionary).has("cast")


static func _info(view: Node) -> Dictionary:
	## what the data of the interior gives to place people: {work: zone -> step, sit: seat -> step, lie: bed -> step,
	## beds: [names], seats: [names], tavern: bool}
	if view.has_meta("situ_live"):
		return view.get_meta("situ_live")
	var B = view.B
	var info := {"work": {}, "sit": {}, "lie": {}, "beds": [], "seats": [], "tavern": B.zones.has("bar") or B.zones.has("tables")}
	for c: Dictionary in B.d.get("cast", []):
		for st: Dictionary in c.get("steps", []):
			if st.has("zone") and not info.work.has(String(st.zone)):
				info.work[String(st.zone)] = st
			elif st.has("sit") and not info.sit.has(String(st.sit)):
				info.sit[String(st.sit)] = st
			elif st.has("lie") and not info.lie.has(String(st.lie)):
				info.lie[String(st.lie)] = st
	var names: Array = (B.named as Dictionary).keys()
	names.sort()
	# beds and seats by the catalog of pieces (data/interiors/muebles.json: "lie", "seat"). The ones the cast already
	# uses go first: the data says how one sits there (look, off, face)
	var mb: Dictionary = Interior3DBuilder.muebles()
	for pass_i in 2:
		for nm: String in names:
			var piece: Dictionary = mb.get(String(B.named[nm].id), {})
			var known: bool = info.sit.has(nm) or info.lie.has(nm)
			if (pass_i == 0) != known:
				continue
			if piece.has("lie") and not info.beds.has(nm):
				info.beds.append(nm)
			if piece.get("seat", false) and not info.seats.has(nm):
				info.seats.append(nm)
	view.set_meta("situ_live", info)
	dbg("%s: %d work zones with a scripted animation, %d beds %s, %d seats %s%s" % [String(view.data_path).get_file(), info.work.size(),
		info.beds.size(), info.beds, info.seats.size(), info.seats, ", tavern" if info.tavern else ""])
	return info


static func _want(r: Dictionary) -> String:
	var doing := String(r.doing)
	if int((r.def as Dictionary).get("age", 30)) < BABY_AGE:
		return "cradle"
	if doing in ["work", "work_night"]:
		return "work"
	if doing == "sleep":
		return "sleep"
	if doing == "home":
		return "home"
	return "client"


static func _taken(view: Node, me: String, place: String) -> bool:
	for id in view.live_actors:
		if id != me and String(view.live_actors[id].get("place", "")) == place and String(view.live_actors[id].get("key", "")) != "out":
			return true
	return false


static func _place(view: Node, id: String, want: String, r: Dictionary, keep: String) -> String:
	## the place of a person: "zone:<id>", "seat:<name>", "bed:<name>", "tile:<spot>", "hidden"
	var B = view.B
	var info := _info(view)
	var cands := []
	match want:
		"cradle":
			return "hidden"
		"work":
			var st := String(r.station)
			if B.zones.has(st):
				cands.append("zone:" + st)
			for z in B.d.get("stations", {}):  # no station of its own, or somebody at it: another zone, crafts and sales first
				if String(B.d.stations[z].get("kind", "")) in ["craft", "sales", "service"]:
					cands.append("zone:" + String(z))
			for z in B.d.get("stations", {}):
				if String(B.d.stations[z].get("kind", "")) == "storage":
					cands.append("zone:" + String(z))
			cands.append("tile:shop")
		"sleep":
			for nm in info.beds:
				cands.append("bed:" + String(nm))
			cands.append("hidden")
		"home":
			var seats: Array = info.seats
			if not seats.is_empty():
				cands.append("seat:" + String(seats[0]))
			if B.zones.has("hearth"):
				cands.append("zone:hearth")
			for i in range(1, seats.size()):
				cands.append("seat:" + String(seats[i]))
			cands.append("tile:kitchen")
		_:
			if info.tavern:
				for nm in info.seats:
					if int(B.named[nm].floor) == 0:
						cands.append("seat:" + String(nm))
			cands.append("tile:shop")
	if keep != "" and cands.has(keep) and not _taken(view, id, keep):
		return keep  # nobody changes place from one frame to the next
	for c: String in cands:
		if c.begins_with("tile:") or c == "hidden" or not _taken(view, id, c):
			return c
	return "tile:shop"


static func _spot(view: Node, name: String) -> Array:
	## [floor, tile] of a spot of the data, else of the entrance
	var B = view.B
	var sp: Dictionary = B.d.get("spots", {})
	for nm in [name, "shop", "kitchen"]:
		if sp.has(nm) and sp[nm] is Array and sp[nm][1] is Array:
			return [int(sp[nm][0]), Vector2i(int(sp[nm][1][0]), int(sp[nm][1][1]))]
	var e: Dictionary = B.d.entrance
	return [0, Vector2i(int(e.tile[0]), int(e.tile[1]))]


static func _step(view: Node, a: Dictionary, want: String, place: String) -> Dictionary:
	var B = view.B
	var info := _info(view)
	var kind := place.get_slice(":", 0)
	var what := place.get_slice(":", 1)
	match kind:
		"zone":
			var st: Dictionary = (info.work.get(what, {}) as Dictionary).duplicate()
			st.erase("carry")
			st["zone"] = what
			if not st.has("anim"):
				st["anim"] = "stir" if what == "hearth" else "Interact"
			if not st.has("say"):
				st["say"] = "guisa en el hogar" if what == "hearth" else "trabaja (%s)" % view.zone_name(what)
			return st
		"seat":
			var st: Dictionary = (info.sit.get(what, {}) as Dictionary).duplicate()
			st["sit"] = what
			if want == "client":
				st["anim"] = "drink"
				st["say"] = "bebe"
			elif not st.has("anim") or want == "home":
				st["anim"] = String(st.get("anim", "sit_bench"))
				st["say"] = "en casa"
			return st
		"bed":
			var st: Dictionary = (info.lie.get(what, {}) as Dictionary).duplicate()
			st["lie"] = what
			st["say"] = "duerme"
			return st
	# a tile: the spot, or the free tile nearest to it nobody stands on
	var sp := _spot(view, what)
	var f := int(sp[0])
	var t: Vector2i = sp[1]
	var near: Vector2i = view._near_untaken(a, f, view._tile_xyz(f, t))
	if near != Vector2i(-99, -99):
		t = near
	var st := {"tile": [f, [t.x, t.y]], "anim": "Idle_Talking" if want == "client" else "Idle", "say": {"client": "compra", "home": "en casa", "work": "trabaja"}.get(want, "dentro")}
	# facing the counter (a client), else the first station of that floor
	var look := ""
	for z in ["counter", "bar", "desk", "hearth"]:
		if B.zones.has(z) and int(B.zones[z].floor) == f and look == "":
			look = z
	if look == "":
		for z in B.zones:
			if int(B.zones[z].floor) == f and look == "":
				look = String(z)
	if look != "":
		var zt: Vector2i = B.zones[look].tile
		st["look"] = [zt.x, zt.y]
	return st


static func _send(view: Node, a: Dictionary, step: Dictionary, snap: bool) -> void:
	view._cast_stop(a)
	a.path = []
	a.erase("claim")
	a.erase("push_to")
	a.shown = true
	a.step = step
	var tgt: Array = view._cast_target(a, step)
	if snap:
		a.floor = int(tgt[0])
		a.tile = tgt[1]
		(a.node as Node3D).position = view._tile_xyz(a.floor, a.tile)
		a.legs = []
	else:
		a.legs = view._legs_to(a, int(tgt[0]), tgt[1])
	a.state = "arrive"
	a.timer = 0.0
	(a.node as Node3D).visible = int(a.floor) <= int(view.top)


static func _hide(view: Node, a: Dictionary, say: String) -> void:
	view._cast_stop(a)
	a.path = []
	a.legs = []
	a.erase("step")
	a.shown = false
	a.state = "idle"
	a.timer = 5.0
	a.tile = Vector2i(-60, -60 - (view.people as Array).find(a))
	a.doing = say
	(a.node as Node3D).visible = false


static func _out(view: Node, a: Dictionary) -> void:
	var B = view.B
	if not a.get("shown", true):
		(a.node as Node).queue_free()
		(view.people as Array).erase(a)
		view.live_actors.erase(a.sim_id)
		return
	view._cast_stop(a)
	a.path = []
	a.erase("step")
	var e: Dictionary = B.d.entrance
	a.legs = view._legs_to(a, 0, Vector2i(int(e.tile[0]), int(e.tile[1]))) + [{"path": [B.entrance_out(1), B.entrance_out(2)]}, {"free": true}]
	a.state = "arrive"
	a.doing = "sale"


static func sync(view: Node, roster: Dictionary, snap := false) -> void:
	if not generic(view):
		view.live_snap = snap
		view.live_sync(roster)
		view.live_snap = false
		return
	var B = view.B
	var ids: Array = roster.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = roster[id]
		if not view.live_actors.has(id):
			var a: Dictionary = view._actor(r.def, "cast", "", B.entrance_out(2))
			a.name = String(r.name)
			a.sim_id = id
			a.steps = []
			a.step_i = 0
			a.legs = []
			a.looks = []
			a.key = ""
			a.place = ""
			a.fresh = true
			view._name_tag(a)
			(a.node as Node3D).visible = int(a.floor) <= int(view.top)
			view.live_actors[id] = a
			dbg("%s %s (%s%s)" % [a.name, "is in" if snap else "comes in", r.doing, " at " + String(r.station) if String(r.station) != "" else ""])
		var la: Dictionary = view.live_actors[id]
		var want := _want(r)
		var place := _place(view, id, want, r, String(la.place) if String(la.key).get_slice("|", 0) == want else "")
		var key := "%s|%s" % [want, place]
		if key == String(la.key):
			continue
		# not in the middle of a step or of a flight of stairs: the way is worked out from a tile
		if la.state == "walk" or (not (la.legs as Array).is_empty() and not (la.legs[0] as Dictionary).has("go")):
			continue
		la.key = key
		la.place = place
		var here: bool = snap or (la.get("fresh", false) and place == "hidden")
		la.fresh = false
		if place == "hidden":
			_hide(view, la, "en la cuna (bebé)" if want == "cradle" else "duerme (sin cama libre)")
		else:
			_send(view, la, _step(view, la, want, place), here)
			la.doing = String(GOING.get(want, "entra"))
		dbg("%s -> %s" % [la.name, key])
	for id in view.live_actors.keys():
		var la: Dictionary = view.live_actors[id]
		if roster.has(id) or String(la.key) == "out":
			continue
		if la.state == "walk" or (not (la.legs as Array).is_empty() and not (la.legs[0] as Dictionary).has("go")):
			continue
		la.key = "out"
		la.place = ""
		dbg("%s leaves" % la.name)
		_out(view, la)
	if view._live_label:
		var lines := []
		for id in view.live_actors:
			var a: Dictionary = view.live_actors[id]
			if String(a.key) != "out":
				lines.append("%s: %s" % [a.name, a.doing])
		view._live_label.text = ("Dentro (según la sim):\n" + "\n".join(lines)) if not lines.is_empty() else "Nadie dentro ahora"
