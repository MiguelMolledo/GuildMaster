class_name OfficeCard
extends PanelContainer
## The result of a vote (GDD 4.12.4, H10): when an election closes with a candidate of the player's family
## (election_held), a card in the middle of the screen with the office, a bar per candidate with its votes (its family
## colour), the share of the votes by family, the winner with the seal and how many voted; «Elegido sin votación»
## when nobody stood against (cargos_y_elecciones.md §3). A click (or the button) closes it;
## it also closes by itself after `office_card_seconds` real seconds (data/view.json). Reads only; gives no orders.

var _left: float = 0.0


func _ready() -> void:
	(%OkButton as Button).pressed.connect(close)
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())


## Whether election_held `e` concerns the human family (one of its members stood).
static func concerns_human(sim: Sim, e: Dictionary) -> bool:
	var el := Elections.last_result(sim.state, str(e.get("office", "")))
	for c: Dictionary in el.get("candidates", []):
		var fam := str(sim.state.characters.get(str(c["character"]), {}).get("family", ""))
		if str(sim.state.families.get(fam, {}).get("controlled_by", "")) == "human":
			return true
	return false


## Shows the card for election_held event `e` of `sim`.
func show_for(sim: Sim, e: Dictionary) -> void:
	var st := sim.state
	var office := str(e.get("office", ""))
	var el := Elections.last_result(st, office)
	var res: Dictionary = el.get("result", {})
	(%Header as Label).text = SimQuery.t_("ui.office_card.header") % SimQuery.office_name(office)
	var votes: Dictionary = res.get("votes", {})
	var most := 1
	for c: Dictionary in el.get("candidates", []):
		most = maxi(most, int(votes.get(str(c["character"]), 0)))
	var box := %Rows as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var winners: Array = res.get("winners", [])
	for c: Dictionary in el.get("candidates", []):
		var chr := str(c["character"])
		var ch: Dictionary = st.characters.get(chr, {})
		var f: Dictionary = st.families.get(str(c.get("family", "")), {})
		var row := HBoxContainer.new()
		row.name = "Row_" + chr
		row.add_theme_constant_override("separation", 6)
		var who := Label.new()
		who.custom_minimum_size = Vector2(110, 0)
		who.text = "%s%s · %s" % ["★ " if chr in winners else "", str(ch.get("name", chr)), str(f.get("name", ""))]
		who.theme_type_variation = &"GoldLabel" if chr in winners else &"BodyLabel"
		row.add_child(who)
		var track := Control.new()
		track.custom_minimum_size = Vector2(100, 12)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := ColorRect.new()
		bg.color = Color(0.2, 0.18, 0.16)
		bg.size = Vector2(100, 12)
		track.add_child(bg)
		var bar := ColorRect.new()
		bar.name = "Bar"
		bar.color = ViewConfig.color(str(f.get("colors", {}).get("primary", "#808080")))
		var n := int(votes.get(chr, 0))
		bar.size = Vector2(roundf(100.0 * float(n) / float(most)) if not bool(res.get("unopposed", false)) else 100.0, 12)
		track.add_child(bar)
		row.add_child(track)
		var nl := Label.new()
		nl.text = SimQuery.t_("ui.office_card.votes") % n if not bool(res.get("unopposed", false)) else ""
		row.add_child(nl)
		box.add_child(row)
	var wnames: PackedStringArray = []
	for w: Variant in winners:
		wnames.append(str(st.characters.get(str(w), {}).get("name", w)))
	if wnames.is_empty():
		(%Winner as Label).text = SimQuery.t_("ui.office_card.nobody")
	elif bool(res.get("unopposed", false)):
		(%Winner as Label).text = SimQuery.t_("ui.office_card.unopposed") % ", ".join(wnames)
	else:
		(%Winner as Label).text = SimQuery.t_("ui.office_card.winner") % [", ".join(wnames), SimQuery.office_name(office)]
	(%Voters as Label).text = SimQuery.t_("ui.office_card.voters") % int(res.get("voters", 0)) \
		if not bool(res.get("unopposed", false)) else ""
	var by: Dictionary = res.get("by_family", {})   # cargos_y_elecciones.md §3: the share by family
	var parts: PackedStringArray = []
	var fams: Array = by.keys()
	fams.sort()
	for f: Variant in fams:
		parts.append("%s %d" % [str(st.families.get(str(f), {}).get("name", f)), int(by[f])])
	(%ByFamily as Label).text = SimQuery.t_("ui.office_card.by_family") % " · ".join(parts) \
		if not parts.is_empty() and not bool(res.get("unopposed", false)) else ""
	(%ByFamily as Label).visible = (%ByFamily as Label).text != ""
	(%Seal as Control).visible = not winners.is_empty()
	(%OkButton as Button).text = SimQuery.t_("ui.title_card.ok")
	visible = true
	_left = float(ViewConfig.value("office_card_seconds", 10.0))
	reset_size()
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) / 2.0).round()
	ViewConfig.info("OfficeCard", "vote: %s -> %s (%s)" % [office, winners, votes])


func close() -> void:
	visible = false
	_left = 0.0


func _process(delta: float) -> void:
	if visible and _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()
