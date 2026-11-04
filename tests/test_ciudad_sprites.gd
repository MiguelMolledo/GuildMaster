extends "res://tests/test_case.gd"
## The drawn doors (docs/protocolos/generar-ciudad.md §Puertas): every building and filler house scene has its
## Marker2D "Door", and the catalogue the town tools read (data/building_sprites.json, exported by
## tools/city/sprites_catalog.py) says exactly what the markers say.

const CATALOG: String = "res://data/building_sprites.json"
const SIDES: Dictionary = {"SW": Vector2i(0, 1), "SE": Vector2i(1, 0), "NE": Vector2i(0, -1), "NW": Vector2i(-1, 0)}


func _catalog() -> Dictionary:
	var txt := FileAccess.get_file_as_string(CATALOG)
	var d: Variant = JSON.parse_string(txt)
	return (d as Dictionary).get("scenes", {}) if d is Dictionary else {}


func _scenes_that_need_a_door() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at("res://game/visuals/buildings"):
		if f.ends_with(".tscn") and not f.begins_with("_"):
			out.append("buildings/" + f.get_basename())
	for f: String in DirAccess.get_files_at("res://game/visuals/props"):
		if f.begins_with("lot_house_") and f.ends_with(".tscn"):
			out.append("props/" + f.get_basename())
	return out


func test_every_building_and_house_scene_has_its_door_marker() -> void:
	var need := _scenes_that_need_a_door()
	check(need.size() >= 20, "buildings and filler houses to check (%d)" % need.size())
	for key: String in need:
		var m := VisualPaths.door_of(key.get_slice("/", 0), key.get_slice("/", 1))
		check(not m.is_empty(), "%s has a Door marker" % key)
		if not m.is_empty():
			check(SIDES.has(str(m["side"])), "%s: side %s is SW, SE, NE or NW" % [key, m["side"]])


func test_the_catalogue_says_what_the_markers_say() -> void:
	var cat := _catalog()
	check(not cat.is_empty(), "data/building_sprites.json has scenes")
	for key: String in _scenes_that_need_a_door():
		check(cat.has(key), "%s is in the catalogue" % key)
	for key: String in cat:
		var e: Dictionary = cat[key]
		var m := VisualPaths.door_of(key.get_slice("/", 0), key.get_slice("/", 1))
		if m.is_empty():
			check(false, "%s: the catalogue has a door, the scene has no marker" % key)
			continue
		var door: Dictionary = e["door"]
		eq(str(m["side"]), str(door["side"]), "%s: side" % key)
		eq(m["tile"], Vector2i(int(door["tile"][0]), int(door["tile"][1])), "%s: tile" % key)
		eq(m["footprint"], Vector2i(int(e["footprint"][0]), int(e["footprint"][1])), "%s: footprint" % key)
		eq(m["position"], Vector2(float(door["px"][0]), float(door["px"][1])), "%s: threshold" % key)
		eq(bool(m["mirror"]), bool(e["mirror"]), "%s: mirror" % key)
		eq(str(m["back"]), str(e["back"]), "%s: back" % key)
		eq(str(m["front"]), str(e["front"]), "%s: front" % key)


func test_the_door_tile_is_outside_the_footprint_on_its_side() -> void:
	for key: String in _scenes_that_need_a_door():
		var m := VisualPaths.door_of(key.get_slice("/", 0), key.get_slice("/", 1))
		if m.is_empty():
			continue
		var t: Vector2i = m["tile"]
		var f: Vector2i = m["footprint"]
		var inner: Vector2i = t - (SIDES[str(m["side"])] as Vector2i)
		check(inner.x >= 0 and inner.x < f.x and inner.y >= 0 and inner.y < f.y and
			not (t.x >= 0 and t.x < f.x and t.y >= 0 and t.y < f.y),
			"%s: door tile %s just outside the footprint %s on %s" % [key, t, f, m["side"]])


func test_a_back_view_and_its_front_point_at_each_other() -> void:
	for key: String in _scenes_that_need_a_door():
		var kind := key.get_slice("/", 0)
		var m := VisualPaths.door_of(kind, key.get_slice("/", 1))
		if m.is_empty() or str(m["back"]) == "":
			continue
		var b := VisualPaths.door_of(kind, str(m["back"]))
		check(not b.is_empty(), "%s: its back view %s has a marker" % [key, m["back"]])
		if not b.is_empty():
			eq(str(b["front"]), key.get_slice("/", 1), "%s: the back view points back" % key)
			check(str(b["side"]) != str(m["side"]), "%s: the back view's door is on another face" % key)
