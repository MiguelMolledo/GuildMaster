class_name KinAiPanel
extends PanelContainer
## The AI of a family member (GDD 4.10.6, 4.2.6, H14): pick an adult of the family; what it is doing now and why
## (a directive, a need, its routine); its directives in order of priority (on / off, ▲ ▼; the ones of later milestones
## greyed with their milestone), sent as one set_directives; its needs (hunger, rest, social, fun) and its morale with
## the work rate it gives. Opens from the person's sheet («AI») or the family tree; closes with ESC or X. Reads the state
## and gives orders (order_sink).

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # who gives the order (the selected person or the head)
var target: String = ""  # whose AI is shown
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	var ob := %MemberOption as OptionButton
	ob.item_selected.connect(func(i: int) -> void:
		target = str(ob.get_item_metadata(i))
		_sig = "")


func open_for(s: Sim, who: String, whose: String) -> void:
	_bind()
	sim = s
	actor = who
	target = whose
	(%Title as Label).text = SimQuery.t_("ui.kin_ai.title")
	(%DirectivesTitle as Label).text = SimQuery.t_("ui.kin_ai.directives")
	(%NeedsTitle as Label).text = SimQuery.t_("ui.kin_ai.needs")
	visible = true
	refresh(true)
	ViewConfig.info("KinAiPanel", "open (actor=%s, target=%s)" % [who, whose])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


## The adults of the family of `actor` (the member picker).
func _members() -> Array:
	var st := sim.state
	var fam := str(st.characters.get(actor, {}).get("family", ""))
	var out: Array = []
	for m: Variant in st.families.get(fam, {}).get("members", []):
		if Kin.alive(st, str(m)) and Kin.is_adult(sim, str(m)):
			out.append(str(m))
	return out


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var members := _members()
	if not target in members and not members.is_empty():
		target = str(members[0])
	var dv := Directives.view(sim, target)
	var nv := Needs.view(sim, target)
	var sig := "%s|%s|%s|%s|%s" % [actor, target, members, dv, nv]
	if sig == _sig and not force:
		return
	_sig = sig
	var st := sim.state
	var ob := %MemberOption as OptionButton
	ob.clear()
	for i: int in members.size():
		var c := str(members[i])
		ob.add_item(str(st.characters[c].get("name", c)))
		ob.set_item_metadata(i, c)
		if c == target:
			ob.select(i)
	if dv.is_empty():
		return
	var controlled := str(st.characters[target].get("controlled_by", "")) == "human"
	(%WhenLabel as Label).text = SimQuery.t_("ui.kin_ai.when_controlled" if controlled else "ui.kin_ai.when_ai")
	(%NowLabel as Label).text = now_text(dv)
	_fill_directives(dv)
	_fill_needs(nv)
	reset_size()


## «Now: trading (directive)» / «Now: home (hunger)» / «Now: working (routine)».
static func now_text(dv: Dictionary) -> String:
	var doing := str(dv.get("doing", ""))
	if doing == "":
		return SimQuery.t_("ui.kin_ai.now_unknown")
	var why := str(dv.get("why", ""))
	var reason := SimQuery.t_("ui.kin_ai.why_" + why)  # why_need_hunger…: «tiene hambre», «está cansado»
	return SimQuery.t_("ui.kin_ai.now") % [SimQuery.t_("ui.kin_ai.doing_" + doing), reason]


func _fill_directives(dv: Dictionary) -> void:
	var box := %Directives as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var list: Array = dv["directives"]
	var rows: Array = list.duplicate()  # the ones on, in their order, then the rest
	for k: Dictionary in dv["known"]:
		if not str(k["id"]) in rows:
			rows.append(str(k["id"]))
	for id: Variant in rows:
		var d := str(id)
		var ready: Variant = null
		for k: Dictionary in dv["known"]:
			if str(k["id"]) == d:
				ready = k["ready"]
		var on := d in list
		var row := HBoxContainer.new()
		row.name = "D_" + d
		var cb := CheckBox.new()
		cb.name = "On"
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = on
		cb.text = ("%d. " % (list.find(d) + 1) if on else "") + SimQuery.t_("directive." + d)
		cb.custom_minimum_size = Vector2(150, 0)
		cb.add_theme_font_size_override("font_size", 10)
		var is_ready: bool = ready is bool and bool(ready)
		cb.disabled = not is_ready
		if not is_ready:
			cb.text += " " + SimQuery.t_("ui.kin_ai.later") % str(ready)
		cb.tooltip_text = SimQuery.t_("ui.kin_ai.tip_" + d)
		cb.toggled.connect(func(p: bool) -> void: _toggle(d, p))
		row.add_child(cb)
		for dir: int in [-1, 1]:
			var b := Button.new()
			b.name = "Up" if dir < 0 else "Down"
			b.text = "▲" if dir < 0 else "▼"
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 10)
			var i := list.find(d)
			b.disabled = not on or (dir < 0 and i == 0) or (dir > 0 and i == list.size() - 1)
			b.pressed.connect(func() -> void: _move(d, dir))
			row.add_child(b)
		box.add_child(row)


func _fill_needs(nv: Dictionary) -> void:
	var box := %Needs as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var needs: Dictionary = nv.get("needs", {})
	for k: Variant in sim.catalog.family.get("needs", {}).get("ids", []):
		box.add_child(_bar("N_" + str(k), SimQuery.t_("need." + str(k)), int(needs.get(str(k), 0))))
	var m := int(nv.get("morale", 0))
	box.add_child(_bar("Morale", SimQuery.t_("ui.kin_ai.morale"), m))
	var rate := Label.new()
	rate.name = "Rate"
	rate.add_theme_font_size_override("font_size", 10)
	var p := float(nv.get("productivity", 1.0))
	rate.text = SimQuery.t_("ui.kin_ai.rate_full") if p >= 1.0 else SimQuery.t_("ui.kin_ai.rate_slow") % roundi(p * 100.0)
	rate.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7) if p >= 1.0 else Color(1, 0.55, 0.45))
	box.add_child(rate)


func _bar(node_name: String, text: String, v: int) -> Control:
	var row := HBoxContainer.new()
	row.name = node_name
	var l := Label.new()
	l.text = "%s %d" % [text, v]
	l.custom_minimum_size = Vector2(100, 0)
	l.add_theme_font_size_override("font_size", 10)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.max_value = 100
	bar.value = v
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var low := int(sim.catalog.family.get("needs", {}).get("low", 30))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.35, 0.3) if v < low else (Color(0.85, 0.7, 0.4) if v < 60 else Color(0.45, 0.78, 0.45))
	bar.add_theme_stylebox_override("fill", sb)
	row.add_child(bar)
	return row


func _toggle(d: String, on: bool) -> void:
	var list: Array = (Directives.view(sim, target)["directives"] as Array).duplicate()
	if on and not d in list:
		list.append(d)
	elif not on:
		list.erase(d)
	_send(list)


func _move(d: String, dir: int) -> void:
	var list: Array = (Directives.view(sim, target)["directives"] as Array).duplicate()
	var i := list.find(d)
	var j := i + dir
	if i < 0 or j < 0 or j >= list.size():
		return
	list[i] = list[j]
	list[j] = d
	_send(list)


func _send(list: Array) -> void:
	var o := {"type": "set_directives", "actor": actor, "character": target, "directives": list}
	ViewConfig.info("KinAiPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
