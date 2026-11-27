class_name Town3D
extends "res://game/world3d/town/sim3d_chars.gd"
## The 3D town of the game, fed by the sim as it runs (docs/3d/plan.md §1). It is Prueba3D's town (town/pueblo.gd: the
## houses by type and level, the yards, extras, trees and hedges of the map) and its townsfolk (town/sim3d_chars.gd:
## CharBuilder bodies dressed by job, family and age, gaits matched to the ground speed, seats, door lanterns, lit
## windows, light and weather by the hour), with the reads of the recorded trace replaced by the live state:
## - `trace` is the live feed: what Prueba3D's trace carried, built from the state when the town is mounted (the map,
##   the walkable grid, the families, the characters, the buildings) and refreshed every game minute (who is inside
##   where and what they do, each building's finished upgrades and works, who appeared, changed or left).
## - Positions are read every frame from the state and interpolated with Game.step_fraction(), as the 2D view does
##   (CharacterView.tile_position: the sim moves by tiles, one tile per minutes_per_tile); the speed on the ground
##   comes from the next tile of the path.
## - The light, the season and the phases come from the sim's clock and data/time.json.
## Reads only: the orders go out through WorldView3D. Nothing here is saved; a load builds the town again.

var sim: Sim = null
var frac: float = 0.0                 # how far towards the next step (Game.step_fraction)
var real_per_minute: float = 0.0625   # real seconds per game minute at the current speed (WorldView3D sets it)
var _minute: int = -1
var _sigs: Dictionary = {}            # chr -> the signature its body was built with (rebuilt when it changes)


const Opt3D := preload("res://game/world3d/town/opt3d.gd")


## The builders' shared caches (materials, meshes, scenes of the kit): emptied when the view goes away (the quit).
static func clear_caches() -> void:
	for d: Dictionary in [HouseBuilder._scenes, HouseBuilder._palette, HouseBuilder._mat_cache, HouseBuilder._prop_mats,
			HouseBuilder._tints, LandmarkBuilder._cat, LandmarkBuilder._scenes, LandmarkBuilder._tints,
			LandmarkBuilder._tinted, BuildingTypes._data, CharBuilder._cache, Opt3D.active, Opt3D._canon]:
		d.clear()
	LandmarkBuilder._water = null
	CharBuilder._outline = null
	RoadBuilder._noise = null


## --transicion=<k>: the house's opening and closing last k times Prueba3D's (0.2: a flow in a hurry; 0: at once).
static func transition_arg() -> float:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--transicion="):
			return maxf(0.0, a.substr(13).to_float())
	return 1.0


## M3D-5: the town's own sound (Prueba3D's, game/world3d/audio) through the game's AudioDirector: its files by id of
## data/audio.json, its buses into the game's, the music still the AudioDirector's. Off without an AudioDirector, with
## the Dummy driver (headless: nothing is heard, and a playback stopped while quitting leaks) or with --sonido=no.
func _sound_on() -> bool:
	var ad := _audio_director()
	# headless (no window): off, a playback stopped while quitting leaks there; with a window and the Dummy driver of a
	# test run it runs (the mixer goes on, nothing is heard): what it costs is measured like that
	if ad == null or DisplayServer.get_name() == "headless" or "--sonido=no" in OS.get_cmdline_user_args():
		return false
	preload("res://game/world3d/audio/sonido_pool.gd").resolver = ad.streams
	ad.town_sound = true
	return true


static func _audio_director() -> AudioDirector:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("App/AudioDirector") as AudioDirector if tree != null else null


## The town's sound stops with the town (a menu screen, the title) and lets the AudioDirector's ambience back.
func sound_active(on: bool) -> void:
	var so := get_node_or_null("Sonido")
	if so == null:
		return
	so.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for n: String in ["Musica", "Ambiente", "Efectos", "Voces", "Lejos"]:
		var i := AudioServer.get_bus_index(n)
		if i >= 0:
			AudioServer.set_bus_mute(i, not on)
	var ad := _audio_director()
	if ad != null:
		ad.town_sound = on


func _exit_tree() -> void:
	if use_sound:
		sound_active(false)
		preload("res://game/world3d/audio/sonido_pool.gd").resolver = Callable()


