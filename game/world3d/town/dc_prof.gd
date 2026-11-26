extends RefCounted
## Draw-call profile of a built town (sim3d_chars --dcprof): the draw calls of the colour pass and of the shadow
## pass, split by what is drawn. Each category is hidden in turn and the drop is its share. Toggles (sun shadow,
## outline pass) are measured the same way.

const CATS := ["house_chunks", "house_walls", "house_misc", "house_roof", "house_interior", "house_props", "props", "trees",
	"cover", "nature", "people", "labels", "lanterns", "ground"]


static func classify(town: Node3D, skip: Array) -> Dictionary:
	## category -> [GeometryInstance3D]
	var out := {}
	for c in CATS:
		out[c] = []
	var houses: Array = town.houses
	var lantern_roots := {}
	for ch in town.get_children():
		if ch in skip:
			continue
		var cat := ""
		if ch is Node3D and houses.has(ch):
			for sub in ch.get_children():
				var sc := "house_misc"
				if sub.has_meta("level"):
					sc = ""
				elif sub.is_in_group("roof"):
					sc = "house_roof"
				elif String(sub.name) == "Interior":
					sc = "house_interior"
				elif String(sub.name) in ["merged", "glass"]:
					sc = "house_chunks"
				elif String(sub.name) == "props":
					sc = "house_props"
				for gi in _geo(sub, []):
					var k := sc
					if k == "":
						k = "house_walls" if gi.is_in_group("wall") else "house_misc"
					out[k].append(gi)
			continue
		if String(ch.name) == "HouseChunks":
			cat = "house_chunks"
		elif String(ch.name) == "Props":
			cat = "props"
		elif ch.is_in_group("tree"):
			cat = "trees"
		elif ch is MultiMeshInstance3D:
			cat = "cover" if ch.has_meta("cover") else "nature"
		elif ch is Label3D:
			cat = "labels"
		elif "people" in town and _is_person(town, ch):
			for gi in _geo(ch, []):
				out["labels" if gi is Label3D else "people"].append(gi)
			continue
		elif String(ch.scene_file_path).contains("Lantern"):
			cat = "lanterns"
		else:
			cat = "ground"
		out[cat].append_array(_geo(ch, []))
	return out


static func _is_person(town: Node3D, n: Node) -> bool:
	for id in town.people:
		if town.people[id].node == n:
			return true
	return false


static func _geo(n: Node, acc: Array) -> Array:
	if n is GeometryInstance3D:
		acc.append(n)
	for c in n.get_children():
		_geo(c, acc)
	return acc


static func info(vp: RID) -> Dictionary:
	var V := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var S := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var D := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var O := RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
	var P := RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	return {"color": RenderingServer.viewport_get_render_info(vp, V, D), "shadow": RenderingServer.viewport_get_render_info(vp, S, D),
		"obj": RenderingServer.viewport_get_render_info(vp, V, O), "tris_k": RenderingServer.viewport_get_render_info(vp, V, P) / 1000}


static func measure(tree: SceneTree, vp: RID, frames := 8) -> Dictionary:
	for i in 3:
		await RenderingServer.frame_post_draw
	var acc := {"color": 0, "shadow": 0, "obj": 0, "tris_k": 0}
	for i in frames:
		await RenderingServer.frame_post_draw
		var r := info(vp)
		for k in acc:
			acc[k] += r[k]
	for k in acc:
		acc[k] = acc[k] / frames
	return acc


static func profile(town: Node3D, sun: DirectionalLight3D, skip: Array) -> Dictionary:
	var vp := town.get_viewport().get_viewport_rid()
	var tree := town.get_tree()
	var cats := classify(town, skip)
	var base: Dictionary = await measure(tree, vp)
	var res := {"all": base}
	for c in CATS:
		var list: Array = cats[c]
		if list.is_empty():
			continue
		var was := []
		for gi: GeometryInstance3D in list:
			was.append(gi.visible)
			gi.visible = false
		var m: Dictionary = await measure(tree, vp)
		for i in list.size():
			list[i].visible = was[i]
		res[c] = {"n": list.size(), "color": base.color - m.color, "shadow": base.shadow - m.shadow, "tris_k": base.tris_k - m.tris_k}
	var split := tree_split(town, skip)
	for c in ["real", "cover"]:
		var list: Array = split[c]
		if list.is_empty():
			continue
		var was := _hide(list)
		var m: Dictionary = await measure(tree, vp)
		_show(list, was)
		res["trees_" + c] = {"n": list.size(), "color": base.color - m.color, "shadow": base.shadow - m.shadow, "tris_k": base.tris_k - m.tris_k}
	if sun:
		var se := sun.shadow_enabled
		sun.shadow_enabled = false
		var m: Dictionary = await measure(tree, vp)
		sun.shadow_enabled = se
		res["sun_shadow"] = {"color": base.color - m.color, "shadow": base.shadow - m.shadow}
	if "style" in town and town.style == "outline":
		town.set_style("toon")
		var m: Dictionary = await measure(tree, vp)
		town.set_style("outline")
		res["outline_pass"] = {"color": base.color - m.color, "shadow": base.shadow - m.shadow}
	return res


