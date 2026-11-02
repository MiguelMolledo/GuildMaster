class_name NpcPanel
extends PanelContainer
## The sheet of a townsperson (H7, GDD 4.11.5): opens with a click on somebody who is not of the player's family. Its
## trade and what it is doing now, its relation with the selected person, its emotions (icon colour, name, intensity)
## and the actions Talk / Give a gift / Flatter / Insult / Threaten. The reason a button cannot be used is its tooltip;
## far away, the selected person walks there first with the action queued (like courtship). Gift = the most valuable
## thing the selected person carries. Only reads the state and gives orders (order_sink).

signal closed

const ACTIONS: Array[String] = ["talk", "gift", "flatter", "insult", "threaten"]

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # the selected person (who acts)
var target: String = ""  # the townsperson of the sheet
var _sig: String = ""
var _bound: bool = false


func setup(s: Sim, who: String, npc: String) -> void:
	if not _bound:
		_bound = true
		(%CloseButton as Button).pressed.connect(close)
	sim = s
	actor = who
	target = npc
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
	var st := sim.state
	var t: Dictionary = st.characters.get(target, {})
	if t.is_empty() or not bool(t.get("alive", true)):
		close()
		return
	var fam: Dictionary = st.families.get(str(t.get("family", "")), {})
	var emos := Emotions.list(sim, target)
	var gift := CourtshipPanel.best_gift(sim, actor)
	var statuses: Array = []
	for a: String in ACTIONS:
		statuses.append(NpcActions.status(sim, actor, target, a) if actor != "" else "unknown_actor")
	var sig := "%s|%s|%s|%s|%s|%s|%d" % [actor, target, SimQuery.town_state_text(sim, target), emos, gift, statuses,
		Emotions.relation(st, actor, target) if actor != "" else 0]
	if sig == _sig and not force:
		return
	_sig = sig
	(%Title as Label).text = "%s · %s" % [str(t.get("name", target)), str(fam.get("name", ""))]
	var info: Array = []
	var occ := SimQuery.occupation_name(str(t.get("occupation", "")))
	if occ != "":
		info.append(occ)
	if str(t.get("rank", "")) != "":
		info.append(SimQuery.rank_name(sim.catalog, str(t["rank"])))
	info.append(SimQuery.t_("ui.npc.age") % Kin.age(sim, target))
	(%Info as Label).text = " · ".join(info)
	(%Doing as Label).text = SimQuery.town_state_text(sim, target)
	var a: Dictionary = st.characters.get(actor, {})
	(%Relation as Label).text = SimQuery.t_("ui.npc.relation") % [str(a.get("name", "—")),
		Emotions.relation(st, actor, target)] if not a.is_empty() else SimQuery.t_("ui.npc.no_actor")
	var box := %Emotions as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if emos.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.npc.calm")
		l.add_theme_font_size_override("font_size", 10)
		box.add_child(l)
	for e: Dictionary in emos:
		var row := HBoxContainer.new()
		row.name = "Emotion_" + str(e["state"])
		var icon := VisualPaths.instantiate("bubbles", str(e["icon"]))  # the same bubble as over the head
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(26, 22)
		VisualPaths.place(icon, Vector2(13, 21))
		holder.add_child(icon)
		row.add_child(holder)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 10)
		var src := str(st.families.get(str(e["source"]), {}).get("name", e["source"]))
		l.text = SimQuery.t_("ui.npc.emotion") % [SimQuery.t_(str(e["name_key"])), src, int(e["intensity"])]
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		box.add_child(row)
	var acts := %Actions as HFlowContainer
	for c: Node in acts.get_children():
		acts.remove_child(c)
		c.queue_free()
	for i: int in ACTIONS.size():
		var act: String = ACTIONS[i]
		var why: String = statuses[i]
		if act == "gift" and gift.is_empty() and why in ["", "too_far"]:
			why = "no_item"
		var b := Button.new()
		b.name = act.capitalize()
		b.text = SimQuery.t_("npc_action." + act)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.disabled = not why in ["", "too_far"]
		if why == "too_far":
			b.tooltip_text = SimQuery.t_("ui.court.walk")
		elif why != "":
			b.tooltip_text = SimQuery.reason_text(why)
		elif act == "gift":
			b.tooltip_text = SimQuery.item_label(sim.catalog, str(gift["item"]), int(gift["quality"]))
		b.pressed.connect(func() -> void: do_action(act))
		acts.add_child(b)
	reset_size()


## Gives the npc_<action> order: at once in range, else walking there first (the action queued behind).
func do_action(act: String) -> void:
	if sim == null or actor == "":
		return
	var o := {"type": "npc_" + act, "actor": actor, "target": target}
	if act == "gift":
		var g := CourtshipPanel.best_gift(sim, actor)
		if g.is_empty():
			return
		o["item"] = str(g["item"])
		o["quality"] = int(g["quality"])
	var orders: Array = []
	if NpcActions.in_range(sim, actor, target):
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
		ViewConfig.info("NpcPanel", "order %s" % [x])
		if order_sink.is_valid():
			order_sink.call(x)
	_sig = ""
