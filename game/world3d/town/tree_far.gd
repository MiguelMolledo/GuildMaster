extends RefCounted
## Far-view meshes of the trees (opt3d "treefar"): what a tree is drawn with past TREE_FAR_ZOOM, where it is 60-150 px
## tall. Two per tree, built from its own mesh surface by surface, so the materials (foliage shader: seasons, wind;
## bark) and the vertex colours are the same and nothing else has to know:
##   colour  what the camera sees
##   shadow  what casts the shadow (coarser: a shadow at that size is a soft blob)
##
## Why: the automatic LODs only swap the index buffer. A tree of kit/trees keeps its 20-30 000 vertices whatever the
## LOD (and its LODs have nothing between ~8 000 triangles and a dark blob of ~100: the leaf cards do not collapse),
## and on this GPU what the trees cost in the far view follows the size of the vertex buffer, not the triangles drawn:
## the far meshes draw MORE triangles than the LODs did and the frame is shorter (out/p3b_arb_*.json). So the far
## meshes are new, compact vertex buffers:
##   - big connected parts (trunk, canopy shell) are simplified with the importer's LOD generator and only the
##     vertices that are left are kept (same positions, colours and normals);
##   - loose leaf cards (parts of a few triangles) OVER A SHELL (kit/trees) are thinned to one in KEEP and the ones
##     left grow by GROW about their centre: the canopy keeps its ragged outline and its mottling. The shell is
##     painted dark in the kit (depth between the leaves); with fewer cards more of it shows, so it is lifted by
##     SHELL_GAIN. In the shadow mesh the shell alone, pushed out SHADOW_PUFF m, stands for the canopy;
##   - loose cards with nothing under them (the Quaternius trees: textured cards) are all kept in the colour mesh:
##     thinned they turn darker and coarser (tried, it shows). Only their shadow mesh thins them.
## Cached in kit/trees/far/<name>.res and <name>_shadow.res (kit/ is not in git), rebuilt when the tree's file or the
## parameters change:  godot --headless --path . -s tools/trees_far.gd  builds them all and prints the table.

const DIR := "res://kit/trees/far/"
const VERSION := 3
## colour mesh: one leaf card in KEEP stays, GROW times bigger
static var KEEP := 4
static var GROW := 1.6
static var SHELL_TRIS := 700
static var SOLID_TRIS := 400  # trunk and branches
static var SHELL_GAIN := 1.35
## shadow mesh
static var SHADOW_SHELL_TRIS := 300
static var SHADOW_SOLID_TRIS := 100
static var SHADOW_PUFF := 0.22
static var SHADOW_KEEP := 4  # loose cards with no shell under them
static var SHADOW_GROW := 2.0
## a tree is worth far meshes from this many vertices
const MIN_VERTS := 3000
## a connected part with this many triangles or fewer is a leaf card
const CARD_TRIS := 8
## the solid part of a foliage surface is a shell under the cards from this many triangles
const SHELL_MIN := 500


static func params() -> String:
	return "v%d keep=%d grow=%.2f shell=%d solid=%d gain=%.2f / shadow shell=%d solid=%d puff=%.2f keep=%d grow=%.2f" % [VERSION, KEEP, GROW,
		SHELL_TRIS, SOLID_TRIS, SHELL_GAIN, SHADOW_SHELL_TRIS, SHADOW_SOLID_TRIS, SHADOW_PUFF, SHADOW_KEEP, SHADOW_GROW]


static func key_of(mesh: Mesh) -> String:
	## "res://kit/trees/roble_0.glb::ArrayMesh_x" -> "roble_0"
	var p := mesh.resource_path.get_slice("::", 0)
	return p.get_file().get_basename() if p != "" else ""


static func tris_of(mesh: Mesh) -> int:
	var t := 0
	for i in mesh.get_surface_count():
		var n: int = mesh.surface_get_array_index_len(i)
		t += (n if n > 0 else int(mesh.surface_get_array_len(i))) / 3
	return t


