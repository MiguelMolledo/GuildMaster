class_name CourtshipPanel
extends PanelContainer
## Courtship (GDD 4.10.1): the single adults the selected person could court, most affinity first, each with its
## affinity bar and Talk / Gift / Propose (Propose from 80). The reason a button cannot be used is its tooltip. Far
## away: the person walks there first (exit_building, move_to to their door or tile) with the action queued behind,
## so it happens on arrival. Gift = the most valuable thing the person carries. Only reads Courtship.candidates and
## gives orders (order_sink).

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var _sig: String = ""
var _bound: bool = false


func setup(s: Sim, who: String) -> void:
	if not _bound:
		_bound = true
		(%CloseButton as Button).pressed.connect(close)
	sim = s
	actor = who
	refresh(true)


func open() -> void:
	visible = true
	refresh(true)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var ch: Dictionary = sim.state.characters.get(actor, {})
	(%Title as Label).text = SimQuery.t_("ui.court.title") % str(ch.get("name", ""))
	var cands := Courtship.candidates(sim, actor) if not ch.is_empty() else []
	var gift := best_gift(sim, actor)
	var sig := "%s|%s|%s|%d" % [actor, cands, gift, Clock.day(int(sim.state.clock["minute"]))]
	if sig == _sig and not force:
		return
	_sig = sig
	var list := %List as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if ch.is_empty() or not Kin.is_single(sim.state, actor) or not Kin.is_adult(sim, actor):
		var l := Label.new()
		l.text = SimQuery.reason_text("not_single" if Kin.is_adult(sim, actor) else "too_young")
		list.add_child(l)
		return
	if cands.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.court.nobody")
		list.add_child(l)
	var min_aff := int(sim.catalog.family.get("courtship", {}).get("propose_min", 80))
	for c: Dictionary in cands:
		var row := HBoxContainer.new()
		row.name = str(c["character"])
		var info := Label.new()
		info.custom_minimum_size = Vector2(150, 0)
		info.add_theme_font_size_override("font_size", 10)
		info.text = "%s · %s · %d" % [c["name"], str(sim.state.families.get(str(c["family"]), {}).get("name", "")), int(c["age"])]
		row.add_child(info)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(70, 10)
		bar.max_value = 100
		bar.value = int(c["affinity"])
		bar.show_percentage = false
		bar.tooltip_text = SimQuery.t_("ui.court.affinity") % int(c["affinity"])
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var aff := Label.new()
		aff.add_theme_font_size_override("font_size", 10)
		aff.text = str(int(c["affinity"]))
		aff.custom_minimum_size = Vector2(20, 0)
		row.add_child(aff)
		var status := str(c["status"])
		var can := status in ["", "too_far"]
		row.add_child(_button("Talk", SimQuery.t_("ui.court.talk"), can, status,
			func() -> void: act(str(c["character"]), {"type": "court_talk"})))
		row.add_child(_button("Gift", SimQuery.t_("ui.court.gift"), can and not gift.is_empty(),
			status if not gift.is_empty() else "not_enough",
			func() -> void: act(str(c["character"]), {"type": "court_gift", "item": gift.get("item", ""),
				"quality": int(gift.get("quality", 0))})))
		row.add_child(_button("Propose", SimQuery.t_("ui.court.propose"), can and int(c["affinity"]) >= min_aff,
			status if int(c["affinity"]) >= min_aff else "low_affinity",
			func() -> void: act(str(c["character"]), {"type": "propose"})))
		list.add_child(row)


func _button(n: String, text: String, enabled: bool, why: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 10)
	b.disabled = not enabled
	if why != "" and why != "too_far":
		b.tooltip_text = SimQuery.reason_text(why)
	elif why == "too_far":
		b.tooltip_text = SimQuery.t_("ui.court.walk")
	b.pressed.connect(cb)
	return b


## The most valuable item the actor carries (sell price), {} if none: {item, quality}.
static func best_gift(s: Sim, who: String) -> Dictionary:
	var best := {}
	var best_p := -1
	for st: Dictionary in s.state.characters.get(who, {}).get("inventory", {}).get("stacks", []):
		var p := Market.price(s, str(st["item"]), int(st["quality"]), "sell")
		if p > best_p:
			best_p = p
			best = {"item": str(st["item"]), "quality": int(st["quality"])}
	return best


## Does `order` (court_talk / court_gift / propose) towards `target`: at once if in range, else walk there first.
func act(target: String, order: Dictionary) -> void:
	var o := order.duplicate()
	o["actor"] = actor
	o["target"] = target
	var orders: Array = []
	if Courtship.in_range(sim, actor, target):
		orders.append(o)
	else:
		var spot := Courtship.spot(sim.state, target)
		if str(sim.state.characters[actor].get("location", "")) != "":
			orders.append({"type": "exit_building", "actor": actor})
			orders.append({"type": "move_to", "actor": actor, "tile": spot, "queued": true})
		else:
			orders.append({"type": "move_to", "actor": actor, "tile": spot})
		var q := o.duplicate()
		q["queued"] = true
		orders.append(q)
	for x: Dictionary in orders:
		ViewConfig.info("CourtshipPanel", "order %s" % [x])
		if order_sink.is_valid():
			order_sink.call(x)
	_sig = ""