static func fps(tree: SceneTree, secs := 3.0) -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 10:
		await RenderingServer.frame_post_draw
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var n := 0
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		await RenderingServer.frame_post_draw
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	var frames := Engine.get_frames_drawn() - f0
	var s := (Time.get_ticks_usec() - t0) / 1e6
	return {"fps": snappedf(frames / s, 0.1), "ms": snappedf(s * 1000.0 / frames, 0.01), "vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps}


static func fps_profile(town: Node3D, sun: DirectionalLight3D, env: Environment, skip: Array) -> Dictionary:
	## frame time with one thing switched off at a time (what each costs in ms, not in draw calls)
	var tree := town.get_tree()
	var cats := classify(town, skip)
	var res := {"all": await fps(tree)}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--treeprof"):
			# only the trees, pass by pass (tree_profile): --dcprof --fpsprof --treeprof; --treeprof=fast: only treefar on / off
			res["trees_detail"] = await tree_profile(town, skip, 8, 0.7, a.trim_prefix("--treeprof").trim_prefix("="))
			return res
	for c in ["house_chunks", "props", "trees", "cover", "people", "labels", "ground", "lanterns", "house_misc"]:
		var list: Array = cats.get(c, [])
		if list.is_empty():
			continue
		var was := []
		for gi: GeometryInstance3D in list:
			was.append(gi.visible)
			gi.visible = false
		res["no_" + c] = await fps(tree)
		for i in list.size():
			list[i].visible = was[i]
	if sun:
		sun.shadow_enabled = false
		res["no_sun_shadow"] = await fps(tree)
		sun.shadow_enabled = true
		var mode := sun.directional_shadow_mode
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		res["shadow_2splits"] = await fps(tree)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		res["shadow_ortho"] = await fps(tree)
		sun.directional_shadow_mode = mode
	if env:
		var ssao := env.ssao_enabled
		env.ssao_enabled = false
		res["no_ssao"] = await fps(tree)
		env.ssao_enabled = ssao
		if env.glow_enabled:
			env.glow_enabled = false
			res["no_glow"] = await fps(tree)
			env.glow_enabled = true
	if "style" in town and town.style == "outline":
		town.set_style("toon")
		res["no_outline"] = await fps(tree)
		town.set_style("outline")
	var vpn := town.get_viewport()
	for th in [2.0, 4.0, 8.0]:
		vpn.mesh_lod_threshold = th
		res["lod_threshold_%d" % int(th)] = await fps(tree)
	vpn.mesh_lod_threshold = 1.0
	var people_shadow := []
	for gi: GeometryInstance3D in cats.get("people", []):
		people_shadow.append(gi.cast_shadow)
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	res["people_no_shadow"] = await fps(tree)
	var pl: Array = cats.get("people", [])
	for i in pl.size():
		pl[i].cast_shadow = people_shadow[i]
	res["trees_detail"] = await tree_profile(town, skip)
	return res


# ---------------------------------------------------------------- trees apart
static func _tree_mesh(n: Node) -> Mesh:
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = n.multimesh
		if mm == null and n.has_meta("whole"):
			mm = n.get_meta("whole")
		if mm == null:
			for c in n.get_children():
				if c is MultiMeshInstance3D and c.multimesh:
					mm = c.multimesh
					break
		return mm.mesh if mm else null
	for gi in _geo(n, []):
		if gi is MeshInstance3D and gi.mesh:
			return gi.mesh
	return null


static func tree_split(town: Node3D, skip: Array) -> Dictionary:
	## the top-level nodes of the group "tree": the trees proper (mesh taller than 3 m, the rule of opt3d's lodbias)
	## and the rest (grass, flowers, bushes, rocks: pueblo.gd puts its ground cover in the same group)
	var out := {"real": [], "cover": [], "other": []}
	for ch in town.get_children():
		if ch in skip or not (ch is Node3D):
			continue
		if ch.is_in_group("tree"):
			var m := _tree_mesh(ch)
			out["real" if m != null and m.get_aabb().size.y > 3.0 else "cover"].append(ch)
		else:
			out.other.append(ch)
	return out


static func _hide(list: Array) -> Array:
	var was := []
	for n: Node3D in list:
		was.append(n.visible)
		n.visible = false
	return was


static func _show(list: Array, was: Array) -> void:
	for i in list.size():
		if is_instance_valid(list[i]):
			list[i].visible = was[i]


static func _shadow_off(list: Array) -> Array:
	var was := []
	for n in list:
		for gi: GeometryInstance3D in _geo(n, []):
			was.append([gi, gi.cast_shadow])
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return was


static func _ms(tree: SceneTree, secs: float) -> float:
	for i in 4:
		await RenderingServer.frame_post_draw
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - t0) / 1000.0 / maxi(1, Engine.get_frames_drawn() - f0)


