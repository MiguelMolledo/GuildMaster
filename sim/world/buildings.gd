class_name Buildings
extends RefCounted
## Entering, leaving and moving between stations of a building (GDD 4.6.4). Owner: subgrim «edificio».
## Contract: docs/contratos/h2_forja.md.
##
## A character is either on the map (location "") or inside one building (location = bld_id). Inside, it does not
## walk the map: move_to is refused with not_inside_map until it leaves (exit_building).
## enter_building from afar walks to the door (Movement) and keeps itself as the first order of the actor's
## order_queue, marked "walking": true, until the arrival; step() then lets the actor in. A live order clears the
## queue and so cancels the entry, like a new move_to replaces a route. Orders queued after it run once inside.


## {"ok", "reason"}: whether `actor` may enter `building` now (own building: its family's or its own; or public, H3,
## and then only while the market is open: market_closed).
static func can_enter(sim: Sim, actor: String, building: String) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	if not bool(ch.get("alive", true)):
		return Orders.fail("dead")
	if not st.buildings.has(building):
		return Orders.fail("unknown_building")
	if not owns(st, actor, building) and not is_public(sim, building):
		return Orders.fail("not_your_building")
	if Market.shop_closed(sim, building) and str(ch.get("location", "")) != building:
		return Orders.fail("market_closed")  # a public shop opens with the market (H3, GDD 4.5.1); Market puts out at closing
	var loc := str(ch.get("location", ""))
	if loc != "" and loc != building:
		return Orders.fail("inside_other_building")
	return Orders.ok()


## Whether anybody may go in (H3): a building without owner whose type says "public": true (the armory). Opening
## hours and what can be done inside belong to its system (Market for shops).
static func is_public(sim: Sim, building: String) -> bool:
	var b: Dictionary = sim.state.buildings.get(building, {})
	if b.is_empty() or str(b.get("owner", "")) != "":
		return false
	return bool(sim.catalog.buildings().get(str(b.get("type", "")), {}).get("public", false))


## Whether the building belongs to the actor or to the actor's family.
static func owns(st: WorldState, actor: String, building: String) -> bool:
	if not st.buildings.has(building) or not st.characters.has(actor):
		return false
	var owner := str(st.buildings[building].get("owner", ""))
	if owner == "":
		return false
	return owner == actor or owner == str(st.characters[actor].get("family", ""))


