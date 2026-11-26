extends RefCounted
## Rendering optimisations for the 3D towns, applied after a town is built (villa, pueblo, main).
## Each one is measured with bench3d.gd (out/bench_*.json). All are on by default; switch them off
## from the command line for comparisons: `-- --opt=none` or `-- --opt=-chunk,-ssao`.
##   chunk    split big MultiMeshes (trees, grass) into CHUNK m cells so frustum culling works per cell
##            (one MultiMesh spanning the whole map is drawn entirely as soon as any corner is on screen)
##   lods     give the meshes merged at runtime (baked houses, lot props) automatic LODs; merging with
##            SurfaceTool drops the importer's LODs, so a whole house was always drawn at full detail
##   lodbias  trees (TREE_LOD_BIAS) and ground cover (LOD_BIAS) switch to their LODs sooner; they are
##            most of the triangles and a tuft or a leaf clump hides the simplification
##   treemm   loose tree scenes (group "tree", one node per tree as in pueblo.gd) become MultiMeshes
##   merge    loose props under a "Props"/"Quarter" node are merged into one mesh per material per CHUNK cell
##   covershadow  ground cover does not cast shadows (villa already did this; pueblo did not)
##   canon    materials that are the same in all but the instance (every kit .gltf brings its own MI_Plaster, MI_WoodTrim...)
##            become one instance, so the merges below join their surfaces (155 instances of 9 materials in town_e)
##   houses   (towns that set meta "opt_houses": pueblo) the baked houses are merged per CHUNK cell and material; the
##            window glass stays one mesh per house (night windows light per house); the pieces stay hidden for the
##            cutaway (set_cutaway -> house_sources)
##   far      past FAR_ZOOM (the whole-town view) the sun shadow drops to 2 splits, the mesh LOD threshold rises to
##            FAR_LOD_PX, the chunked MultiMeshes (trees, grass) are drawn whole again (every cell is on screen there:
##            one draw per mesh and surface instead of one per cell) and the town's on_far_zoom(true) runs (sim3d_chars:
##            people stop casting shadows); at game zoom (plaza, street) nothing changes
##   night    (towns with daylight(): the sim) the sun shadow also drops to 2 splits while it is dark: the moon is low,
##            its four splits reach a long way over the town and its shadows are faint
##   zoom     ground cover (grass, flowers, pebbles) is hidden when the camera zooms out past GRASS_ZOOM
##            (at that size a tuft is 1-2 px and only adds shimmer); a node watches the camera
##   treefar  past TREE_FAR_ZOOM the trees are drawn with their far meshes (scripts/tree_far.gd): one for the camera
##            (trunk and canopy shell simplified, one leaf card in four on the kit/trees ones, in a vertex buffer of
##            its own) and a coarser one that only casts the shadow; needs treemm. -- --treefar=<zoom> moves the
##            threshold, --treefar_shadow=same|off casts the shadow with the camera's mesh, or none

static var CHUNK := 32.0
const LOD_BIAS := 0.1
## 0.35 keeps the look at every zoom; 0.12 gives 60 fps at the maximum zoom-out (220) but the low LODs of the
## vertex-coloured trees (kit/trees) turn into dark blobs there. Override with -- --treebias=0.12
static var TREE_LOD_BIAS := 0.35
## SSAO in the far view: "off" (default: 3.6 ms at 1600x900, out/fpsprof_v2.json), "low" (very low quality, barely cheaper) or "keep" (-- --farssao=)
static var FAR_SSAO := "off"
const GRASS_ZOOM := 140.0
const FAR_ZOOM := 40.0
## past this zoom the trees switch to their far mesh ("treefar"); at 26 and closer nothing changes
static var TREE_FAR_ZOOM := 40.0
## what casts the shadow of a tree in the far view: "near" (the tree itself, shadow only: the shadow of always, and the
## cheapest: its LODs leave ~15 triangles per tree in the shadow passes), "proxy" (its shadow mesh), "same" (the far
## mesh the camera sees) or "off"
static var TREE_FAR_SHADOW := "near"
## "own" only the kit/trees ones (default: measured -2.5 ms in the far view, out/p3b_arb_treeprof_4own.json); "all"
## every tree; "q" only the Quaternius ones (they are cheap already: +0.9 ms with far meshes, out/p3b_arb_treeprof_4q.json)
static var TREE_FAR_ONLY := "own"
const TreeFar := preload("res://game/world3d/town/tree_far.gd")
static var FAR_LOD_PX := 4.0
const COVER := ["Grass", "Flower", "Clover", "Fern", "Pebble", "Mushroom", "Plant_1."]
const ALL := ["treemm", "canon", "houses", "merge", "covershadow", "chunk", "lods", "lodbias", "zoom", "far", "whole", "treefar"]

