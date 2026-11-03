class_name ManageSlot
extends RefCounted
## One management panel at a time (docs/ui/01_hud.md §4.2): every panel of zone 5 (and the wide and big ones) joins
## the group "manage_panel"; when one becomes visible the others close (with their own close(), so their buttons and
## sounds follow). The HUD's panels and the interior's join the same group, so a book opened inside a building closes
## its production panel and the other way round.

const GROUP: StringName = &"manage_panel"


## `panel` takes part (it must have close()). Once per node.
static func join(panel: Control) -> void:
	if panel.is_in_group(GROUP):
		return
	panel.add_to_group(GROUP)
	panel.visibility_changed.connect(_on_visibility.bind(panel))


static func _on_visibility(panel: Control) -> void:
	if panel.visible and panel.is_inside_tree():
		close_others(panel, panel.get_tree().get_nodes_in_group(GROUP))


## `panel` was opened: every other visible panel of `members` closes (its own close()). The closed ones are returned.
static func close_others(panel: Control, members: Array) -> Array:
	var closed: Array = []
	for n: Node in members:
		if n != panel and (n as Control).visible and n.has_method("close"):
			if OS.is_debug_build():
				print("[ManageSlot] %s opens: %s closes" % [panel.name, n.name])
			n.call("close")
			closed.append(n)
	return closed


## The panel of the group open now (null if none).
static func open_panel(tree: SceneTree) -> Control:
	for n: Node in tree.get_nodes_in_group(GROUP):
		if (n as Control).visible:
			return n as Control
	return null
