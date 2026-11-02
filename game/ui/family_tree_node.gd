class_name FamilyTreeNode
extends PanelContainer
## One person of the family tree (GDD 4.10.7): portrait, name, age (or age at death) and class. Click: `picked(id)`.

signal picked(id: String)

var char_id: String = ""


func show_person(sim: Sim, chr: String, flags: Dictionary) -> void:
	char_id = chr
	name = chr
	var ch: Dictionary = sim.state.characters.get(chr, {})
	(%Frame as PortraitFrame).show_character(sim.state, chr, flags)
	(%NameLabel as Label).text = str(ch.get("name", chr))
	var age := Kin.age(sim, chr)
	(%AgeLabel as Label).text = (SimQuery.t_("ui.family.age_dead") if not bool(ch.get("alive", true)) \
		else SimQuery.t_("ui.family.age")) % age
	(%ClassLabel as Label).text = SimQuery.t_("class." + str(ch.get("class", "artisan")))
	modulate = Color(1, 1, 1, 0.6) if not bool(ch.get("alive", true)) else Color.WHITE
	var sel := bool(flags.get("selected", false))
	self_modulate = Color(1.35, 1.25, 1.0) if sel else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(char_id)
		accept_event()