static var active := {}


static func apply(root: Node, args: PackedStringArray, cam_owner: Node = null) -> void:
	## cam_owner: the node with the `cam` property (default root; a twin town uses the first town's camera)
	if cam_owner == null:
		cam_owner = root
	if DisplayServer.get_name() == "headless":
		# nothing is drawn, and headless checks (sim3d --simcheck) read the loose tree and prop nodes
		if OS.is_debug_build():
			print("[Opt3D] headless: optimisations skipped")
		return
	root.set_meta("opt3d", true)
	active = {}
	for k in ALL:
		active[k] = true
	for a in args:
		if a.begins_with("--opt="):
			for k in a.trim_prefix("--opt=").split(","):
				if k == "none":
					for kk in ALL:
						active[kk] = false
				elif k.begins_with("-"):
					active[k.substr(1)] = false
				else:
					active[k] = true
		elif a.begins_with("--treebias="):
			TREE_LOD_BIAS = float(a.trim_prefix("--treebias="))
		elif a.begins_with("--farlod="):
			FAR_LOD_PX = float(a.trim_prefix("--farlod="))
		elif a.begins_with("--farssao="):
			FAR_SSAO = a.trim_prefix("--farssao=")
		elif a.begins_with("--chunk="):
			CHUNK = float(a.trim_prefix("--chunk="))
		elif a.begins_with("--treefar="):
			TREE_FAR_ZOOM = float(a.trim_prefix("--treefar="))
		elif a.begins_with("--treefar_shadow="):
			TREE_FAR_SHADOW = a.trim_prefix("--treefar_shadow=")
		elif a.begins_with("--treefar_only="):
			TREE_FAR_ONLY = a.trim_prefix("--treefar_only=")
		elif a.begins_with("--treefar_keep="):
			TreeFar.KEEP = maxi(1, int(a.trim_prefix("--treefar_keep=")))
		elif a.begins_with("--treefar_grow="):
			TreeFar.GROW = float(a.trim_prefix("--treefar_grow="))
		elif a.begins_with("--treefar_shell="):
			TreeFar.SHELL_TRIS = int(a.trim_prefix("--treefar_shell="))
		elif a.begins_with("--treefar_gain="):
			TreeFar.SHELL_GAIN = float(a.trim_prefix("--treefar_gain="))
	var t0 := Time.get_ticks_msec()
	if active.treemm:
		_tree_mm(root)
	if active.houses and root.has_meta("opt_houses"):
		_merge_houses(root)
	if active.merge:
		_merge_props(root)
	var mmis := _mmis(root, [])
	for mmi: MultiMeshInstance3D in mmis:
		if mmi.multimesh and mmi.multimesh.mesh:
			var path := mmi.multimesh.mesh.resource_path
			for c in COVER:
				if path.contains("/" + c):
					mmi.set_meta("cover", true)
	if active.covershadow:
		for mmi: MultiMeshInstance3D in mmis:
			if mmi.has_meta("cover"):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if active.lodbias:
		for mmi: MultiMeshInstance3D in mmis:
			var mesh: Mesh = mmi.multimesh.mesh if mmi.multimesh else null
			if mesh == null:
				continue
			mmi.lod_bias = LOD_BIAS if mesh.get_aabb().size.y <= 3.0 else TREE_LOD_BIAS
	if active.chunk:
		_chunk_all(root)
	if active.lods:
		_lods_all(root)
	if (active.zoom or active.far or active.treefar) and "cam" in cam_owner:
		var z := ZoomLod.new()
		z.name = "Opt3DZoom"
		z.town = cam_owner
		z.do_cover = active.zoom
		z.do_far = active.far
		z.far_ssao = FAR_SSAO
		z.far_lod = FAR_LOD_PX
		for ch in root.get_children():
			if ch is DirectionalLight3D and z.sun == null:
				z.sun = ch
			elif ch is WorldEnvironment and z.env == null:
				z.env = (ch as WorldEnvironment).environment
		for mmi: MultiMeshInstance3D in mmis:
			if mmi.has_meta("cover"):
				z.cover.append(mmi)
			if mmi.has_meta("whole") and active.whole:
				z.chunked.append(mmi)
			if mmi.has_meta("far_twin") and active.treefar:
				z.far_trees.append([mmi, mmi.get_meta("far_twin"), (mmi.get_meta("far_shadow_twin") if mmi.has_meta("far_shadow_twin") else null)])
		z.tree_far_zoom = TREE_FAR_ZOOM
		z.tree_far_shadow = TREE_FAR_SHADOW
		z.do_night = not ("--opt=-night" in args)
		root.add_child(z)
	if OS.is_debug_build():
		print("[Opt3D] applied %s in %d ms" % [active, Time.get_ticks_msec() - t0])


