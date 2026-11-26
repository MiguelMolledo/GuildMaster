class_name CharAge
extends SkeletonModifier3D
## Age proportions and posture on top of the shared animations (see docs/personajes.md, "Edades").
## Runs after the AnimationPlayer every frame; Skeleton3D restores the animated pose after skinning, so nothing
## accumulates (also with a paused animation).
##   - per-bone uniform scale: the profile gives an *effective* scale per bone relative to the body (Head 1.22 =
##     the head is 22 % bigger than the body scale); bones not listed inherit their parent's. Uniform scales
##     commute with rotations, so no shear whatever the animation does.
##   - the pelvis position track carries the adult hip height: it is multiplied by the leg scale (feet on the floor).
##   - bend: degrees about each bone's local X added to the animated rotation (forward stoop, head raised back).
## The UAL animations only carry rotations (and the pelvis position), so the scales are never overwritten.

var scales := {}  # bone index -> local scale (only bones != 1)
var bends := {}  # bone index -> Quaternion added after the animation
var pelvis := -1
var hip_k := 1.0


## profile: the interpolated age profile (CharBuilder.age_profile). Call after adding to the skeleton.
func setup(sk: Skeleton3D, profile: Dictionary) -> void:
	name = "CharAge"
	var eff := effective(sk, profile.get("bones", {}))
	scales.clear()
	for b in sk.get_bone_count():
		var p := sk.get_bone_parent(b)
		var local: float = eff[b] / (eff[p] if p >= 0 else 1.0)
		if absf(local - 1.0) > 0.0005:
			scales[b] = local
	bends.clear()
	var bend: Dictionary = profile.get("bend", {})
	for b in sk.get_bone_count():
		var deg := float(bend.get(_key(sk.get_bone_name(b), bend), 0.0))
		if absf(deg) > 0.01:
			bends[b] = Quaternion(Vector3.RIGHT, deg_to_rad(deg))
	pelvis = sk.find_bone("pelvis")
	hip_k = eff[sk.find_bone("thigh_l")]
	if OS.is_debug_build():
		var named := {}
		for b in scales:
			named[sk.get_bone_name(b)] = snappedf(scales[b], 0.001)
		print("[CharAge] setup: %d scaled bones %s, %d bends, hip_k=%.3f" % [scales.size(), named, bends.size(), hip_k])


## Effective scale of every bone: the listed value, or its parent's. Keys may omit the _l/_r side ("thigh").
static func effective(sk: Skeleton3D, bones: Dictionary) -> PackedFloat32Array:
	var eff := PackedFloat32Array()
	eff.resize(sk.get_bone_count())
	for b in sk.get_bone_count():  # parents come before children in this skeleton
		var p := sk.get_bone_parent(b)
		var k := _key(sk.get_bone_name(b), bones)
		eff[b] = float(bones[k]) if k != "" else (eff[p] if p >= 0 else 1.0)
	return eff


static func _key(bone: String, table: Dictionary) -> String:
	if table.has(bone):
		return bone
	for side in ["_l", "_r"]:
		if bone.ends_with(side) and table.has(bone.trim_suffix(side)):
			return bone.trim_suffix(side)
	return ""


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in scales:
		sk.set_bone_pose_scale(b, Vector3.ONE * scales[b])
	if hip_k != 1.0 and pelvis >= 0:
		sk.set_bone_pose_position(pelvis, sk.get_bone_pose_position(pelvis) * hip_k)
	for b in bends:
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * bends[b])
