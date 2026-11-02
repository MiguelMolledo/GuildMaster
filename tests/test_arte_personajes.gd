extends "res://tests/test_case.gd"
## Character sprites from Guild Renew (tools/art/personajes_guild.py): every visual id has its frames in 8 directions,
## the greybox hidden (kept), the H8 identity painted by the shader (hair, skin, family colours) and the motion
## following the sim (walk towards path[0], idle when stopped, forge/work at a station).

var cat := Catalog.load_from()
const IDS: Array[String] = ["artisan_m", "artisan_f", "worker_m", "worker_f", "townsfolk_m", "townsfolk_f"]
const DIRS: Array[String] = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


func test_every_character_has_its_frames_in_eight_directions() -> void:
	for id: String in IDS:
		var n := VisualPaths.instantiate("characters", id)
		var sp := n.get_node("Sprite") as AnimatedSprite2D
		check(sp.visible and not (n.get_node("Greybox") as CanvasItem).visible, "%s: sprite shown, greybox kept hidden" % id)
		check(sp.material is ShaderMaterial, "%s: the identity shader" % id)
		for m: String in ["idle", "walk"]:
			for d: String in DIRS:
				check(sp.sprite_frames.get_frame_count("%s_%s" % [m, d]) > 0, "%s: %s_%s" % [id, m, d])
		if id.begins_with("artisan") or id.begins_with("worker"):
			for d: String in DIRS:
				check(sp.sprite_frames.get_frame_count("forge_%s" % d) > 0 and sp.sprite_frames.get_frame_count("work_%s" % d) > 0,
					"%s: forge and work %s" % [id, d])
		eq(VisualPaths.top_height(n, 0.0), 48.0, "%s: 48 px" % id)
		n.free()


func test_facing_of_a_move() -> void:
	eq(CharacterView.dir_of(Vector2(1, 0)), "se", "one column on: down-right")
	eq(CharacterView.dir_of(Vector2(0, 1)), "sw", "one row on: down-left")
	eq(CharacterView.dir_of(Vector2(-1, 0)), "nw", "one column back")
	eq(CharacterView.dir_of(Vector2(0, -1)), "ne", "one row back")
	eq(CharacterView.dir_of(Vector2(1, 1)), "s", "diagonal: straight down")
	eq(CharacterView.dir_of(Vector2(1, -1)), "e", "across: right")


func test_identity_colours_reach_the_shader_and_motion_follows_the_path() -> void:
	var st: WorldState = NewGame.from_scenario("town_e_start")["state"]
	var id := ""
	for c: String in st.characters:
		if str(st.characters[c].get("controlled_by", "")) == "human":
			id = c
			break
	var ch: Dictionary = st.characters[id]
	var fam: Dictionary = st.families[str(ch["family"])]
	var v := CharacterView.new()
	v.setup(ch, fam)
	var mat := (v.visual().get_node("Sprite") as AnimatedSprite2D).material as ShaderMaterial
	var idn := Identity.of(st, id)
	eq(mat.get_shader_parameter("primary"), idn["primary"], "family primary colour on the clothes")
	eq(mat.get_shader_parameter("secondary"), idn["secondary"], "family secondary colour")
	eq(mat.get_shader_parameter("hair"), idn["hair"], "H8 hair")
	eq(mat.get_shader_parameter("skin"), idn["skin"], "H8 skin")
	var pos: Array = ch["position"]
	var walking := ch.duplicate(true)
	walking["path"] = [[int(pos[0]) + 1, int(pos[1])]]
	v.follow(walking, 1, 0.0)
	eq(v.animation_name(), "walk_se", "walking one column on")
	var stopped := ch.duplicate(true)
	stopped["path"] = []
	v.follow(stopped, 1, 0.0)
	eq(v.animation_name(), "idle_se", "stopped: idle, same facing")
	var other := VisualPaths.instantiate("characters", "artisan_m")
	var other_mat := (other.get_node("Sprite") as AnimatedSprite2D).material
	check(other_mat != mat, "each person has its own material (local to scene)")
	other.free()
	v.free()


func test_station_motion_in_the_interior() -> void:
	var r := NewGame.from_scenario("town_e_start")
	var sim := Sim.new(r["state"], cat)
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, "bld_0001", "", true)
	var zones: Dictionary = sim.state.buildings["bld_0001"]["zones"]
	zones["anvil"]["occupant"] = "chr_0001"
	zones["anvil"]["job"] = {"recipe": "forge_sword"}
	eq(v.station_motion(sim.state, "chr_0001", "anvil"), "forge", "hammering at the anvil")
	zones["anvil"]["job"] = null
	eq(v.station_motion(sim.state, "chr_0001", "anvil"), "idle", "no job: waits")
	zones["counter"]["occupant"] = "chr_0001"
	zones["counter"]["job"] = {"recipe": "x"}
	eq(v.station_motion(sim.state, "chr_0001", "counter"), "work", "other stations: work")
	v.free()