static func _mmis(n: Node, out: Array) -> Array:
	if n is MultiMeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_mmis(c, out)
	return out


# ---------------------------------------------------------------- chunk
static func _chunk_all(root: Node) -> void:
	var before := 0
	var after := 0
	for mmi: MultiMeshInstance3D in _mmis(root, []):
		var mm := mmi.multimesh
		if mm == null or mm.instance_count < 16 or mmi.has_meta("chunk") or mmi.has_meta("tree_far"):
			continue  # (a far-view twin is only drawn when every cell is on screen)
		before += 1
		after += _chunk(mmi)
	if OS.is_debug_build():
		print("[Opt3D] chunk: %d multimeshes -> %d cells of %.0f m" % [before, after, CHUNK])


static func _chunk(mmi: MultiMeshInstance3D) -> int:
	## the original node stays (other code keeps references to it and toggles its visibility) but
	## renders nothing; its children carry one MultiMesh per cell in the same local space
	var mm := mmi.multimesh
	var cells := {}
	for i in mm.instance_count:
		var xf := mm.get_instance_transform(i)
		var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	for key: Vector2i in cells:
		var idx: Array = cells[key]
		var cm := MultiMesh.new()
		cm.transform_format = mm.transform_format
		cm.use_colors = mm.use_colors
		cm.use_custom_data = mm.use_custom_data
		cm.mesh = mm.mesh
		cm.instance_count = idx.size()
		for j in idx.size():
			cm.set_instance_transform(j, mm.get_instance_transform(idx[j]))
			if mm.use_colors:
				cm.set_instance_color(j, mm.get_instance_color(idx[j]))
			if mm.use_custom_data:
				cm.set_instance_custom_data(j, mm.get_instance_custom_data(idx[j]))
		var c := MultiMeshInstance3D.new()
		c.name = "c%d_%d" % [key.x, key.y]
		c.multimesh = cm
		c.cast_shadow = mmi.cast_shadow
		c.material_override = mmi.material_override
		c.visibility_range_end = mmi.visibility_range_end
		c.lod_bias = mmi.lod_bias
		c.set_meta("chunk", true)
		mmi.add_child(c)
	mmi.set_meta("whole", mm)  # the far view draws it whole again (ZoomLod)
	mmi.multimesh = null
	return cells.size()


# ---------------------------------------------------------------- treemm
static func _meshes_under(n: Node, out: Array) -> Array:
	if n is MeshInstance3D and n.mesh and n.mesh.resource_path != "":
		out.append(n)
	for c in n.get_children():
		_meshes_under(c, out)
	return out