## Before add_child: the state the town is built from.
func setup(s: Sim) -> void:
	sim = s
	use_cart = false
	use_sound = _sound_on()
	transition_k = transition_arg()
	names_on = false  # the names show for the hovered and the selected only (name_shown)
	var st := s.state
	mapd = (s.catalog.maps().get(st.map_id, {}) as Dictionary).duplicate(true)
	season_id = Clock.season(int(st.clock["minute"]), s.catalog.time)
	trace = _feed()
	_minute = int(st.clock["minute"])
	t_min = float(_minute)
	speed_i = SPEEDS.find(1.0)


## The live feed in the shape of Prueba3D's trace (version 2, tools/sim_trace.gd of the prueba), from the state now.
func _feed() -> Dictionary:
	var st := sim.state
	var now := int(st.clock["minute"])
	var m: Dictionary = sim.catalog.maps().get(st.map_id, {})
	var grid := Grid.for_state(sim.catalog, st)
	var mask: Array = []
	for r: int in grid.height:
		var row := ""
		for c: int in grid.width:
			row += "1" if grid.walkable(c, r) else "0"
		mask.append(row)
	var fams := {}
	for f: String in st.families:
		var d: Dictionary = st.families[f]
		fams[f] = {"name": str(d.get("name", "")), "color": str((d.get("colors", {}) as Dictionary).get("primary", "#808080")),
			"controlled_by": str(d.get("controlled_by", ""))}
	var feed := {"version": 2,
		"meta": {"seed": st.world_seed, "map": st.map_id, "start_minute": now, "end_minute": now + 1000000,
			"minutes_per_tile": Movement.minutes_per_tile(sim.catalog), "days": [], "live": true},
		"map": {"size": m.get("size", [0, 0]), "rows": m.get("rows", []), "walkable": mask,
			"stalls": m.get("stalls", {}), "social_points": m.get("social_points", []), "spawns": m.get("spawns", {})},
		"families": fams, "buildings": {}, "characters": {}, "festivals": _festivals_now(), "events": _events_now()}
	_fest_sig = _festival_sig(feed["festivals"], feed["events"])   # what the town is built with
	for b: String in st.buildings:
		var d: Dictionary = st.buildings[b]
		feed["buildings"][b] = {"type": str(d.get("type", "")), "origin": d.get("origin", []),
			"footprint": d.get("footprint", []), "door": d.get("door", []), "owner": str(d.get("owner", "")),
			"plot": Plots.plot_of(sim, b), "first": 0, "tl": [_building_row(b, now)]}
	var hall: Dictionary = m.get("town_hall", {})
	if not hall.is_empty():
		feed["buildings"]["town_hall"] = {"type": "town_hall", "origin": hall.get("origin", []),
			"footprint": hall.get("footprint", []), "door": hall.get("service", hall.get("door", [])), "owner": "",
			"first": 0, "tl": [[0, "normal", [], [], []]]}
	for id: String in st.characters:
		var c := _char_entry(id, now)
		if not c.is_empty():
			feed["characters"][id] = c
	return feed


## [minute, state, finished upgrades, upgrade works, building works] of a building now (the trace's timeline row).
func _building_row(b: String, now: int) -> Array:
	var d: Dictionary = sim.state.buildings[b]
	var w: Dictionary = Upgrades.work(sim.state, b)
	var c: Dictionary = d.get("construction", {}) if d.get("construction") is Dictionary else {}
	return [0, str(d.get("state", "normal")), Upgrades.owned(sim.state, b),
		[] if w.is_empty() else [str(w.get("upgrade", "")), int(w.get("start", now)), int(w.get("end", now))],
		[] if c.is_empty() else [str(c.get("kind", "")), int(c.get("start", now)), int(c.get("end", now))]]


