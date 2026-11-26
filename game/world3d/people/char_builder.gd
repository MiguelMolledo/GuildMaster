class_name CharBuilder
extends RefCounted
## Assembles a townsperson from data. Nothing in here knows about a particular pack: the parts, texture sets and
## colours live in data/chars/kit.json and data/chars/palettes.json (see docs/personajes.md), the meshes are baked
## to kit/chars/derived/<part id>.res by tools/make_char_meshes.gd. All parts share one 65-bone skeleton per sex
## and bind by bone name, so a part from another pack (or made by us) on the same skeleton is just more data.
##
## build(def) -> Node3D: Armature/Skeleton3D with one MeshInstance3D per part, and an AnimationPlayer with the
## animation library. A def (a Dictionary, e.g. one entry of data/chars/villagers.json):
##   sex     "m" | "f"
##   parts   {slot: part id | outfit name | "" (none)}; slot "acc" takes a list. Missing slots use kit.defaults.
##           A name that is not a part id picks the part of that slot whose "outfit" or "kind" is that name and
##           whose sex is the def's (or "*"): torso "peasant" -> torso_peasant_f for a woman, acc "hood" -> hood_ranger_m.
##   paint   {"skin": tone, "hair": colour, "*": cloth paint for every slot, <slot or part id>: cloth paint}
##           cloth paint = "dye" (band a) | ["dye a", "dye b"] | {"tex": texture set, "a": dye, "b": dye}
##           ("tex" only applies to parts whose texture set lists it in "variants": same UV layout)
##   height  uniform scale; anim, seed (start offset); outline (bool); lod_bias; props [kit.props names]
##   anim    a UAL animation ("Walk") or one of ours (data/chars/anims.json, "hammer"); ours bring their items (hammer,
##           tongs, broom...) on a BoneAttachment3D unless items = false
##   carry   an upper-body layer over anim: "box" plays anims.json "carry_box" on the arms (AnimationTree, bone
##           filter) while anim (Walk / Idle) drives the rest. Change both later with CharBuilder.play(node, anim, carry).
##   age     years (default: none = adult as modelled). Picks an interpolated profile from kit.ages: body proportions
##           and posture (CharAge modifier), stature, animation speed, grey hair, faded skin, and the stage's part /
##           texture variants ("<id>_<variant>" when it exists: head_m -> head_m_child, skin_head_m -> skin_head_m_old)
## Rules carried by the parts: "attach" (parts that always come along: eyes with a head, belts with a torso),
## "head" (a torso that needs another head cut, e.g. a V neck), "hides_tags" (a hood drops parts tagged long_hair),
## "paint_from" (an accessory painted like another slot), "skirt" (a long skirt with skirt bones: CharSkirt moves them).

const KIT := "res://game/world3d/kit_data/chars/kit.json"
const PAL := "res://data/view3d/chars/palettes.json"
const D := "res://kit/chars/derived/"
const Age := preload("res://game/world3d/people/char_age.gd")
const Skirt := preload("res://game/world3d/people/char_skirt.gd")
const ANIMS := "res://game/world3d/kit_data/chars/anims.json"
const OWN := "own"  # library of our animations (tools/make_anims.gd -> kit/chars/derived/anims_<sex>.res)

static var kit: Dictionary
static var pal: Dictionary
static var anims: Dictionary
static var _cache := {}
static var _outline: StandardMaterial3D


static func load_data(force := false) -> void:
	if kit.is_empty() or force:
		kit = JSON.parse_string(FileAccess.get_file_as_string(KIT))
		pal = JSON.parse_string(FileAccess.get_file_as_string(PAL))
		anims = JSON.parse_string(FileAccess.get_file_as_string(ANIMS)) if FileAccess.file_exists(ANIMS) else {}
		# derived parts (age variants baked by tools/make_age_parts.gd) inherit what they do not set from their source
		for id in kit.parts:
			var p: Dictionary = kit.parts[id]
			if p.has("derive"):
				p.merge(kit.parts[p.derive.from], false)


static func path(p: String) -> String:
	for k in kit.dirs:
		if p.begins_with(k):
			return String(kit.dirs[k]) + p.trim_prefix(k)
	return p


