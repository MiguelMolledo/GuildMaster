class_name WeddingCard
extends PanelContainer
## The wedding card (docs/ui/mecanicas/cortejo_y_boda.md §3, §6; the same base as the title card): when someone of the
## player's family marries (event wedding), a letter in the middle with the two families' colours as two half ribbons,
## the two portraits with a ring between them, «¡Hugo y Agnès se casan!» and what it means: the spouse lives in the
## family's home now, the job it leaves (employee_left married of the same step, or its trade), when the first child
## may come (the wife's wedding day + data/family.json children.first_child_days). A click or the button closes it;
## also by itself after view.json title_card_seconds. Listens to Events itself; reads only, gives no orders.

var data: Dictionary = {}   # what the card says (tests)
var _left: float = 0.0


func _ready() -> void:
	(%OkButton as Button).pressed.connect(close)
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			var sim: Sim = g.get("sim")
			for e: Dictionary in events:
				if str(e.get("type", "")) == "wedding" and str(e.get("family", "")) == SimQuery.player_family(sim.state):
					show_for(sim, e, events))


## Shows the card for wedding event `e` (and the events of its step: the job left).
func show_for(sim: Sim, e: Dictionary, events: Array = []) -> void:
	var st := sim.state
	var a := str(e.get("character", ""))
	var b := str(e.get("spouse", ""))
	var fam := str(e.get("family", ""))
	var old := str(e.get("from_family", ""))
	var ac: Dictionary = st.characters.get(a, {})
	var bc: Dictionary = st.characters.get(b, {})
	for pair: Array in [[%RibbonLeft, fam], [%RibbonRight, old if st.families.has(old) else fam]]:
		var slot := pair[0] as Control
		SocialKit.clear(slot)
		slot.add_child(SocialKit.ribbon(st, str(pair[1]), Vector2(90, 6)))
	for pair: Array in [[%LeftSlot, a], [%RightSlot, b]]:
		var slot := pair[0] as Control
		SocialKit.clear(slot)
		if st.characters.has(str(pair[1])):
			var p := SocialKit.portrait(st, str(pair[1]))
			p.scale = Vector2(2, 2)
			slot.add_child(p)
	(%LeftName as Label).text = str(ac.get("name", a))
	(%RightName as Label).text = str(bc.get("name", b))
	(%Text as Label).text = SimQuery.t_("ui.wedding.text") % [str(ac.get("name", a)), str(bc.get("name", b))]
	var lines: PackedStringArray = [SimQuery.t_("ui.wedding.home") % str(bc.get("name", b))]
	for x: Dictionary in events:
		if str(x.get("type", "")) == "employee_left" and str(x.get("employee", "")) == b and str(x.get("reason", "")) == "married":
			lines.append(SimQuery.t_("ui.wedding.job") % SimQuery.building_label(st, sim.catalog, str(x.get("building", ""))))
	if lines.size() == 1 and str(bc.get("occupation", "")) != "" and not TownLife.is_household(st, fam):
		lines.append(SimQuery.t_("ui.wedding.job") % SimQuery.occupation_name(str(bc["occupation"])))  # no longer a townsperson
	var wife: Dictionary = bc if bool(bc.get("female", false)) else ac
	var wd := int(wife.get("life", {}).get("wedding_day", -1)) if wife.get("life") is Dictionary else -1
	if wd >= 0:
		var first := wd + int(sim.catalog.family.get("children", {}).get("first_child_days", 0))
		lines.append(SimQuery.t_("ui.wedding.child") % (first + 1))
	(%Lines as Label).text = "· " + "\n· ".join(lines)
	(%OkButton as Button).text = SimQuery.t_("ui.wedding.ok")
	data = {"a": a, "b": b, "lines": lines}
	visible = true
	_left = float(ViewConfig.value("title_card_seconds", 8.0))
	reset_size()
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) / 2.0).round()
	ViewConfig.info("WeddingCard", "wedding: %s + %s (%s)" % [a, b, lines])


func close() -> void:
	visible = false
	_left = 0.0


func _process(delta: float) -> void:
	if visible and _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()