## A character's entry of the feed ({} for the dead): who it is and its one state row.
func _char_entry(id: String, now: int) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[id]
	if not bool(ch.get("alive", true)) or not ch.has("position"):
		return {}
	var job: Variant = ch.get("job")
	return {"id": id, "name": str(ch.get("name", "")), "family": str(ch.get("family", "")),
		"female": bool(ch.get("female", false)), "sex": "f" if bool(ch.get("female", false)) else "m",
		"age": Kin.age(sim, id), "birth_day": int(ch.get("birth_day", 0)),
		"occupation": str(ch.get("occupation", "")), "profession": str(ch.get("profession", "")),
		"role": str((job as Dictionary).get("role", "")) if job is Dictionary else "",
		"home": str(ch.get("home", "")), "family_role": SimQuery.family_role(st, id),
		"visual": ch.get("visual", {}) if ch.get("visual") is Dictionary else {},
		"parents": ch.get("parents", []), "spouse": str(ch.get("spouse", "")),
		"employer": Staff.employer(st, id), "first": 0, "pos": [], "st": [_state_row(id, now)]}


## [minute, location, doing, bubble, station, spot] now (location "~" = not in the town).
func _state_row(id: String, now: int) -> Array:
	var ch: Dictionary = sim.state.characters[id]
	var loc := str(ch.get("location", ""))
	if SimQuery.offstage(sim.state, id):
		loc = "~"
	var station := str(ch.get("station", "")) if loc != "" else ""
	var t: Variant = ch.get("town")
	var spot := ""
	if t is Dictionary and loc == "" and str((t as Dictionary).get("spot", "")) != "":
		spot = "%s|%d" % [(t as Dictionary)["spot"], int((t as Dictionary).get("slot", -1))]
	return [0, loc, SimQuery.doing(sim, id, now), SimQuery.bubble_of(sim, id), station, spot]


## What makes a body different: rebuilt when it changes (married, came of age, hired, another family...).
func _body_sig(c: Dictionary) -> String:
	var age: int = int(c.get("age", 0))
	var stage := 0 if age < 8 else (1 if age < 16 else (2 if age < 55 else 3))
	return "%s|%s|%s|%s|%s|%d" % [c.get("family", ""), c.get("occupation", ""), c.get("profession", ""),
		c.get("family_role", ""), c.get("employer", ""), stage]


func _spawn_person(id: String, skin: StandardMaterial3D = null, head_mesh: SphereMesh = null) -> void:
	super(id, skin, head_mesh)
	(people[id] as Dictionary)["id"] = id
	_sigs[id] = _body_sig(trace.characters[id])


func _remove_person(id: String) -> void:
	if people.has(id):
		(people[id].node as Node).queue_free()
	people.erase(id)
	_chr.erase(id)
	_sigs.erase(id)


## Once per game minute: the state rows, who appeared, changed or left, the buildings' timeline rows.
func _refresh_minute(now: int) -> void:
	var st := sim.state
	var added := 0
	var rebuilt := 0
	for id: String in st.characters:
		var c := _char_entry(id, now) if not trace.characters.has(id) else {}
		if trace.characters.has(id):
			var ch: Dictionary = st.characters[id]
			if not bool(ch.get("alive", true)):
				_remove_person(id)
				trace.characters.erase(id)
				continue
			var e: Dictionary = trace.characters[id]
			e["st"] = [_state_row(id, now)]
			if now % 60 == 0:  # who someone is changes slowly: checked once a game hour
				var fresh := _char_entry(id, now)
				if _body_sig(fresh) != str(_sigs.get(id, "")):
					_remove_person(id)
					trace.characters[id] = fresh
					_spawn_person(id)
					rebuilt += 1
			if people.has(id):
				var p: Dictionary = people[id]
				p["st"] = e["st"]
		elif not c.is_empty():
			trace.characters[id] = c
			_spawn_person(id)
			added += 1
	for id: String in trace.characters.keys():
		if not st.characters.has(id):
			_remove_person(id)
			trace.characters.erase(id)
	for b: String in st.buildings:
		if trace.buildings.has(b):
			trace.buildings[b]["tl"] = [_building_row(b, now)]
	var season := Clock.season(now, sim.catalog.time)
	if season != season_id:
		_change_season(season)
	_check_festivals()
	if (added > 0 or rebuilt > 0) and OS.is_debug_build():
		print("[Town3D] minute %d: %d people added, %d rebuilt (%d in town)" % [now, added, rebuilt, people.size()])