static func _res(p: String) -> Resource:
	if not _cache.has(p):
		_cache[p] = load(p)
	return _cache[p]


## The part ids of a def, in order, after defaults, outfits, attachments and hiding rules.
static func resolve(def: Dictionary) -> Array:
	load_data()
	var sex: String = def.get("sex", "m")
	var want: Dictionary = (kit.defaults[sex] as Dictionary).duplicate()
	want.merge(def.get("parts", {}), true)
	var stage := age_stage(def)
	want.merge(stage.get("parts", {}), true)
	var ids := []
	for slot in kit.slots:
		var v = want.get(slot, "")
		for name in (v if v is Array else [v]):
			var id := _find(slot, String(name), sex)
			if id != "":
				ids.append(id)
	# a torso may need another head (V neck); attachments come along
	for id in ids.duplicate():
		var p: Dictionary = kit.parts[id]
		if p.has("head"):
			for j in ids.size():
				if kit.parts[ids[j]].slot == "head":
					ids[j] = p.head
	var i := 0
	while i < ids.size():
		for a in kit.parts[ids[i]].get("attach", []):
			if not ids.has(a):
				ids.append(a)
		i += 1
	var variant := String(stage.get("variant", ""))
	if variant != "":
		for j in ids.size():
			var alt: String = ids[j] + "_" + variant
			if kit.parts.has(alt) and kit.parts[alt].sex in [sex, "*"]:
				ids[j] = alt
	var hidden := []
	for id in ids:
		hidden.append_array(kit.parts[id].get("hides_tags", []))
	return ids.filter(func(id):
		for t in kit.parts[id].get("tags", []):
			if hidden.has(t):
				return false
		return true)


static func _find(slot: String, name: String, sex: String) -> String:
	if name == "":
		return ""
	if kit.parts.has(name):
		return name
	for id in kit.parts:
		var p: Dictionary = kit.parts[id]
		if not p.has("derive") and p.slot == slot and (p.get("outfit", "") == name or p.get("kind", "") == name) and p.sex in [sex, "*"]:
			return id
	push_warning("[CharBuilder] no part for slot %s = %s (%s)" % [slot, name, sex])
	return ""


## Cloth paint of a part: {tex, a, b} merged from "*", its slot (or paint_from) and its own id.
static func _paint_for(id: String, def: Dictionary) -> Dictionary:
	var p: Dictionary = kit.parts[id]
	var paint: Dictionary = def.get("paint", {})
	var out := {}
	for key in ["*", p.get("paint_from", p.slot), id]:
		var v = paint.get(key, null)
		if v is String:
			out.a = v
		elif v is Array:
			out.a = v[0]
			if v.size() > 1:
				out.b = v[1]
		elif v is Dictionary:
			out.merge(v, true)
	return out


static func _tint(table: String, name, fallback: String) -> Array:
	var c: Array = pal[table].get(String(name), pal[table][fallback])
	return [Color(c[0], c[1], c[2]), float(c[3])]


