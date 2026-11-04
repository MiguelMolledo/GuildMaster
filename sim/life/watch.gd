class_name Watch
extends RefCounted
## The town watch (docs/gdd/04f_vida_y_fiestas.md §4.24.4, 4.22.6.2 brought forward; docs/contratos/vida.md): the
## family fam_watch («Guardia de la villa»), made the first time the living town runs: `gate` guards by day, one at
## each main gate (they greet the visitors), `night` guards walking the map's patrols at night (with a lantern: the
## view), and `festival` in the plaza on a festival day. Off duty they are not on the map (the guardhouse: the town
## hall's door). A cry, a brawl or a raid within respond_tiles sends the guards on duty there (respond); they have
## arrived within reach_tiles (Incidents reads arrived). The council pays them: no ledger. A constable (alguacil) in
## office adds one night guard [propuesta]. Figures: data/life/life.json "watch".
##
## state.town.watch: guards {chr: role}, dispatch {chr: {tile, incident, since}}. character.guard: {role, post, wp,
## wait_until, greet_until}.


static func cfg(sim: Sim) -> Dictionary:
	return Life.cfg(sim.catalog).get("watch", {})


static func book(st: WorldState) -> Dictionary:
	var b: Variant = st.town.get("watch")
	if b is Dictionary and (b as Dictionary).size() > 0:
		return b
	Life.ensure(st)
	return st.town["watch"]


## The guards of the town (ids, sorted).
static func guards(st: WorldState) -> Array:
	var w: Variant = st.town.get("watch")
	var out: Array = []
	if w is Dictionary:
		for g: Variant in ((w as Dictionary).get("guards", {}) as Dictionary):
			if st.characters.has(str(g)) and bool(st.characters[str(g)].get("alive", true)):
				out.append(str(g))  # a guard that died of old age is replaced (_ensure)
	out.sort()
	return out


static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	if now % 60 == 0 or (st.town["watch"]["guards"] as Dictionary).is_empty():
		_ensure(sim)  # the roles change with the offices (a constable) at most: once an hour
	var phase := Clock.phase(now, sim.catalog.time)
	var fest := Life.festival(sim)
	for g: String in guards(st):
		_step_one(sim, g, now, phase, fest)


## The roles the town wants: gate_<gate> per main gate, night_<n>, festival_<n>.
static func roles(sim: Sim) -> Array:
	var c := cfg(sim)
	var out: Array = []
	var gates := Life.gates(sim)
	var wanted: Array = []
	for g: Variant in c.get("gates", []):
		if gates.has(str(g)):
			wanted.append(str(g))
	var names: Array = gates.keys()
	names.sort()
	for g: String in names:
		if wanted.size() >= int(c.get("gate", 2)):
			break
		if not g in wanted:
			wanted.append(g)
	for g: String in wanted.slice(0, int(c.get("gate", 2))):
		out.append("gate_" + g)
	var nights := int(c.get("night", 2)) + (1 if _constable(sim) else 0)
	for i: int in nights:
		out.append("night_%d" % (i + 1))
	for i: int in int(c.get("festival", 1)):
		out.append("festival_%d" % (i + 1))
	return out


## Whether the constable's office (alguacil) is held: +1 night guard [propuesta].
static func _constable(sim: Sim) -> bool:
	var office := str(cfg(sim).get("alguacil_office", "constable"))
	var o: Dictionary = sim.state.offices.get(office, {})
	for s: Dictionary in o.get("seats", []):
		if str(s.get("holder", "")) != "":
			return true
	return false


## Makes the watch's family and a guard per role that has none (the first time; a constable adds one).
static func _ensure(sim: Sim) -> void:
	var st := sim.state
	var b := book(st)
	var have := {}
	for g: String in guards(st):
		have[str(b["guards"][g])] = g
	var want := roles(sim)
	if have.size() == want.size() and have.size() > 0:
		return
	var c := cfg(sim)
	Life.service_family(st, Life.FAMILY_WATCH, "family.watch", c.get("livery", {"primary": "#7a2a2a", "secondary": "#d8b050"}))
	var post := barracks(sim)
	for role: String in want:
		if have.has(role):
			continue
		var key := "life|watch|%s" % role
		var span: Array = c.get("age", [24, 40])
		var look := Cast.newcomer(sim, key, false, 30)
		var id := Life.add_person(sim, Life.FAMILY_WATCH, str(look.get("name", "?")), false,
			Kin.randi_range(st, key + "|age", int(span[0]), int(span[1])), c.get("stats", {}), c.get("equipment", {}), post,
			{"guard": {"role": role, "wp": 0}})
		st.characters[id]["visual"]["hair"] = int(look.get("hair", 0))
		st.characters[id]["visual"]["skin"] = int(look.get("skin", 0))
		b["guards"][id] = role
		sim.events.append({"type": "guard_hired", "character": id, "role": role})
		if OS.is_debug_build():
			print("[Watch] guardia %s «%s»: %s" % [id, st.characters[id]["name"], role])