# ---------------------------------------------------------------- festivals of the sim (M3D-5)
## What FiestasPueblo reads (Prueba3D's trace format, tools/sim_trace.gd there): the sim's festivals upcoming and in
## force, and the global events in force, read from the state as they are now.
func _festivals_now() -> Array:
	var f: Dictionary = sim.state.festivals if sim.state.festivals is Dictionary else {}
	var out: Array = []
	for key: String in ["active", "upcoming"]:
		for inst: Dictionary in f.get(key, []):
			out.append(_festival_record(inst))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) < int(b["start"]))
	return out


func _festival_record(inst: Dictionary) -> Dictionary:
	var d := Festivals.def_of(sim, str(inst.get("def", "")))
	var day := int(inst.get("day", 0))
	var sched: Array = []
	for sc: Dictionary in d.get("schedule", []):
		var needs := str(sc.get("needs", ""))
		sched.append({"what": str(sc.get("what", "")), "at": day * Clock.MINUTES_PER_DAY + int(sc.get("hour", 0)) * 60,
			"needs": needs, "on": needs == "" or Festivals.part_on(inst, needs)})
	return {"id": str(inst.get("id", "")), "def": str(inst.get("def", "")), "kind": str(d.get("kind", "")),
		"size": str(d.get("size", "")), "day": day, "start": int(inst.get("start", 0)), "end": int(inst.get("end", 0)),
		"announce": int(inst.get("announce", 0)), "hosts": (inst.get("hosts", []) as Array).duplicate(),
		"couple": (inst.get("couple", []) as Array).duplicate(), "schedule": sched, "view": Festivals.view_of(sim, inst)}


func _events_now() -> Array:
	var out: Array = []
	for ev: Dictionary in sim.state.events_active:
		out.append({"id": str(ev.get("id", "")), "def": str(ev.get("def", "")), "start": int(ev.get("start", 0)),
			"end": int(ev.get("end", 0)), "by": str(ev.get("by", ""))})
	return out


var _fest_sig: String = ""


func _festival_sig(fests: Array, evs: Array) -> String:
	return JSON.stringify([fests.map(func(x: Dictionary) -> String: return "%s|%d|%d" % [x["id"], x["start"], x["end"]]),
		evs.map(func(x: Dictionary) -> String: return "%s|%d" % [x["id"], x["end"]])])


## Once a game minute: when the sim's festivals or events change (one put on the calendar, one over), the town's
## festival dressing is laid out again from them (FiestasPueblo plans its pieces when it is made).
func _check_festivals() -> void:
	var fests := _festivals_now()
	var evs := _events_now()
	var sig := _festival_sig(fests, evs)
	if sig == _fest_sig:
		return
	_fest_sig = sig
	trace["festivals"] = fests
	trace["events"] = evs
	if vivo == null:
		return
	var old: Node3D = vivo.get("fiestas")
	if old != null and is_instance_valid(old):
		for inst: Dictionary in old.get("insts"):
			if bool(inst.get("mounted", false)):
				old.call("_unmount", inst)
		remove_child(old)
		old.queue_free()
	var fp: Node3D = preload("res://game/world3d/town/fiestas_pueblo.gd").new()
	add_child(fp)
	fp.call("setup", self)
	vivo.set("fiestas", fp)
	if OS.is_debug_build():
		print("[Town3D] festivals now %s, events %s: the town's dressing laid out again" % [
			fests.map(func(x: Dictionary) -> String: return str(x["def"])), evs.map(func(x: Dictionary) -> String: return str(x["def"]))])


## The sim's season changed (every 2 days): the light and the weather read it live; the crowns, the leaves and the
## grass are tinted again (vida.gd). The crops of the fields keep the look they were built with until the town is
## built again (a load, a new game).
func _change_season(season: String) -> void:
	if OS.is_debug_build():
		print("[Town3D] season %s -> %s" % [season_id, season])
	season_id = season
	if clima != null and clima.get("vida") != null:
		var v: RefCounted = clima.get("vida")
		v.set("season", season)
		v.call("_crowns")


## The prueba's count of who is inside each building, over its roof, is not the game's (the HUD and the signs say it):
## drawn fully transparent (its code shows and hides it).
func _anchor_buildings() -> void:
	super()
	for b: Variant in bld_anchor:
		(bld_anchor[b].label as Label3D).transparency = 1.0