static func material(channel: String, tex_id: String, def: Dictionary, paint: Dictionary) -> ShaderMaterial:
	## channel: skin (skin tone), hair (hair colour), cloth (dyes), fixed (as painted)
	var outline: bool = def.get("outline", false)
	var key := "%s|%s|%s|%s" % [channel, tex_id, outline, ""]
	var tint := [Color.WHITE, 1.0]
	var variant := String(def.get("_variant", ""))
	if variant != "" and kit.textures.has(tex_id + "_" + variant):
		tex_id = tex_id + "_" + variant
	if channel == "skin":
		tint = _tint("skin", def.get("paint", {}).get("skin", "fair"), "fair")
		var fade := float(def.get("_skin_fade", 0.0))
		if fade > 0.0:
			# older skin: less saturated, a little darker
			var c: Color = tint[0]
			var g := c.get_luminance()
			tint[0] = c.lerp(Color(g, g, g), 0.45 * fade) * (1.0 - 0.08 * fade)
	elif channel == "hair":
		tint = _tint("hair", def.get("paint", {}).get("hair", "brown"), "brown")
		var grey := float(def.get("_grey", 0.0))
		if grey > 0.0:
			var w := _tint("hair", "white", "white")
			tint = [(tint[0] as Color).lerp(w[0], grey), lerpf(tint[1], w[1], grey)]
	elif channel == "cloth":
		# another texture set only if it shares the UV layout (listed in the part's set "variants")
		var alt := String(paint.get("tex", ""))
		if alt != "" and (kit.textures[tex_id].get("variants", []) as Array).has(alt):
			tex_id = alt
	key = "%s|%s|%s|%s|%s|%s" % [channel, tex_id, outline, tint[0].to_html(), tint[1], JSON.stringify([paint.get("a", ""), paint.get("b", "")])]
	if _cache.has(key):
		return _cache[key]
	var t: Dictionary = kit.textures[tex_id]
	var m := ShaderMaterial.new()
	m.shader = _res("res://game/world3d/shaders/char.gdshader")
	m.set_shader_parameter("albedo_tex", _res(path(t.albedo)))
	m.set_shader_parameter("use_normal", t.has("normal"))
	if t.has("normal"):
		m.set_shader_parameter("normal_tex", _res(path(t.normal)))
	m.set_shader_parameter("use_orm", t.has("orm"))
	if t.has("orm"):
		m.set_shader_parameter("orm_tex", _res(path(t.orm)))
	m.set_shader_parameter("roughness", float(t.get("roughness", 1.0)))
	m.set_shader_parameter("tint", tint[0])
	m.set_shader_parameter("tint_gain", tint[1])
	if channel == "cloth":
		for band in ["a", "b"]:
			var dn := String(paint.get(band, ""))
			if dn != "" and pal.dyes.has(dn) and t.get("bands", {}).has(band):
				_set_band(m, band, t.bands[band], pal.dyes[dn])
	if outline and channel != "fixed":
		if _outline == null:
			_outline = StandardMaterial3D.new()
			_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_outline.albedo_color = Color(0.16, 0.1, 0.07)
			_outline.cull_mode = BaseMaterial3D.CULL_FRONT
			_outline.grow = true
			_outline.grow_amount = 0.03
		m.next_pass = _outline
	_cache[key] = m
	return m


static func _set_band(m: ShaderMaterial, p: String, b: Array, dy: Array) -> void:
	## band [hue centre deg, hue half width deg (180 = any), sat min, sat max, val min, val max, mean value]
	## dye [target hue deg (-1 keeps), target saturation, target value]: saturation pulled most of the way to the
	## target, the band's mean value lands on the target value (the shader compresses the rest around it)
	m.set_shader_parameter(p + "_hue", Vector2(b[0] / 360.0, b[1] / 360.0 if b[1] < 180 else 1.0))
	m.set_shader_parameter(p + "_sv", Vector4(b[2], b[3], b[4], b[5]))
	m.set_shader_parameter(p + "_dye", Vector4(dy[0] / 360.0 if dy[0] >= 0 else -1.0, 0.35, 0.65 * dy[1], dy[2]))
	m.set_shader_parameter(p + "_ref", b[6])
	m.set_shader_parameter(p + "_on", 1.0)


## Age profile for def.age: the numeric fields of kit.ages.keys interpolated between the two keys around the age
## (height, anim_speed, grey, skin_fade, bones {bone: effective scale}, bend {bone: degrees}). {} without age.
static func age_profile(def: Dictionary) -> Dictionary:
	load_data()
	if not def.has("age") or not kit.has("ages"):
		return {}
	var age := float(def.age)
	var keys: Array = kit.ages.keys
	var i := 0
	while i < keys.size() - 1 and float(keys[i + 1].at) <= age:
		i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var t := 0.0
	if k1 != k0 and float(k1.at) > float(k0.at):
		t = clampf((age - float(k0.at)) / (float(k1.at) - float(k0.at)), 0.0, 1.0)
	var out := {}
	for f in ["height", "anim_speed"]:
		out[f] = lerpf(float(k0.get(f, 1.0)), float(k1.get(f, 1.0)), t)
	for f in ["grey", "skin_fade"]:
		out[f] = lerpf(float(k0.get(f, 0.0)), float(k1.get(f, 0.0)), t)
	for f in [["bones", 1.0], ["bend", 0.0]]:
		var a: Dictionary = k0.get(f[0], {})
		var b: Dictionary = k1.get(f[0], {})
		var m := {}
		for bone in a.keys() + b.keys():
			m[bone] = lerpf(float(a.get(bone, f[1])), float(b.get(bone, f[1])), t)
		out[f[0]] = m
	return out