static func _tree_mm(root: Node3D) -> void:
	var inv := root.global_transform.affine_inverse()
	var groups := {}  # mesh+materials -> {mesh, xs, shadow, src, far}
	var trees := []
	var far_n := 0
	var far_trees := 0
	for t in root.get_children():
		if not (t is Node3D) or not t.is_in_group("tree") or t is MultiMeshInstance3D or t is MeshInstance3D:
			continue
		var mis := _meshes_under(t, [])
		if mis.is_empty():
			continue
		trees.append(t)
		for mi: MeshInstance3D in mis:
			var key := str(mi.mesh.get_rid().get_id())
			var mats := []
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				mats.append(m)
				key += "|%d" % (m.get_instance_id() if m else 0)
			if not groups.has(key):
				var mesh: Mesh = mi.mesh.duplicate()
				for i in mats.size():
					mesh.surface_set_material(i, mats[i])
				groups[key] = {mesh = mesh, xs = [], shadow = mi.cast_shadow, src = mi.mesh.resource_path.get_slice("::", 0), far = null, far_shadow = null}
				var own: bool = String(groups[key].src).contains("kit/trees")
				if active.get("treefar", false) and mi.mesh.get_aabb().size.y > 3.0 and (TREE_FAR_ONLY == "all" or (TREE_FAR_ONLY == "own") == own):
					var fms: Dictionary = TreeFar.far_meshes(mi.mesh)
					for fk in fms:
						var fm: ArrayMesh = (fms[fk] as ArrayMesh).duplicate()
						for i in mini(mats.size(), fm.get_surface_count()):
							fm.surface_set_material(i, mats[i])
						groups[key]["far" if fk == "colour" else "far_shadow"] = fm
			groups[key].xs.append(inv * mi.global_transform)
	for key in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g.mesh
		mm.instance_count = g.xs.size()
		for i in g.xs.size():
			mm.set_instance_transform(i, g.xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_mm%d" % root.get_child_count()
		mmi.multimesh = mm
		mmi.cast_shadow = g.shadow
		mmi.add_to_group("tree")
		mmi.set_meta("tree_src", g.src)
		root.add_child(mmi)
		if g.far != null:
			# the far-view twins: same trees with the far mesh and, casting the shadow, with the shadow mesh; hidden
			# until ZoomLod swaps them for the tree
			var casts: bool = g.shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and TREE_FAR_SHADOW != "off"
			var proxy: bool = casts and TREE_FAR_SHADOW == "proxy" and g.far_shadow != null
			var twins := [[g.far, "TreesFar_mm", "far_twin", g.shadow if (casts and not proxy) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]]
			if proxy:
				twins.append([g.far_shadow, "TreesFarShadow_mm", "far_shadow_twin", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY])
			for tw: Array in twins:
				var fmm := MultiMesh.new()
				fmm.transform_format = MultiMesh.TRANSFORM_3D
				fmm.mesh = tw[0]
				fmm.instance_count = g.xs.size()
				for i in g.xs.size():
					fmm.set_instance_transform(i, g.xs[i])
				var fmmi := MultiMeshInstance3D.new()
				fmmi.name = "%s%d" % [tw[1], root.get_child_count()]
				fmmi.multimesh = fmm
				fmmi.cast_shadow = tw[3]
				fmmi.visible = false
				fmmi.add_to_group("tree")
				fmmi.set_meta("tree_far", true)
				fmmi.set_meta("tree_src", g.src)
				root.add_child(fmmi)
				mmi.set_meta(tw[2], fmmi)
			far_n += 1
			far_trees += g.xs.size()
	for t in trees:
		t.free()
	if OS.is_debug_build():
		print("[Opt3D] treemm: %d tree nodes -> %d multimeshes (%d with a far mesh: %d trees)" % [trees.size(), groups.size(), far_n, far_trees])


# ---------------------------------------------------------------- merge
static func _has_light(n: Node) -> bool:
	if n is Light3D or n is GPUParticles3D or n is CPUParticles3D:
		return true
	for c in n.get_children():
		if _has_light(c):
			return true
	return false


static func _merge_props(root: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var merged := 0
	var cells_made := 0
	for holder_name in ["Props", "Quarter"]:
		var holder := root.get_node_or_null(holder_name) as Node3D
		if holder == null:
			continue
		var cells := {}
		for c in holder.get_children():
			if not (c is Node3D) or c.has_meta("merged") or _has_light(c) or _meshes_under(c, []).is_empty():
				continue
			var p: Vector3 = (c as Node3D).position
			var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(c)
		for key: Vector2i in cells:
			var mi := merge_canon(cells[key], holder, "props_%d_%d" % [key.x, key.y], root)
			if mi:
				mi.set_meta("merged", true)
				cells_made += 1
			for c in cells[key]:
				if "_orig" in root:
					for m in _meshes_any(c, []):
						root._orig.erase(m)  # set_style would touch freed nodes
				c.free()
				merged += 1
	if OS.is_debug_build() and merged > 0:
		print("[Opt3D] merge: %d loose props -> %d meshes in %d ms" % [merged, cells_made, Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- canon + houses
static var _canon := {}  # signature -> Material


static func _sig(m: Material) -> String:
	if m == null:
		return "null"
	var parts := [m.get_class()]
	for p in m.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE) or p.name in ["resource_name", "resource_local_to_scene", "resource_path", "script"]:
			continue
		var v = m.get(p.name)
		if v is Resource:
			v = (v as Resource).resource_path if (v as Resource).resource_path != "" else "#%d" % (v as Resource).get_instance_id()
		parts.append("%s=%s" % [p.name, v])
	return "|".join(parts)


static func canon(m: Material) -> Material:
	## one instance per distinct material (same class and stored properties, textures by path)
	if m == null or not active.get("canon", false):
		return m
	var k := _sig(m)
	if not _canon.has(k):
		_canon[k] = m
	return _canon[k]


static func _base_mat(root: Node, mi: MeshInstance3D, i: int) -> Material:
	## the material before the style variant (main.gd set_style), so set_style can re-skin the merged mesh
	if "_orig" in root and root._orig.has(mi):
		var mats: Array = root._orig[mi]
		if i < mats.size():
			return mats[i]
	return mi.get_active_material(i)


static func _commit(tools: Dictionary, mats: Dictionary, owner: Node3D, name: String, root: Node) -> MeshInstance3D:
	if tools.is_empty():
		return null
	var am := ArrayMesh.new()
	var bases := []
	for key in tools:
		am = (tools[key] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
		bases.append(mats[key])
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = am
	owner.add_child(mi)
	if "_orig" in root and root.has_method("_variant"):
		root._orig[mi] = bases
		for i in bases.size():
			mi.set_surface_override_material(i, root._variant(bases[i], root.style))
	return mi


static func _append(mi: MeshInstance3D, xf: Transform3D, root: Node, tools: Dictionary, mats: Dictionary, glass: Variant, gxf := Transform3D.IDENTITY) -> void:
	## glass: null -> every surface into tools; a Dictionary {tools, mats} -> the window glass goes there instead (at gxf)
	for i in mi.mesh.get_surface_count():
		var base := canon(_base_mat(root, mi, i))
		var t := tools
		var ms := mats
		var x := xf
		var src := mi.mesh.surface_get_material(i)
		if glass != null and src != null and src.resource_name.contains("Glass"):
			t = glass.tools
			ms = glass.mats
			x = gxf
		var key := base.get_instance_id() if base else 0
		if not t.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			t[key] = st
			ms[key] = base
		(t[key] as SurfaceTool).append_from(mi.mesh, i, x)


static func merge_canon(sources: Array, owner: Node3D, name: String, root: Node) -> MeshInstance3D:
	## HouseBuilder._merge_into with canonical materials (one surface per distinct material, not per instance)
	var tools := {}
	var mats := {}
	var inv := owner.global_transform.affine_inverse()
	for s in sources:
		for mi: MeshInstance3D in _meshes_any(s, []):
			_append(mi, inv * mi.global_transform, root, tools, mats, null)
	return _commit(tools, mats, owner, name, root)


static func _meshes_any(n: Node, out: Array) -> Array:
	if n is MeshInstance3D and n.mesh:
		out.append(n)
	for c in n.get_children():
		_meshes_any(c, out)
	return out


static func _merge_houses(root: Node3D) -> void:
	## one mesh per house (one surface per material) + its glass. Per house and not per cell: the automatic LODs
	## (lods) of a 32 m cell were so coarse in the shadow pass that the walls stopped casting shadows
	var t0 := Time.get_ticks_msec()
	var sources := []
	var merged := []
	var glass_mis := []
	var surf := 0
	for h: Node3D in root.houses:
		var tools := {}
		var mats := {}
		var g := {tools = {}, mats = {}}
		var hinv := h.global_transform.affine_inverse()
		var mine := []
		for mi: MeshInstance3D in _meshes_any(h, []):
			if not mi.is_visible_in_tree():
				continue
			_append(mi, hinv * mi.global_transform, root, tools, mats, g, hinv * mi.global_transform)
			mine.append(mi)
		var mm := _commit(tools, mats, h, "merged", root)
		if mm:
			mm.set_meta("opt_house", true)
			merged.append(mm)
			surf += mm.mesh.get_surface_count()
		# the glass of this house in its own mesh; glass surfaces keep the name sim3d looks for (resource_name)
		var gmi := _commit(g.tools, g.mats, h, "glass", root)
		if gmi:
			gmi.set_meta("opt_glass", true)
			glass_mis.append(gmi)
		for mi: MeshInstance3D in mine:
			mi.visible = false
		sources.append_array(mine)
	root.set_meta("opt_house_sources", sources)
	root.set_meta("opt_house_chunks", merged)
	root.set_meta("opt_house_glass", glass_mis)
	if OS.is_debug_build():
		print("[Opt3D] houses: %d meshes of %d houses -> %d merged (%d surfaces) + %d glass meshes in %d ms (%d canonical materials)" % [
			sources.size(), root.houses.size(), merged.size(), surf, glass_mis.size(), Time.get_ticks_msec() - t0, _canon.size()])


static func house_sources(root: Node, show: bool) -> void:
	## cutaway on: the house pieces (HouseBuilder.set_cutaway hides walls and roofs on them); off: the merged chunks
	if not root.has_meta("opt_house_sources"):
		return
	for mi: Node3D in root.get_meta("opt_house_sources"):
		if is_instance_valid(mi):
			mi.visible = show
	for mi: Node3D in root.get_meta("opt_house_chunks"):
		mi.visible = not show
	for mi: Node3D in root.get_meta("opt_house_glass"):
		mi.visible = not show


# ---------------------------------------------------------------- lods
static func _tri_count(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		t += m.surface_get_array_index_len(i) / 3 if m.surface_get_array_index_len(i) > 0 else m.surface_get_array_len(i) / 3
	return t


static func _lods_all(root: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var tris := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if node is MeshInstance3D and node.mesh is ArrayMesh and node.mesh.resource_path == "" and node.is_visible_in_tree():
			var t := _tri_count(node.mesh)
			if t < 1500:
				continue
			node.mesh = with_lods(node.mesh)
			n += 1
			tris += t
	if OS.is_debug_build():
		print("[Opt3D] lods: %d merged meshes (%d tris) got LODs in %d ms" % [n, tris, Time.get_ticks_msec() - t0])


static func with_lods(src: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for i in src.get_surface_count():
		im.add_surface(src.surface_get_primitive_type(i), src.surface_get_arrays(i), [], {}, src.surface_get_material(i), src.surface_get_name(i))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


# ---------------------------------------------------------------- zoom
class ZoomLod extends Node:
	var town: Node
	var cover: Array = []
	var chunked: Array = []  # MultiMeshInstance3D split in cells (meta "whole": the MultiMesh before the split)
	var far_trees: Array = []  # [the trees' MultiMeshInstance3D, its far-view twin, the twin that casts the shadow or null] ("treefar")
	var tree_far_zoom := 40.0
	var tree_far_shadow := "near"
	var _tfar := false
	var _tforce := 0
	var do_night := true
	var _two := false
	var sun: DirectionalLight3D
	var env: Environment
	var far_ssao := "off"
	var far_lod := 4.0
	var do_cover := true
	var do_far := true
	var _shown := true
	var _far := false
	var _near_mode := -1

	func _process(_dt: float) -> void:
		if not is_instance_valid(town) or not is_instance_valid(town.cam):
			return
		if not far_trees.is_empty():
			_tree_far_update()
		if do_far:
			_far_update()
		_splits()
		if not do_cover:
			return
		var show: bool = town.cam.size <= GRASS_ZOOM
		if show == _shown:
			return
		_shown = show
		for mmi: Node in cover:
			for c in mmi.get_children():
				c.visible = show and not (_far and mmi.has_meta("whole"))
			if mmi is MultiMeshInstance3D and mmi.multimesh != null:
				mmi.visible = show  # not chunked, or drawn whole in the far view
		if OS.is_debug_build():
			print("[Opt3D] zoom %.0f: ground cover %s" % [town.cam.size, "shown" if show else "hidden"])


	func tree_far_force(mode: int) -> void:
		## 0: by zoom; 1: always the far meshes; -1: never (dc_prof measures one against the other in the same view)
		_tforce = mode
		_tree_far_update()


	func _tree_far_update() -> void:
		var want: bool = _tforce > 0 or (_tforce == 0 and town.cam.size > tree_far_zoom)
		if want == _tfar:
			return
		_tfar = want
		for tw: Array in far_trees:
			for i in range(1, tw.size()):
				if is_instance_valid(tw[i]):
					tw[i].visible = want
			var near: MultiMeshInstance3D = tw[0]
			if not is_instance_valid(near):
				continue
			if tree_far_shadow != "near":
				near.visible = not want
				continue
			# the tree stays, casting its shadow only (its cells too: they draw when the far view is not on)
			if not near.has_meta("shadow0"):
				near.set_meta("shadow0", near.cast_shadow)
			var cast: int = near.get_meta("shadow0")
			if want and cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				cast = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			elif want:
				near.visible = false
			else:
				near.visible = true
			near.cast_shadow = cast
			for c in near.get_children():
				if c is GeometryInstance3D and c.has_meta("chunk"):
					c.cast_shadow = cast
		if OS.is_debug_build():
			print("[Opt3D] zoom %.0f: trees drawn with their %s meshes (%d kinds)" % [town.cam.size, "far" if want else "own", far_trees.size()])


	func _splits() -> void:
		## two shadow splits in the far view and, in the towns that tell the hour, while it is dark
		if not is_instance_valid(sun):
			return
		var night: bool = do_night and town.has_method("daylight") and "t_min" in town and town.daylight(town.t_min) < 0.3
		var two: bool = (do_far and _far) or night
		if _near_mode < 0:
			_near_mode = sun.directional_shadow_mode
		if two == _two:
			return
		_two = two
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if two else _near_mode


	func _far_update() -> void:
		var far: bool = town.cam.size > FAR_ZOOM
		if far == _far:
			return
		_far = far
		for mmi: MultiMeshInstance3D in chunked:
			if not is_instance_valid(mmi):
				continue
			mmi.multimesh = mmi.get_meta("whole") if far else null
			for c in mmi.get_children():
				if c.has_meta("chunk"):
					c.visible = (not far) and (_shown or not mmi.has_meta("cover"))
		get_viewport().mesh_lod_threshold = far_lod if far else 1.0
		if far_ssao == "low":
			# project defaults when near (rendering/environment/ssao/*): medium, half size, 0.5, 2 blur passes, fade 50..300
			if far:
				RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, true, 0.5, 1, 50.0, 300.0)
			else:
				RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		elif far_ssao == "off" and env:
			if far:
				set_meta("ssao", env.ssao_enabled)
				env.ssao_enabled = false
			elif has_meta("ssao"):
				env.ssao_enabled = get_meta("ssao")
		if town.has_method("on_far_zoom"):
			town.on_far_zoom(far)
		if OS.is_debug_build():
			print("[Opt3D] zoom %.0f: %s view (shadow splits %s, lod threshold %.0f px, ssao %s)" % [town.cam.size, "far" if far else "near",
				"2" if far else "own", far_lod if far else 1.0, far_ssao if far else "as set"])