# ---------------------------------------------------------------- what the prueba read from the trace, live

## Every building can change its look while the game runs (upgrades, works): looked at once per game minute.
func _live_setup() -> void:
	_live_blds = []
	for b: String in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		if (bd.get("origin", []) as Array).size() == 2 and bld_anchor.has(b):
			_live_blds.append(b)


func _sim_buildings() -> void:
	var now := float(sim.state.clock["minute"])
	for b: String in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		if (bd.get("origin", []) as Array).size() == 2:
			sim_buildings[Vector2i(int(bd.origin[0]), int(bd.origin[1]))] = _bld_at(b, now)


## [cols, rows] of a building type: its footprint in the catalog (data/buildings), the town hall's from the map.
func _footprint_of(type: String) -> Vector2i:
	if type == "town_hall":
		var f: Array = mapd.get("town_hall", {}).get("footprint", [3, 3])
		return Vector2i(int(f[0]), int(f[1]))
	if not _fp_cache.has(type):
		var fp: Array = (sim.catalog.buildings().get(type, {}) as Dictionary).get("footprint", [3, 3])
		_fp_cache[type] = Vector2i(int(fp[0]), int(fp[1]))
	return _fp_cache[type]


func _parse_days() -> void:
	pass  # _day_info reads the clock's own phases


## The phase starts of the day of minute t, from data/time.json (the trace carried them per day).
func _day_info(t: float) -> Dictionary:
	var m := int(t)
	var season := Clock.season(m, sim.catalog.time)
	var starts: Dictionary = sim.catalog.time["phase_starts"][season]
	var b := {}
	for ph: String in starts:
		b[ph] = int(starts[ph])
	return {"day": Clock.day(m), "season": season, "bounds": b}


func tile_at(p: Dictionary, _t: float) -> Vector2:
	var ch: Dictionary = sim.state.characters.get(str(p.get("id", "")), {})
	if ch.is_empty():
		return Vector2.ZERO
	return CharacterView.tile_position(ch, int(mpt), frac)


## Plan metres per game minute towards the next tile of the path (zero when standing).
func motion_at(p: Dictionary, _t: float) -> Vector2:
	var ch: Dictionary = sim.state.characters.get(str(p.get("id", "")), {})
	var path: Array = ch.get("path", [])
	if path.is_empty():
		return Vector2.ZERO
	var pos: Array = ch.get("position", [0, 0])
	var nxt: Array = path[0]
	var d := Vector2(float(nxt[0]) - float(pos[0]), float(nxt[1]) - float(pos[1]))
	if maxf(absf(d.x), absf(d.y)) > 1.0:
		return Vector2.ZERO
	return Vector2(d.x, -d.y) * 2.0 / mpt


func real_per_game_minute() -> float:
	return real_per_minute


var keys_on: bool = true  # the camera keys act (off while a menu screen is open: WorldView3D)


func _cam_free() -> bool:
	return keys_on and not _busy


## The game's HUD is on top: of Prueba3D's own only what its code touches (a hidden hint and forge label). The houses
## with an interior in place open when the game asks (open_building), not at the start nor by zooming in.
func _make_hud() -> void:
	_hint = Label.new()
	_hint.visible = false
	add_child(_hint)
	_forge_label = Label3D.new()
	_forge_label.visible = false
	_forge_label.set_meta("was", false)
	add_child(_forge_label)
	for h: Node3D in houses:
		if h.has_meta("interior"):
			situ_mode = true


# ---------------------------------------------------------------- a house open in place (M3D-3)

## Opens the house of sim building `b` where it stands (SituShell: the roof melts, the walls in front go down, the
## interior of its type and level with its upgrades, the sim's people at their places): false if its house has no
## interior in place (the game then shows its 2D interior).
func open_building(b: String) -> bool:
	if not bld_anchor.has(b):
		return false
	var h: Node3D = bld_anchor[b].house
	if h == null or not is_instance_valid(h) or not h.has_meta("interior"):
		return false
	if inside and situ_house == h:
		looking = false   # it was open by the zoom: now the game's (its panels come on top)
		return true
	if inside:
		_close_now()
	situ_mode = true
	_mount(h)
	live_bld = b
	if inside_view == null:
		return false
	inside_view.set_process_unhandled_input(false)
	_open(false)
	var ui: Variant = inside_view.get("_ui")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false  # the game's interior bar and panels instead (activate showed it)
	if OS.is_debug_build():
		print("[Town3D] open %s in place (%s, %s)" % [b, h.name, String(h.get_meta("interior")).get_file()])
	return true