static func verts_of(mesh: Mesh) -> int:
	var t := 0
	for i in mesh.get_surface_count():
		t += int(mesh.surface_get_array_len(i))
	return t


static func far_meshes(mesh: Mesh, use_cache := true) -> Dictionary:
	## {colour: ArrayMesh, shadow: ArrayMesh} of a tree mesh, or {} if it is not worth it. Same surfaces in the same
	## order as the tree's.
	var key := key_of(mesh)
	if key == "" or verts_of(mesh) < MIN_VERTS:
		return {}
	var paths := {"colour": DIR + key + ".res", "shadow": DIR + key + "_shadow.res"}
	var stamp := "%s src=%d" % [params(), FileAccess.get_modified_time(mesh.resource_path.get_slice("::", 0))]
	if use_cache and ResourceLoader.exists(paths.colour) and ResourceLoader.exists(paths.shadow):
		var c := ResourceLoader.load(paths.colour) as ArrayMesh
		var s := ResourceLoader.load(paths.shadow) as ArrayMesh
		if c and s and String(c.get_meta("tree_far", "")) == stamp and String(s.get_meta("tree_far", "")) == stamp:
			return {"colour": c, "shadow": s}
	var t0 := Time.get_ticks_msec()
	var out := {"colour": build(mesh, false), "shadow": build(mesh, true)}
	for k in out:
		var m: ArrayMesh = out[k]
		m.set_meta("tree_far", stamp)
		if use_cache:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
			var err := ResourceSaver.save(m, paths[k], ResourceSaver.FLAG_COMPRESS)
			if err != OK and OS.is_debug_build():
				print("[TreeFar] could not save %s (error %d): built again next time" % [paths[k], err])
	if OS.is_debug_build():
		print("[TreeFar] %s: %d tris, %d verts -> colour %d tris, %d verts; shadow %d tris, %d verts (%d ms)" % [key, tris_of(mesh), verts_of(mesh),
			tris_of(out.colour), verts_of(out.colour), tris_of(out.shadow), verts_of(out.shadow), Time.get_ticks_msec() - t0])
	return out


static func build(mesh: Mesh, shadow: bool) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var foliage: bool = mat == null or not String(mat.resource_name).to_lower().contains("bark")
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface(mesh.surface_get_arrays(s), foliage, shadow))
		out.surface_set_name(out.get_surface_count() - 1, mesh.surface_get_name(s) if mesh is ArrayMesh else "")
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	while parent[i] != r:
		var n := parent[i]
		parent[i] = r
		i = n
	return r