## The life stage of def.age (kit.ages.stages: the first whose "until" >= age): variant suffix, forced parts.
static func age_stage(def: Dictionary) -> Dictionary:
	if not def.has("age") or not kit.has("ages"):
		return {}
	for st in kit.ages.stages:
		if float(def.age) <= float(st.until):
			return st
	return {}


## Standing height (m) of the skeleton with the age scales: top of the head mesh over the floor, rest pose.
static func stature(sk: Skeleton3D, sex: String, eff: PackedFloat32Array) -> float:
	var head := sk.find_bone("Head")
	var top_key := "head_top_" + sex
	if not _cache.has(top_key):
		var m: Mesh = _res(D + String(kit.defaults[sex].head) + ".res")
		var ab := m.get_aabb()
		_cache[top_key] = ab.position.y + ab.size.y - sk.get_bone_global_rest(head).origin.y
	var g := []
	g.resize(sk.get_bone_count())
	var hip_k := eff[sk.find_bone("thigh_l")] if eff.size() > 0 else 1.0
	for b in sk.get_bone_count():
		var r := sk.get_bone_rest(b)
		var s := eff[b] / (eff[sk.get_bone_parent(b)] if sk.get_bone_parent(b) >= 0 else 1.0) if eff.size() > 0 else 1.0
		var l := Transform3D(r.basis * Basis.from_scale(Vector3.ONE * s), r.origin * (hip_k if sk.get_bone_name(b) == "pelvis" else 1.0))
		g[b] = (g[sk.get_bone_parent(b)] as Transform3D) * l if sk.get_bone_parent(b) >= 0 else l
		if b == head:
			break
	return ((g[head] as Transform3D) * Vector3(0, float(_cache[top_key]), 0)).y + float(kit.skeletons[sex].get("y_offset", 0.0))


## A kit.props object on its bone (cane in the hand, baby in a sling): primitive shapes, toon material.
static func _add_prop(sk: Skeleton3D, prop: String) -> void:
	if not kit.get("props", {}).has(prop):
		push_warning("[CharBuilder] no prop " + prop)
		return
	var pd: Dictionary = kit.props[prop]
	var ba := BoneAttachment3D.new()
	ba.name = "prop_" + prop
	ba.bone_name = pd.bone
	sk.add_child(ba)
	for sh in pd.shapes:
		var mi := MeshInstance3D.new()
		var sz: Array = sh[1]
		match String(sh[0]):
			"cylinder":
				var m := CylinderMesh.new()
				m.top_radius = sz[0]
				m.bottom_radius = sz[0]
				m.height = sz[1]
				m.radial_segments = 8
				mi.mesh = m
			"capsule":
				var m := CapsuleMesh.new()
				m.radius = sz[0]
				m.height = sz[1]
				m.radial_segments = 10
				m.rings = 4
				mi.mesh = m
			"sphere":
				var m := SphereMesh.new()
				m.radius = sz[0]
				m.height = sz[0] * 2.0
				m.radial_segments = 10
				m.rings = 6
				mi.mesh = m
			_:
				var m := BoxMesh.new()
				m.size = Vector3(sz[0], sz[1], sz[2])
				mi.mesh = m
		mi.position = Vector3(sh[2][0], sh[2][1], sh[2][2])
		mi.rotation_degrees = Vector3(sh[3][0], sh[3][1], sh[3][2])
		var key := "prop|" + str(sh[4])
		if not _cache.has(key):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(sh[4][0], sh[4][1], sh[4][2])
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			mat.roughness = 1.0
			_cache[key] = mat
		mi.material_override = _cache[key]
		ba.add_child(mi)