## Mounts the interior of sim building `b`'s house, closed (the cost of loading its furniture goes to the town's
## build, not to the first opening). One house is mounted at a time: opening another mounts that one instead.
func premount(b: String) -> void:
	if not bld_anchor.has(b) or inside:
		return
	var h: Node3D = bld_anchor[b].house
	if h == null or not is_instance_valid(h) or not h.has_meta("interior"):
		return
	situ_mode = true
	_mount(h)
	live_bld = b
	if inside_view != null:
		var ui: Variant = inside_view.get("_ui")
		if ui is CanvasLayer:
			(ui as CanvasLayer).visible = false
		inside_view.set_process_unhandled_input(false)


## Closes the house open in place as Prueba3D does: the roof comes back, the walls go up and the camera slides back
## to where it was before the house opened (the flows wait for it: WorldView3D.settling).
func close_building() -> void:
	if inside and not _busy:
		_focus_auto = looking   # looking (zoom): no camera move back, as in the prueba
		looking = false
		_close()


## The same at once (another house opens, the town is rebuilt).
func _close_now() -> void:
	looking = false
	if not inside:
		return
	situ_cut.set_on(false, true)
	inside_view.activate(false)
	if inside_view.live:
		inside_view.live_clear()
	inside = false
	_busy = false


# ---------------------------------------------------------------- looking inside by zooming in (as Prueba3D)
## Zooming in over a house with an interior in place (camera size FOCUS_ZOOM or less, no house open by the game)
## opens it where it stands to look inside: its people at their places, no panels, no orders (a click goes on to the
## town as always). Zooming out past UNFOCUS_ZOOM or moving away closes it. WorldView3D turns it off while the game
## has a house open, a menu is open or the keys are off.
var looking: bool = false
var look_on: bool = true


func _look_update() -> void:
	if _busy or not situ_mode:
		return
	if looking:
		if not inside:
			looking = false
			return
		var fp := situ_house.global_position
		var off := Vector2(target.x - fp.x, target.z - fp.z).length()
		if not look_on or cam.size > UNFOCUS_ZOOM or off > 8.0:
			close_building()
		return
	if inside or not look_on or cam.size > FOCUS_ZOOM:
		return
	var h := _house_near(target, 1.0)
	if h == null:
		return
	situ_mode = true
	_mount(h)
	live_bld = _bld_of(h)
	if inside_view == null:
		return
	inside_view.set_process_unhandled_input(false)
	looking = true
	_open(true)
	var ui: Variant = inside_view.get("_ui")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	if OS.is_debug_build():
		print("[Town3D] looking inside %s (%s) by zooming in" % [h.name, live_bld])


func open_house_building() -> String:
	return live_bld if inside else ""


func _roster_extra(roster: Dictionary) -> void:
	Inn3D.add_guests(self, roster)  # a tavern open in place: its guests, seated (inn3d.gd)


var _reopen: String = ""  # the house open in place was built again (an upgrade done, works): it opens again


func _before_rehouse(h: Node3D) -> void:
	if inside and situ_house == h:
		_reopen = live_bld
	super(h)


func _rehoused(old: Node3D, nh: Node3D) -> void:
	super(old, nh)
	if _reopen != "":
		var b := _reopen
		_reopen = ""
		open_building.call_deferred(b)



var name_shown: Dictionary = {}  # chr -> true: whose name shows (the hovered and the selected: Marks3D)
var _dragging: bool = false       # the middle button pans the camera (as the 2D town's): pressed over the town,
                                  # then followed in _input (before the GUI, which keeps the motion over a control)