## {"type": "enter_building", "actor", "building"}.
static func order_enter(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var r := can_enter(sim, actor, bld)
	if not r["ok"]:
		return r
	var ch: Dictionary = sim.state.characters[actor]
	if str(ch.get("location", "")) == bld:
		return Orders.ok()  # already inside: nothing to do
	var door: Array = sim.state.buildings[bld].get("door", [])
	if door.size() != 2:
		return Orders.fail("no_door")
	var pos: Array = ch.get("position", [0, 0])
	if int(pos[0]) == int(door[0]) and int(pos[1]) == int(door[1]):
		ch["path"] = []
		ch["move_progress"] = 0
		_go_in(sim, actor, bld)
		return Orders.ok()
	var walk := Movement.move_to(sim, actor, door)
	if not walk["ok"]:
		return walk
	var pending := {"type": "enter_building", "actor": actor, "building": bld, "walking": true}
	(ch["order_queue"] as Array).push_front(pending)
	if OS.is_debug_build():
		print("[Buildings] %s camina a la puerta de %s (door=%s)" % [actor, bld, door])
	return Orders.ok()


## {"type": "exit_building", "actor"}: interrupts the actor's work (D11) and puts it on the door tile.
static func order_exit(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	var bld := str(ch.get("location", ""))
	if bld == "" or not st.buildings.has(bld):
		return Orders.fail("not_inside")
	_leave_station(sim, actor)
	var door: Array = st.buildings[bld].get("door", ch.get("position", [0, 0]))
	ch["location"] = ""
	ch["station"] = ""
	ch["position"] = [int(door[0]), int(door[1])]
	ch["path"] = []
	ch["move_progress"] = 0
	sim.events.append({"type": "building_left", "actor": actor, "building": bld})
	if OS.is_debug_build():
		print("[Buildings] %s sale de %s (door=%s)" % [actor, bld, ch["position"]])
	return Orders.ok()


## {"type": "go_to_station", "actor", "zone"}: inside, a station that exists and is free (or already its own).
## Leaving a station where the actor works interrupts that work (D11), as leaving the building does.
static func order_go_to_station(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var zone := str(o.get("zone", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	var bld := str(ch.get("location", ""))
	if bld == "" or not st.buildings.has(bld):
		return Orders.fail("not_inside")
	var zones: Dictionary = st.buildings[bld].get("zones", {})
	if not zones.has(zone):
		return Orders.fail("unknown_station")
	var occupant := str(zones[zone].get("occupant", ""))
	if occupant != "" and occupant != actor:
		return Orders.fail("station_busy")
	if str(ch.get("station", "")) == zone:
		return Orders.ok()
	_leave_station(sim, actor)
	zones[zone]["occupant"] = actor
	ch["station"] = zone
	sim.events.append({"type": "station_taken", "actor": actor, "building": bld, "zone": zone})
	if OS.is_debug_build():
		print("[Buildings] %s ocupa el puesto %s de %s" % [actor, zone, bld])
	return Orders.ok()


## Arrivals at doors: an actor whose first queued order is a walking enter_building, now still on its door, goes in.
static func step(sim: Sim) -> void:
	var st := sim.state
	for id: String in st.characters:
		var ch: Dictionary = st.characters[id]
		var queue: Array = ch.get("order_queue", [])
		if queue.is_empty() or not (ch.get("path", []) as Array).is_empty():
			continue
		var first: Dictionary = queue[0]
		if str(first.get("type", "")) != "enter_building" or not bool(first.get("walking", false)):
			continue
		var bld := str(first.get("building", ""))
		if not st.buildings.has(bld) or str(ch.get("location", "")) != "":
			continue
		var door: Array = st.buildings[bld].get("door", [])
		var pos: Array = ch.get("position", [0, 0])
		if door.size() == 2 and int(pos[0]) == int(door[0]) and int(pos[1]) == int(door[1]) \
				and can_enter(sim, id, bld)["ok"]:
			queue.pop_front()
			_go_in(sim, id, bld)
		# Otherwise OrderQueue.step re-applies it next minute (it walks again, or it is refused).


## Whether the actor has a job running at some station (the job's actor, wherever it is).
static func job_zone(sim: Sim, actor: String) -> String:
	var bld := str(sim.state.characters.get(actor, {}).get("location", ""))
	if bld == "" or not sim.state.buildings.has(bld):
		return ""
	var zones: Dictionary = sim.state.buildings[bld].get("zones", {})
	var ids: Array = zones.keys()
	ids.sort()
	for z: String in ids:
		var job: Variant = zones[z].get("job")
		if job is Dictionary and str((job as Dictionary).get("actor", "")) == actor:
			return z
	return ""


static func _go_in(sim: Sim, actor: String, bld: String) -> void:
	var ch: Dictionary = sim.state.characters[actor]
	ch["location"] = bld
	ch["station"] = ""
	sim.events.append({"type": "building_entered", "actor": actor, "building": bld})
	if OS.is_debug_build():
		print("[Buildings] %s entra en %s" % [actor, bld])


## Frees the actor's station, interrupting its work there first (Production returns the inputs, D11).
static func _leave_station(sim: Sim, actor: String) -> void:
	var ch: Dictionary = sim.state.characters[actor]
	var bld := str(ch.get("location", ""))
	if bld == "" or not sim.state.buildings.has(bld):
		return
	var working := job_zone(sim, actor)
	if working != "":
		Production.interrupt(sim, bld, working)
	var zones: Dictionary = sim.state.buildings[bld].get("zones", {})
	var station := str(ch.get("station", ""))
	if zones.has(station) and str(zones[station].get("occupant", "")) == actor:
		zones[station]["occupant"] = ""
	ch["station"] = ""

