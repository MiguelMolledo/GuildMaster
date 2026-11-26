class_name InteriorBridge3D
extends RefCounted
## The house open in place (docs/3d/plan.md M3D-3) as the game's InteriorView sees it: InteriorView keeps everything it
## does today (the building's bar, its panels, the station menu, the Forja viva, the orders) but does not draw its
## room; it asks this bridge where things are on screen and what is under the pointer, in the 3D interior that
## Prueba3D's SituShell mounted in the house (interior3d.gd: its stations are the sim's zones, its people are the
## sim's: SituLive). Reads only.

const PICK_PERSON: float = 26.0   # screen units around a person's chest
const PICK_STATION: float = 30.0  # around a station's middle, when the floor under the pointer is not its tile
const STATION_LIFT: float = 1.0   # the station's middle, metres over its floor
const FALLBACK_LIFT: float = 0.2  # a zone without a station in the layout (missing()): its mark, by the floor

var town: Town3D = null
var sim: Sim = null   # the game's (WorldView3D.build): what the building is, for the zones its layout lacks
var building: String = ""


func view() -> Node3D:
	return town.inside_view if town != null else null


func ready() -> bool:
	var v := view()
	return v != null and is_instance_valid(v) and v.B != null


## The screen point of a 3D point of the interior's local space (Vector2.INF behind the camera).
func _screen(local: Vector3) -> Vector2:
	var v := view()
	var p: Vector3 = (v.interior as Node3D).global_transform * local
	if town.cam.is_position_behind(p):
		return Vector2.INF
	return town.cam.unproject_position(p)


## The middle of a station's tiles on screen (Vector2.INF if the interior has no such zone).
func station_screen(zone: String) -> Vector2:
	if not ready():
		return Vector2.INF
	if not (view().B.zones as Dictionary).has(zone):
		var k := missing().find(zone)
		return _screen(_spot_point(k, missing().size())) if k >= 0 else Vector2.INF
	var zd: Dictionary = view().B.zones[zone]
	var c := Vector3.ZERO
	for t: Vector2i in zd.tiles:
		c += view().B.tile_pos(int(zd.floor), t)
	c /= maxf(1.0, float((zd.tiles as Array).size()))
	return _screen(c + Vector3(0, STATION_LIFT, 0))


func has_station(zone: String) -> bool:
	return ready() and ((view().B.zones as Dictionary).has(zone) or missing().has(zone))


## The zones of the sim's building that the 3D layout has no station for (the counter of a level-1 workshop, the farm's
## fields): their marks stand where SituLive puts whoever works on them (the layout's "shop" spot, else the entrance),
## side by side.
func missing() -> Array:
	if not ready() or sim == null or not sim.state.buildings.has(building):
		return []
	var out: Array = []
	var type := str(sim.state.buildings[building]["type"])
	for z: Dictionary in sim.catalog.buildings().get(type, {}).get("zones", []):
		if not (view().B.zones as Dictionary).has(str(z["id"])):
			out.append(str(z["id"]))
	return out


func _spot_point(k: int, n: int) -> Vector3:
	var B: Variant = view().B
	var sp: Dictionary = B.d.get("spots", {})
	var f := 0
	var t := Vector2i(int(B.d.entrance.tile[0]), int(B.d.entrance.tile[1]))
	if sp.get("shop") is Array and sp["shop"][1] is Array:
		f = int(sp["shop"][0])
		t = Vector2i(int(sp["shop"][1][0]), int(sp["shop"][1][1]))
	# low, by the floor: the marks of the stations next to the door hang at STATION_LIFT and would cover these
	return B.tile_pos(f, t) + Vector3(0.7 * (float(k) - float(n - 1) / 2.0), FALLBACK_LIFT, 0.0)


## The street door's tile on screen.
func door_screen() -> Vector2:
	if not ready() or not (view().B.d as Dictionary).has("entrance"):
		return Vector2.INF
	var e: Array = view().B.d.entrance.tile
	return _screen(view().B.tile_pos(0, Vector2i(int(e[0]), int(e[1]))) + Vector3(0, 0.6, 0))


## The station under the pointer: the zone of the floor tile it points at, else the nearest station middle.
func pick_station(screen: Vector2) -> String:
	if not ready():
		return ""
	var hit: Array = view()._pick(screen)
	var z: String = view()._zone_at(hit[0], hit[1])
	if z != "":
		return z
	var best := ""
	var bd := PICK_STATION
	for zone: String in (view().B.zones as Dictionary).keys() + missing():
		if view().B.zones.has(zone) and view().zone_name(zone) == "":
			continue
		var at := station_screen(zone)
		if at != Vector2.INF and at.distance_to(screen) < bd:
			bd = at.distance_to(screen)
			best = zone
	return best


## A person of the player's family inside, under the pointer ("" if none).
func pick_character(screen: Vector2, selectable: Callable) -> String:
	if not ready():
		return ""
	var best := ""
	var bd := PICK_PERSON
	for id: Variant in view().live_actors:
		var a: Dictionary = view().live_actors[id]
		var n: Node3D = a.node
		if not n.is_visible_in_tree() or str(a.get("want", "")) == "out" or not selectable.call(str(id)):
			continue
		var p := n.global_position + Vector3(0, 1.0, 0)
		if town.cam.is_position_behind(p):
			continue
		var d := town.cam.unproject_position(p).distance_to(screen)
		if d < bd:
			bd = d
			best = str(id)
	return best


## The street door: the pointer on its tile, or near its point on screen.
func is_door(screen: Vector2) -> bool:
	if not ready() or not (view().B.d as Dictionary).has("entrance"):
		return false
	var e: Array = view().B.d.entrance.tile
	var hit: Array = view()._pick(screen)
	if int(hit[0]) == 0 and hit[1] == Vector2i(int(e[0]), int(e[1])):
		return true
	var at := door_screen()
	return at != Vector2.INF and at.distance_to(screen) < 22.0


## The station under the mouse lit (the interior's own highlight), "" = none.
func hover(zone: String) -> void:
	if ready():
		view().set_hover(zone)


## Where a person of the sim stands inside, on screen (Vector2.INF if not drawn).
func person_screen(id: String) -> Vector2:
	if not ready() or not view().live_actors.has(id):
		return Vector2.INF
	var n: Node3D = view().live_actors[id].node
	if not n.is_visible_in_tree():
		return Vector2.INF
	return town.cam.unproject_position(n.global_position + Vector3(0, 1.0, 0))


## The upper / lower floor of the open house (the room's «Planta alta» button, the wheel's floor in 2D); returns the
## top floor now shown.
func toggle_floor() -> int:
	if not ready():
		return 0
	var floors: Array = view().B.floors
	var top := int(view().top)
	var i := floors.find(top)
	view().set_top(int(floors[(i + 1) % floors.size()]))
	return int(view().top)


func floors() -> int:
	return (view().B.floors as Array).size() if ready() else 1