func _input(e: InputEvent) -> void:
	if not _dragging:
		return
	if e is InputEventMouseMotion:
		pan_screen((e as InputEventMouseMotion).relative)
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE \
			and not (e as InputEventMouseButton).pressed:
		_dragging = false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		if (e as InputEventMouseButton).pressed and keys_on:
			_dragging = true
			follow_id = ""
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var mb := e as InputEventMouseButton
		var steps: float = mb.factor if mb.factor > 0.0 else 1.0
		_zoom_by(pow(0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88, steps))
		get_viewport().set_input_as_handled()
	elif e is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(0.2, (e as InputEventMagnifyGesture).factor))  # trackpad pinch
		get_viewport().set_input_as_handled()


## The bodies never jump when somebody starts walking or changes path (the owner saw it: «da un salto y luego anda»).
## The sim gives an order and walks its first minute in the same step, so the next tile is already half way when the
## view first sees the path; a new path drops the old progress; a seat, a stall's shelter in the rain or the jitter
## put the standing body off its tile. Here the drawn body follows the place _apply computed at most at SMOOTH_K times
## the walking speed (a diagonal step), so it catches up in a few frames instead of popping; a real jump (more than
## SMOOTH_SNAP metres: going in or out, appearing) or a body that was not drawn goes straight. Only the view.
const SMOOTH_K: float = 1.7
const SMOOTH_SNAP: float = 3.5
var _drawn: Dictionary = {}   # chr -> where its body was drawn last frame
var smooth_on: bool = not ("--suavizado=no" in OS.get_cmdline_user_args())


func _smooth_bodies(delta: float) -> void:
	var sps := 1.0 / maxf(real_per_minute, 0.0001)   # game minutes per real second (the last running speed in pause)
	var lim := SMOOTH_K * 2.0 * sqrt(2.0) / maxf(mpt, 1.0) * sps * delta
	for id: Variant in people:
		var n: Node3D = people[id].node
		if not n.visible:
			_drawn.erase(id)
			continue
		var want := n.position
		var was: Vector3 = _drawn.get(id, Vector3.INF)
		if not smooth_on or was == Vector3.INF or was.distance_to(want) > SMOOTH_SNAP:
			_drawn[id] = want
			continue
		var at := was.move_toward(want, lim)
		n.position = at
		_drawn[id] = at


## Moves the ground under the pointer by `d` screen units (a middle drag): what was under it stays under it.
func pan_screen(d: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var k := cam.size / maxf(1.0, vp.y)  # metres per screen unit (orthographic: size = the view's height)
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var fwd := Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	var s := maxf(0.2, sin(deg_to_rad(pitch)))  # screen up runs along the ground longer than it looks
	target -= right * d.x * k
	target += fwd * d.y * k / s
	_update_camera()


func _process(delta: float) -> void:
	_cam_keys(delta)
	if _dragging and not keys_on:
		_dragging = false
	if sim == null or trace.is_empty():
		return
	var now := int(sim.state.clock["minute"])
	if now != _minute:
		_minute = now
		_refresh_minute(now)
	t_min = float(now) + frac
	_apply(t_min)
	_smooth_bodies(delta)
	_look_update()
	if inside and situ_cut != null:
		situ_cut.speed = 1.0 / maxf(transition_k, 0.01)
	for id: Variant in people:  # names only for who is under the mouse or selected (as the 2D town)
		var lab: Label3D = people[id].name
		var on := name_shown.has(id) and (people[id].node as Node3D).visible
		if lab.visible != on:
			lab.visible = on
	if follow_id != "" and people.has(follow_id):
		var n: Node3D = people[follow_id].node
		if n.visible:
			target = target.lerp(n.position + Vector3(0, 1, 0), minf(1.0, delta * 4.0))
			_update_camera()


## The camera over tile `t` (keeps its zoom and turn).
func look_at_tile(t: Vector2) -> void:
	var p := _tp(t.x, t.y)
	target = Vector3(p.x, 0.0, -p.y)
	_update_camera()


## Where a character stands on screen (Vector2.INF if not drawn).
func screen_of(id: String) -> Vector2:
	if not people.has(id) or not (people[id].node as Node3D).visible:
		return Vector2.INF
	var at: Vector3 = (people[id].node as Node3D).global_position + Vector3(0, 1.0, 0)
	if cam.is_position_behind(at):
		return Vector2.INF
	return cam.unproject_position(at)