static func _surface(arrays: Array, foliage: bool, shadow: bool) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var nt := idx.size() / 3
	# connected parts (by shared vertex)
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	for t in nt:
		var a := _find(parent, idx[t * 3])
		var b := _find(parent, idx[t * 3 + 1])
		var c := _find(parent, idx[t * 3 + 2])
		if b != a:
			parent[b] = a
		if c != a:
			parent[c] = a
	var part_tris := {}  # root -> triangle count
	var tri_root := PackedInt32Array()
	tri_root.resize(nt)
	for t in nt:
		var r := _find(parent, idx[t * 3])
		tri_root[t] = r
		part_tris[r] = int(part_tris.get(r, 0)) + 1
	# solid parts -> simplified; cards -> thinned (or all kept)
	var solid := PackedInt32Array()
	var n_cards := 0
	for t in nt:
		if int(part_tris[tri_root[t]]) > CARD_TRIS:
			solid.append(idx[t * 3])
			solid.append(idx[t * 3 + 1])
			solid.append(idx[t * 3 + 2])
	for r in part_tris:
		if int(part_tris[r]) <= CARD_TRIS:
			n_cards += 1
	# a shell under the cards: the cards can go (one in KEEP stays; none in the shadow mesh)
	var shell: bool = foliage and n_cards > 0 and solid.size() / 3 >= SHELL_MIN
	var every := 1
	var grow := 1.0
	if shell:
		every = 0 if shadow else KEEP
		grow = GROW
	elif shadow and foliage:
		every = SHADOW_KEEP
		grow = SHADOW_GROW
	var card_idx := PackedInt32Array()
	if n_cards > 0 and every > 0:
		var keep := {}
		var k := 0
		var roots := part_tris.keys()
		roots.sort()
		for r in roots:
			if int(part_tris[r]) > CARD_TRIS:
				continue
			# evenly over the canopy: the cards come in the order they were scattered (at random over its surface)
			if k % every == 0:
				keep[r] = true
			k += 1
		for t in nt:
			if keep.has(tri_root[t]):
				card_idx.append(idx[t * 3])
				card_idx.append(idx[t * 3 + 1])
				card_idx.append(idx[t * 3 + 2])
	var target := SOLID_TRIS
	if shadow:
		target = SHADOW_SHELL_TRIS if shell else SHADOW_SOLID_TRIS
	elif shell:
		target = SHELL_TRIS
	var solid_far := _simplify(arrays, solid, target)
	# compact vertex arrays: solid first, then the cards that stay
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	for i in solid_far:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		new_idx.append(remap[i])
	var n_solid := order.size()
	for i in card_idx:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		new_idx.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX or a == Mesh.ARRAY_BONES or a == Mesh.ARRAY_WEIGHTS:
			continue
		var per: int = 4 if a == Mesh.ARRAY_TANGENT else 1
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for j in order.size():
			for q in per:
				dst[j * per + q] = src[order[j] * per + q]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	var ov: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	# the cards that stay grow about their centre
	if not card_idx.is_empty() and grow != 1.0:
		var sum := {}
		var cnt := {}
		for j in range(n_solid, order.size()):
			var r := _find(parent, order[j])
			sum[r] = (sum.get(r, Vector3.ZERO) as Vector3) + verts[order[j]]
			cnt[r] = int(cnt.get(r, 0)) + 1
		for j in range(n_solid, order.size()):
			var r := _find(parent, order[j])
			var c: Vector3 = (sum[r] as Vector3) / float(cnt[r])
			ov[j] = c + (ov[j] - c) * grow
	if shell and shadow and SHADOW_PUFF != 0.0 and out[Mesh.ARRAY_NORMAL] != null:
		# the shell alone casts the shadow of the canopy: out to where the leaf tips were
		var on: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
		for j in n_solid:
			ov[j] += on[j] * SHADOW_PUFF
	out[Mesh.ARRAY_VERTEX] = ov
	# the shell under the cards, lifted
	if shell and not shadow and SHELL_GAIN != 1.0 and out[Mesh.ARRAY_COLOR] != null:
		var oc: PackedColorArray = out[Mesh.ARRAY_COLOR]
		for j in n_solid:
			var c := oc[j]
			oc[j] = Color(minf(c.r * SHELL_GAIN, 1.0), minf(c.g * SHELL_GAIN, 1.0), minf(c.b * SHELL_GAIN, 1.0), c.a)
		out[Mesh.ARRAY_COLOR] = oc
	return out


static func _simplify(arrays: Array, solid: PackedInt32Array, target: int) -> PackedInt32Array:
	## the LOD of the solid part closest to `target` triangles from below (indices into the same vertex arrays)
	if solid.size() / 3 <= target:
		return solid
	var a := arrays.duplicate()
	a[Mesh.ARRAY_INDEX] = solid
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a)
	im.generate_lods(25.0, 60.0, [])
	var best := solid
	var best_n := solid.size() / 3
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		var n := li.size() / 3
		# the biggest that fits the target; if none fits, the smallest there is
		if (n <= target and (best_n > target or n > best_n)) or (best_n > target and n < best_n):
			best = li
			best_n = n
	return best