## Where the guards come from and go back to: the town hall's door (else the plaza).
static func barracks(sim: Sim) -> Array:
	var th: Dictionary = Life.map(sim).get("town_hall", {})
	if (th.get("service", []) as Array).size() == 2:
		return (th["service"] as Array).duplicate()
	return Life.plaza(sim)


static func on_duty(sim: Sim, role: String, phase: String, fest: bool) -> bool:
	if role.begins_with("gate_"):
		return phase in ["dawn", "day"]
	if role.begins_with("night_"):
		return phase == "night"
	if role.begins_with("festival_"):
		return fest and phase in ["day", "dusk"]
	return false


## The post of a gate guard: three tiles in from its gate (two, one if those are not walkable): on the street, in
## the open (not under the first houses).
static func gate_post(sim: Sim, gate: String) -> Array:
	var g: Array = Life.gates(sim).get(gate, Life.plaza(sim))
	var size: Array = Life.map(sim).get("size", [40, 40])
	var dc := 1 if int(g[0]) == 0 else (-1 if int(g[0]) >= int(size[0]) - 1 else 0)
	var dr := 1 if int(g[1]) == 0 else (-1 if int(g[1]) >= int(size[1]) - 1 else 0)
	for k: int in [3, 2, 1]:
		var t := [int(g[0]) + dc * k, int(g[1]) + dr * k]
		if TownLife._walkable(sim, int(t[0]), int(t[1])):
			return t
	return (g as Array).duplicate()


static func _step_one(sim: Sim, g: String, now: int, phase: String, fest: bool) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[g]
	var gd: Dictionary = ch.get("guard", {})
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	var t: Dictionary = ch["town"]
	var role := str(gd.get("role", ""))
	var b := book(st)
	var duty := on_duty(sim, role, phase, fest)
	var sent: Dictionary = b["dispatch"].get(g, {})
	if not sent.is_empty() and bool(ch.get("offstage", false)):
		Life.put_on(sim, g, barracks(sim))  # called out of the guardhouse
	if bool(ch.get("offstage", false)):
		if duty:
			Life.put_on(sim, g, barracks(sim))
			gd["wp"] = 0
			sim.events.append({"type": "guard_on_duty", "character": g, "role": role})
		return
	if not sent.is_empty():
		var tile: Array = sent.get("tile", [])
		if Life.dist(Life.tile_of(st, g), tile) <= int(cfg(sim).get("reach_tiles", 1)):
			if not bool(sent.get("arrived", false)):
				sent["arrived"] = true
				sent["arrived_at"] = now
				sim.events.append({"type": "guard_arrived", "character": g, "incident": str(sent.get("incident", ""))})
				if OS.is_debug_build():
					print("[Watch] %s llega al suceso %s" % [g, sent.get("incident", "")])
			TownLife._set_state(sim, g, t, "social", "guard_respond")
			return
		TownLife._go_tile(sim, g, t, _near_free(sim, tile), now)
		TownLife._set_state(sim, g, t, "walking", "guard_respond")
		return
	if not duty:
		if TownLife._go_tile(sim, g, t, barracks(sim), now):
			Life.take_off(sim, g)
			sim.events.append({"type": "guard_off_duty", "character": g, "role": role})
		return
	if role.begins_with("gate_"):
		if not gd.get("post") is Array:
			gd["post"] = gate_post(sim, role.substr(5))
		var post: Array = gd["post"]
		if TownLife._go_tile(sim, g, t, post, now):
			var greet := int(gd.get("greet_until", -1)) > now
			if not greet and now % 2 == 0:
				for v: String in Visitors.alive(st):
					var vis: Dictionary = st.characters[v].get("visitor", {})
					if str(vis.get("gate", "")) == role.substr(5) and now - int(vis.get("arrived", -999)) <= 3:
						gd["greet_until"] = now + int(cfg(sim).get("greet_minutes", 10))
						sim.events.append({"type": "guard_greets", "character": g, "visitor": v})
						greet = true
						break
			TownLife._set_state(sim, g, t, "social" if greet else "guarding", "guard_greet" if greet else "guard_post")
		else:
			TownLife._set_state(sim, g, t, "walking", "")
		return
	if role.begins_with("festival_"):
		if TownLife._go_tile(sim, g, t, Life.plaza(sim), now):
			TownLife._set_state(sim, g, t, "guarding", "guard_post")
		return
	_patrol(sim, g, gd, t, now)