static func build(def: Dictionary) -> Node3D:
	load_data()
	var sex: String = def.get("sex", "m")
	var prof := age_profile(def)
	if not prof.is_empty():
		def = def.duplicate()
		def._variant = age_stage(def).get("variant", "")
		def._grey = prof.grey
		def._skin_fade = prof.skin_fade
	var root := Node3D.new()
	root.name = String(def.get("name", "Char"))
	var arm := Node3D.new()
	arm.name = "Armature"
	root.add_child(arm)
	var sk: Skeleton3D = (_res(D + "skeleton_%s.scn" % sex) as PackedScene).instantiate()
	arm.add_child(sk)
	# the animations carry the male hip height; other skeletons are moved so their feet touch the ground
	arm.position.y = float(kit.skeletons[sex].get("y_offset", 0.0))
	var ids := resolve(def)
	var tris := 0
	# long skirts: the skirt bones their skins bind come onto this skeleton before any part is bound
	var skirt := {}
	var skirt_id := ""
	for id in ids:
		if kit.parts[id].has("skirt") and Skirt.add_bones(sk, _res(D + id + ".skin.res")) > 0:
			skirt = kit.parts[id].skirt
			skirt_id = id
	for id in ids:
		var p: Dictionary = kit.parts[id]
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = _res(D + id + ".res")
		mi.skin = _res(D + id + ".skin.res")
		var paint := _paint_for(id, def)
		var surfs: Array = p.surfaces
		for i in mi.mesh.get_surface_count():
			var s := String(surfs[mini(i, surfs.size() - 1)])
			mi.set_surface_override_material(i, material(s.get_slice(":", 0), s.get_slice(":", 1), def, paint))
			tris += mi.mesh.surface_get_array_index_len(i) / 3
		mi.lod_bias = float(def.get("lod_bias", 1.0))
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
	for prop in def.get("props", []):
		_add_prop(sk, String(prop))
	var scale := float(def.get("height", 1.0))
	var speed := 1.0
	if not prof.is_empty():
		# proportions + posture after the animation; the body is scaled so the standing height is
		# profile.height x the adult height of that sex (the head scale alone would make it taller)
		var mod := Age.new()
		sk.add_child(mod)
		mod.setup(sk, prof)
		if mod.scales.is_empty() and mod.bends.is_empty():
			mod.free()  # adult proportions: nothing to do every frame
			mod = null
		var eff := Age.effective(sk, prof.bones)
		var adult := stature(sk, sex, PackedFloat32Array())
		var aged := stature(sk, sex, eff)
		scale *= float(prof.height) * adult / aged
		speed = float(prof.anim_speed)
		root.set_meta("stature", aged * scale)
		var hip_k: float = mod.hip_k if mod else 1.0
		root.set_meta("stride", hip_k * scale)
		if OS.is_debug_build():
			print("[CharBuilder] %s age %s (%s): stature %.3f m (adult %.3f), root scale %.3f, hip_k %.3f, anim speed %.2f, parts %s" % [root.name, def.age,
				def._variant, aged * scale, adult, scale, hip_k, speed, ids])
	if not skirt.is_empty():
		# after the animation and CharAge: the columns open out of the legs (see scripts/char_skirt.gd)
		var sm := Skirt.new()
		sk.add_child(sm)
		sm.setup(sk, skirt, sk.get_node(skirt_id))
	root.scale = Vector3.ONE * scale
	# speed of the walk cycle relative to an adult: move the node this much slower to keep the feet planted
	root.set_meta("move_speed", speed * float(root.get_meta("stride", scale)))
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.speed_scale = speed
	ap.add_animation_library("", _res(D + "animations.res"))
	if ResourceLoader.exists(D + "anims_%s.res" % sex):
		ap.add_animation_library(OWN, _res(D + "anims_%s.res" % sex))
	root.set_meta("base_speed", speed)
	root.set_meta("base_move_speed", root.get_meta("move_speed"))
	root.set_meta("with_items", def.get("items", true))
	var anim: String = def.get("anim", "Idle")
	if anim_name(ap, anim) != "":
		var r := RandomNumberGenerator.new()
		r.seed = int(def.get("seed", 0))
		play(root, anim, String(def.get("carry", "")), 0.0, r.randf())
	root.set_meta("tris", tris)
	root.set_meta("pieces", ids.size())
	root.set_meta("parts", ids)
	return root


# ---------------------------------------------------------------- animations: ours, layers and held items

## The playable name of an animation: a UAL one as is, one of ours as "own/<name>". "" if there is none.
static func anim_name(ap: AnimationPlayer, anim: String) -> String:
	if anim == "":
		return ""
	if ap.has_animation(anim):
		return anim
	if ap.has_animation(OWN + "/" + anim):
		return OWN + "/" + anim
	return ""