static func info2(vp: RID) -> Dictionary:
	## info() plus the triangles of the shadow passes
	var r := info(vp)
	r["shadow_tris_k"] = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000
	return r


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return (b[b.size() / 2] + b[(b.size() - 1) / 2]) / 2.0


static func _pair(tree: SceneTree, vp: RID, on: Callable, off: Callable, rounds: int, secs: float) -> Dictionary:
	## Frame time with a change (B: `on` applied) against without it (A), in `rounds` pairs measured one right after the
	## other and in alternating order: the machine drifts (heat, other processes) by more than what is being measured,
	## and a pair drifts together. diff = A - B (ms the change saves), median of the pairs, with its quartiles.
	var a_ms := []
	var b_ms := []
	var diffs := []
	var inf := {}
	for r in rounds:
		var a := 0.0
		var b := 0.0
		for step in 2:
			if (step == 0) == (r % 2 == 1):
				on.call()
				b = await _ms(tree, secs)
				if inf.is_empty():
					inf = info2(vp)
				off.call()
			else:
				a = await _ms(tree, secs)
		a_ms.append(a)
		b_ms.append(b)
		diffs.append(a - b)
	var d := diffs.duplicate()
	d.sort()
	return {"ms_a": snappedf(_median(a_ms), 0.01), "ms_b": snappedf(_median(b_ms), 0.01), "diff_ms": snappedf(_median(diffs), 0.01),
		"diff_q1": snappedf(d[d.size() / 4], 0.01), "diff_q3": snappedf(d[(d.size() * 3) / 4], 0.01),
		"fps_a": snappedf(1000.0 / _median(a_ms), 0.1), "fps_b": snappedf(1000.0 / _median(b_ms), 0.1),
		"dc_color": inf.color, "dc_shadow": inf.shadow, "tris_k": inf.tris_k, "shadow_tris_k": inf.shadow_tris_k}