## The night round: the map's patrols (data/maps "patrols"), one per guard in turn; waits at each tile.
static func _patrol(sim: Sim, g: String, gd: Dictionary, t: Dictionary, now: int) -> void:
	var pats: Array = Life.map(sim).get("patrols", [])
	if pats.is_empty():
		TownLife._go_tile(sim, g, t, Life.plaza(sim), now)
		return
	var n := str(gd.get("role", "night_1")).get_slice("_", 1).to_int()
	var route: Array = pats[(n - 1) % pats.size()].get("tiles", [])
	if route.is_empty():
		return
	var wp := int(gd.get("wp", 0)) % route.size()
	if int(gd.get("wait_until", -1)) > now:
		TownLife._set_state(sim, g, t, "guarding", "guard_patrol")
		return
	if TownLife._go_tile(sim, g, t, route[wp], now):
		gd["wp"] = (wp + 1) % route.size()
		gd["wait_until"] = now + int(cfg(sim).get("patrol_wait_minutes", 10))
		TownLife._set_state(sim, g, t, "guarding", "guard_patrol")
	else:
		TownLife._set_state(sim, g, t, "walking", "guard_patrol")


## A walkable tile next to `tile` (where a guard stands to step in).
static func _near_free(sim: Sim, tile: Array) -> Array:
	for d: Array in [[0, 1], [1, 0], [0, -1], [-1, 0], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		var c := int(tile[0]) + int(d[0])
		var r := int(tile[1]) + int(d[1])
		if TownLife._walkable(sim, c, r):
			return [c, r]
	return tile.duplicate()


## A cry at `tile` (a brawl, a raid, a call for help): the guards on duty within respond_tiles (all of them with
## `all`) go there. Returns the ones sent.
static func respond(sim: Sim, tile: Array, incident: String, all: bool = false) -> Array:
	var st := sim.state
	var b := book(st)
	var fest := Life.festival(sim)
	var phase := Clock.phase(int(st.clock["minute"]), sim.catalog.time)
	var out: Array = []
	for g: String in guards(st):
		var ch: Dictionary = st.characters[g]
		var role := str(ch.get("guard", {}).get("role", ""))
		if not on_duty(sim, role, phase, fest) and not all:
			continue
		if bool(ch.get("offstage", false)) and not all:
			continue
		if not all and Life.dist(Life.tile_of(st, g), tile) > int(cfg(sim).get("respond_tiles", 12)):
			continue
		b["dispatch"][g] = {"tile": tile.duplicate(), "incident": incident, "since": int(st.clock["minute"]), "arrived": false}
		out.append(g)
	if not out.is_empty():
		sim.events.append({"type": "watch_called", "incident": incident, "guards": out.duplicate(), "tile": tile.duplicate()})
		if OS.is_debug_build():
			print("[Watch] grito en %s (%s): acuden %s" % [tile, incident, out])
	return out


## The guards sent to `incident` that are there now.
static func arrived(st: WorldState, incident: String) -> Array:
	var out: Array = []
	var w: Variant = st.town.get("watch")
	if not w is Dictionary:
		return out
	var d: Dictionary = (w as Dictionary).get("dispatch", {})
	var ks: Array = d.keys()
	ks.sort()
	for g: String in ks:
		if str(d[g].get("incident", "")) == incident and bool(d[g].get("arrived", false)):
			out.append(g)
	return out


## The incident is over: its guards go back to their round.
static func release(st: WorldState, incident: String) -> void:
	var w: Variant = st.town.get("watch")
	if not w is Dictionary:
		return
	var d: Dictionary = (w as Dictionary).get("dispatch", {})
	for g: String in d.keys():
		if str(d[g].get("incident", "")) == incident:
			d.erase(g)


## Whether `chr` is a guard of the town.
static func is_guard(st: WorldState, chr: String) -> bool:
	return st.characters.get(chr, {}).get("guard") is Dictionary