## Plays `anim` on a built character; with `carry`, anims.json "carry_<carry>" drives the bones of its mask (arms,
## one arm, upper body) on top of anim (AnimationTree: Blend2 with a bone filter, then a TimeScale). The items of
## the animations (hammer, broom, crate...) are attached and the old ones removed. `start` = fraction of the cycle.
static func play(c: Node3D, anim: String, carry := "", fade := 0.25, start := -1.0) -> void:
	load_data()
	var ap: AnimationPlayer = c.get_node("AnimationPlayer")
	var lower := anim_name(ap, anim)
	if lower == "":
		push_warning("[CharBuilder] no animation " + anim)
		return
	var upper := ""
	var cdef: Dictionary = {}
	if carry != "":
		var cname := "carry_" + carry
		cdef = anims.get("anims", {}).get(cname, {})
		# a carry may have its own variant per lower animation (the cane planted when standing still)
		var vname := String(cdef.get("variants", {}).get(anim, cname))
		upper = anim_name(ap, vname)
		if upper == "":
			push_warning("[CharBuilder] no carry animation " + vname)
		cdef = anims.get("anims", {}).get(vname, cdef)
	var speed := float(c.get_meta("base_speed", 1.0))
	var cspeed := float(cdef.get("speed", 1.0)) if upper != "" else 1.0
	var tree: AnimationTree = c.get_node_or_null("AnimationTree")
	if upper == "":
		if tree:
			tree.active = false
			ap.active = true
		ap.speed_scale = speed
		ap.play(lower, fade)
		if start >= 0.0:
			ap.seek(start * ap.get_animation(lower).length, true)
	else:
		if tree == null:
			tree = _make_tree(c, ap)
		var bt := tree.tree_root as AnimationNodeBlendTree
		(bt.get_node("lower") as AnimationNodeAnimation).animation = lower
		(bt.get_node("upper") as AnimationNodeAnimation).animation = upper
		var mix := bt.get_node("mix") as AnimationNodeBlend2
		var mask: Array = anims.get("masks", {}).get(String(cdef.get("mask", "arms")), [])
		var sk: Skeleton3D = c.get_node("Armature").get_child(0)
		for b in sk.get_bone_count():
			var bn := sk.get_bone_name(b)
			var on := false
			for pat in mask:
				if bn.match(String(pat)):
					on = true
					break
			mix.set_filter_path(NodePath("Armature/Skeleton3D:" + bn), on)
		ap.stop()
		ap.active = false
		tree.active = true
		tree.set("parameters/mix/blend_amount", 1.0)
		tree.set("parameters/speed/scale", speed * cspeed)
		if start >= 0.0:
			# both layers at the same phase (a cane cycle is as long as the walk it goes with)
			seek(c, start * ap.get_animation(lower).length)
	c.set_meta("move_speed", float(c.get_meta("base_move_speed", 1.0)) * cspeed)
	c.set_meta("anim", anim)
	c.set_meta("carry", carry)
	_sync_items(c, ap, [lower, upper] if upper != "" else [lower])
	if OS.is_debug_build() and (lower.begins_with(OWN) or upper != ""):
		print("[CharBuilder] %s plays %s%s (speed %.2f)" % [c.name, lower, " + " + upper if upper != "" else "", speed * cspeed])


static func _make_tree(c: Node3D, ap: AnimationPlayer) -> AnimationTree:
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	c.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("lower", AnimationNodeAnimation.new(), Vector2(0, 0))
	bt.add_node("upper", AnimationNodeAnimation.new(), Vector2(0, 200))
	var mix := AnimationNodeBlend2.new()
	mix.filter_enabled = true
	bt.add_node("mix", mix, Vector2(250, 100))
	bt.add_node("speed", AnimationNodeTimeScale.new(), Vector2(450, 100))
	bt.add_node("seek", AnimationNodeTimeSeek.new(), Vector2(650, 100))
	bt.connect_node("mix", 0, "lower")
	bt.connect_node("mix", 1, "upper")
	bt.connect_node("speed", 0, "mix")
	bt.connect_node("seek", 0, "speed")
	bt.connect_node("output", 0, "seek")
	tree.tree_root = bt
	return tree


