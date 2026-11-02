extends "res://tests/test_case.gd"
## Scale B (docs/arte/escala.md): the buildings stand at 1:1 (no scaled sprite) and a tall building goes see-through
## while the selected person stands behind it (WorldView._update_see_through, data/view.json see_through).

const BLD := "bld_0001"
const TOMAS := "chr_0003"

var cat := Catalog.load_from()


func _world(state: WorldState) -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(state, cat)
	return v


func test_building_sprites_are_not_scaled() -> void:
	for kind: String in ["buildings", "props"]:
		var dir := DirAccess.open("res://game/visuals/" + kind)
		for f: String in dir.get_files():
			if not f.ends_with(".tscn"):
				continue
			var n := (load("res://game/visuals/%s/%s" % [kind, f]) as PackedScene).instantiate()
			var spr := n.get_node_or_null("Sprite") as Sprite2D
			if spr != null:
				eq(spr.scale, Vector2.ONE, "%s/%s: Sprite at 1:1" % [kind, f])
			n.free()


func test_forge_goes_see_through_with_the_selected_person_behind() -> void:
	var st: WorldState = NewGame.from_scenario("town_e_start")["state"]
	st.characters[TOMAS]["position"] = [25, 19]  # behind the forge (25..27, 20..23), under its roof on screen
	st.characters[TOMAS]["path"] = []
	var v := _world(st)
	var forge := v.building_visual(BLD)
	v.sync(0.0)
	eq(forge.modulate.a, 1.0, "nobody selected: opaque")
	v.select(TOMAS)
	v.sync(0.0)
	check(forge.modulate.a < 1.0, "Tomás selected behind it: see-through")
	st.characters[TOMAS]["position"] = [26, 25]  # in front of it
	v.sync(0.0)
	eq(forge.modulate.a, 1.0, "in front: opaque again")
	v.free()