static func tree_profile(town: Node3D, skip: Array, rounds := 8, secs := 0.7, mode := "") -> Dictionary:
	## What the trees proper cost in the view on screen, each thing against the whole scene in alternating pairs (_pair):
	##   no_trees          the trees hidden                      -> diff_ms = colour + shadow passes of the trees
	##   trees_no_shadow   the trees cast no shadow              -> diff_ms = their shadow passes
	##   no_trees_own / no_trees_q   only the kit/trees ones, only the Quaternius ones hidden
	##   no_cover          the grass, bushes and rocks of the group "tree" hidden
	##   treefar_off       (with opt3d's "treefar" active) the near meshes back: diff_ms < 0 is what treefar saves
	## and "meshes": per tree mesh, instances, draw calls and triangles (colour pass, shadow passes), which do not drift.
	## The trees alone on screen (everything else hidden) cannot be timed here: the frame hits a 120 fps cap (8.33 ms).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var tree := town.get_tree()
	var vp := town.get_viewport().get_viewport_rid()
	var split := tree_split(town, skip)
	var real: Array = split.real
	var own := []
	var quat := []
	for n: Node in real:
		(own if String(n.get_meta("tree_src", "")).contains("kit/trees") else quat).append(n)
	var res := {"n_real": real.size(), "n_cover": (split.cover as Array).size(), "rounds": rounds, "secs": secs}
	var base: Dictionary = await measure2(vp)
	res["all"] = base
	var meshes := {}
	for n: Node3D in real:
		var was := n.visible
		if not was:
			continue  # the twin that is not in use (near or far)
		n.visible = false
		var m: Dictionary = await measure2(vp)
		n.visible = was
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh if n is MultiMeshInstance3D else null
		if mm == null and n.has_meta("whole"):
			mm = n.get_meta("whole")
		meshes[String(n.name)] = {"src": String(n.get_meta("tree_src", "")).get_file(), "n": mm.instance_count if mm else 1,
			"color": base.color - m.color, "shadow": base.shadow - m.shadow, "tris_k": base.tris_k - m.tris_k,
			"shadow_tris_k": base.shadow_tris_k - m.shadow_tris_k}
	res["meshes"] = meshes
	var zoom: Node = town.get_node_or_null("Opt3DZoom")
	var has_far: bool = zoom != null and zoom.has_method("tree_far_force") and zoom.get("far_trees") is Array and not (zoom.far_trees as Array).is_empty()
	if has_far:
		zoom.tree_far_force(-1)
		var nbase: Dictionary = await measure2(vp)
		res["all_near"] = nbase
		var nmeshes := {}
		for n: Node3D in real:
			if n.has_meta("tree_far") or not n.visible:
				continue
			n.visible = false
			var m: Dictionary = await measure2(vp)
			n.visible = true
			var mm: MultiMesh = n.get_meta("whole") if n.has_meta("whole") else (n as MultiMeshInstance3D).multimesh
			nmeshes[String(n.name)] = {"src": String(n.get_meta("tree_src", "")).get_file(), "n": mm.instance_count if mm else 1,
				"color": nbase.color - m.color, "shadow": nbase.shadow - m.shadow, "tris_k": nbase.tris_k - m.tris_k,
				"shadow_tris_k": nbase.shadow_tris_k - m.shadow_tris_k}
		res["meshes_near"] = nmeshes
		zoom.tree_far_force(0)
	var state := {"was": [], "sh": []}
	var hide := func(list: Array) -> Callable:
		return func() -> void: state.was = _hide(list)
	var show := func(list: Array) -> Callable:
		return func() -> void: _show(list, state.was)
	var unshadow := func() -> void:
		for e in state.sh:
			if is_instance_valid(e[0]):
				e[0].cast_shadow = e[1]
	if has_far:
		res["treefar_off"] = await _pair(tree, vp, func() -> void: zoom.tree_far_force(-1), func() -> void: zoom.tree_far_force(0), rounds * 3, secs)
	if mode == "fast":
		return res
	if mode == "parts" and has_far:
		# where treefar saves: each pass of the far twins and of the trees themselves, hidden in turn
		var near := []
		var far_colour := []
		var far_shadow := []
		for n: Node in real:
			if not n.has_meta("tree_far"):
				near.append(n)
			elif (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				far_shadow.append(n)
			else:
				far_colour.append(n)
		res["far_no_colour"] = await _pair(tree, vp, hide.call(far_colour), show.call(far_colour), rounds * 2, secs)
		if not far_shadow.is_empty():
			res["far_no_shadow"] = await _pair(tree, vp, hide.call(far_shadow), show.call(far_shadow), rounds * 2, secs)
		elif String(zoom.get("tree_far_shadow")) == "near":
			var twinned := near.filter(func(n: Node) -> bool: return n.has_meta("far_twin"))  # shadow only while the far view is on
			res["far_no_shadow"] = await _pair(tree, vp, hide.call(twinned), show.call(twinned), rounds * 2, secs)
		else:
			res["far_no_shadow"] = await _pair(tree, vp, func() -> void: state.sh = _shadow_off(far_colour), unshadow, rounds * 2, secs)
		zoom.tree_far_force(-1)
		res["near_no_trees"] = await _pair(tree, vp, hide.call(near), show.call(near), rounds * 2, secs)
		res["near_no_shadow"] = await _pair(tree, vp, func() -> void: state.sh = _shadow_off(near), unshadow, rounds * 2, secs)
		zoom.tree_far_force(0)
		return res
	res["no_trees"] = await _pair(tree, vp, hide.call(real), show.call(real), rounds, secs)
	res["trees_no_shadow"] = await _pair(tree, vp, func() -> void: state.sh = _shadow_off(real), unshadow, rounds, secs)
	if not own.is_empty():
		res["no_trees_own"] = await _pair(tree, vp, hide.call(own), show.call(own), rounds, secs)
		res["own_no_shadow"] = await _pair(tree, vp, func() -> void: state.sh = _shadow_off(own), unshadow, rounds, secs)
	if not quat.is_empty():
		res["no_trees_q"] = await _pair(tree, vp, hide.call(quat), show.call(quat), rounds, secs)
		res["q_no_shadow"] = await _pair(tree, vp, func() -> void: state.sh = _shadow_off(quat), unshadow, rounds, secs)
	res["no_cover"] = await _pair(tree, vp, hide.call(split.cover), show.call(split.cover), rounds, secs)
	return res


static func measure2(vp: RID, frames := 6) -> Dictionary:
	for i in 3:
		await RenderingServer.frame_post_draw
	var acc := {"color": 0, "shadow": 0, "obj": 0, "tris_k": 0, "shadow_tris_k": 0}
	for i in frames:
		await RenderingServer.frame_post_draw
		var r := info2(vp)
		for k in acc:
			acc[k] += r[k]
	for k in acc:
		acc[k] = acc[k] / frames
	return acc