## Items of the playing animations (meta "items" written by tools/make_anims.gd: item, bone, xform in bone space).
static func _sync_items(c: Node3D, ap: AnimationPlayer, names: Array) -> void:
	var sk: Skeleton3D = c.get_node("Armature").get_child(0)
	var want := {}
	if c.get_meta("with_items", true):
		for n in names:
			var a := ap.get_animation(n)
			for it in a.get_meta("items", []):
				want["item_" + String(it.item)] = it
	for ch in sk.get_children():
		if ch is BoneAttachment3D and String(ch.name).begins_with("item_") and not want.has(String(ch.name)):
			sk.remove_child(ch)
			ch.queue_free()
	for key in want:
		if sk.has_node(NodePath(key)):
			continue
		var it: Dictionary = want[key]
		var node := make_item(String(it.item))
		if node == null:
			continue
		var ba := BoneAttachment3D.new()
		ba.name = key
		ba.bone_name = it.bone
		sk.add_child(ba)
		node.transform = it.xform * node.transform
		ba.add_child(node)


## An item of anims.json: a glTF scene (scale, pos, rot) or primitive shapes ([type, size, pos, rot deg, colour,
## emission]), in its own frame (the fist's grip frame for hand-held tools).
static func make_item(name: String) -> Node3D:
	load_data()
	var d: Dictionary = anims.get("items", {}).get(name, {})
	if d.is_empty():
		push_warning("[CharBuilder] no item " + name)
		return null
	var root := Node3D.new()
	root.name = name
	if d.has("scene"):
		var n: Node3D = (_res(String(d.scene)) as PackedScene).instantiate()
		LandmarkBuilder._vertex_colors(n)   # tinted surfaces (kit/utiles) read their vertex colours, white ones keep the kit material
		var sc = d.get("scale", 1.0)
		n.scale = Vector3(sc[0], sc[1], sc[2]) if sc is Array else Vector3.ONE * float(sc)
		var p: Array = d.get("pos", [0, 0, 0])
		n.position = Vector3(p[0], p[1], p[2])
		var r: Array = d.get("rot", [0, 0, 0])
		n.rotation_degrees = Vector3(r[0], r[1], r[2])
		root.add_child(n)
	for sh in d.get("shapes", []):
		root.add_child(_shape(sh))
	return root


static func _shape(sh: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sz: Array = sh[1]
	match String(sh[0]):
		"cylinder", "cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0 if sh[0] == "cone" else sz[0]
			m.bottom_radius = sz[0]
			m.height = sz[1]
			m.radial_segments = 10
			m.rings = 1
			mi.mesh = m
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = sz[0]
			m.height = sz[1]
			m.radial_segments = 10
			m.rings = 4
			mi.mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = sz[0]
			m.height = sz[0] * 2.0 * (float(sz[1]) if sz.size() > 1 else 1.0)
			m.radial_segments = 12
			m.rings = 6
			mi.mesh = m
		_:
			var m := BoxMesh.new()
			m.size = Vector3(sz[0], sz[1], sz[2])
			mi.mesh = m
	mi.position = Vector3(sh[2][0], sh[2][1], sh[2][2])
	mi.rotation_degrees = Vector3(sh[3][0], sh[3][1], sh[3][2])
	var emit := float(sh[5]) if sh.size() > 5 else 0.0
	var key := "item|%s|%s" % [str(sh[4]), emit]
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(sh[4][0], sh[4][1], sh[4][2])
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.roughness = 1.0
		if emit > 0.0:
			mat.emission_enabled = true
			mat.emission = Color(sh[4][0], sh[4][1], sh[4][2])
			mat.emission_energy_multiplier = emit
		_cache[key] = mat
	mi.material_override = _cache[key]
	return mi


## Jumps a built character's animation (both layers when it carries something) to `t` seconds.
static func seek(c: Node3D, t: float) -> void:
	var tree: AnimationTree = c.get_node_or_null("AnimationTree")
	if tree and tree.active:
		tree.set("parameters/seek/seek_request", t)
		if tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			tree.advance(0.0)
	else:
		(c.get_node("AnimationPlayer") as AnimationPlayer).seek(t, true)
