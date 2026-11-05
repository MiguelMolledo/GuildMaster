class_name FamilyTreeNode
extends PanelContainer
## One person of the family tree (GDD 4.10.7; docs/ui/mecanicas/familia.md §3): portrait, name, age (or † age) and a
## row of badges: the key 1-2-3 of the group, the office it holds (H10), «!» while its school choice waits, «R» for
## the regent, banished (H11). Its tooltip says the role and the death risk this year as a band. Dead: faded.
## Click: `picked(id)`.

signal picked(id: String)

var char_id: String = ""


func show_person(sim: Sim, chr: String, flags: Dictionary) -> void:
	char_id = chr
	name = chr
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	var fam := str(ch.get("family", ""))
	var alive := bool(ch.get("alive", true))
	var g := Kin.group(st, fam)
	var key := g.find(chr) if alive else -1
	var f := flags.duplicate()
	if key >= 0:
		f["key"] = str(key + 1)
	(%Frame as PortraitFrame).show_character(st, chr, f)
	(%NameLabel as Label).text = str(ch.get("name", chr))
	var age := Kin.age(sim, chr)
	(%AgeLabel as Label).text = (SimQuery.t_("ui.family.age_dead") if not alive else SimQuery.t_("ui.family.age")) % age
	var badges := %Badges as HBoxContainer
	SocialKit.clear(badges)
	var office := Offices.of_character(st, chr)  # H10: the office it holds
	if office != "" and alive:
		var t := TextureRect.new()
		t.name = "Office"
		t.texture = UiIcons.mark("badge_office_" + office)
		t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		t.tooltip_text = SimQuery.office_name(office)
		badges.add_child(t)
	if alive and ch.get("life") is Dictionary and str(ch["life"].get("school", "")) == "pending":
		badges.add_child(SocialKit.label("!", &"WarningLabel", "School"))
	if chr == str(st.families.get(fam, {}).get("regent", "")):
		badges.add_child(SocialKit.label(SimQuery.t_("ui.family.regent_badge"), &"CaptionLabel", "Regent"))
	if Tribunal.is_banished(st, chr):  # H11: banished
		badges.add_child(SocialKit.label(SimQuery.t_("ui.trial.banished_short"), &"ReasonLabel", "Banished"))
	var roles: PackedStringArray = [str(ch.get("name", chr)), (%AgeLabel as Label).text]
	if chr == str(st.families.get(fam, {}).get("head", "")):
		roles.append(SimQuery.t_("ui.family.head").to_lower())
	if bool(flags.get("heir", false)):
		roles.append(SimQuery.t_("ui.family.heir").to_lower())
	if office != "" and alive:
		roles.append(SimQuery.office_name(office))
	var tip := " · ".join(roles)
	if alive:
		tip += "\n" + SimQuery.t_("ui.family.risk") % SimQuery.t_("risk." + FamilyTreePanel.risk_band(Lifecycle.death_chance(sim, chr)))
	tooltip_text = tip
	modulate = Color(1, 1, 1, 0.6) if not alive else Color.WHITE
	theme_type_variation = &"SelectedRow" if bool(flags.get("selected", false)) else &"RowPanel"


func _enter_tree() -> void:
	focus_mode = Control.FOCUS_ALL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(char_id)
		accept_event()
	elif event.is_action_pressed("ui_accept"):   # the keyboard: Enter / Space on the focused person (verificación C13)
		picked.emit(char_id)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1), Color("#f2d880"), false, 1.0)
