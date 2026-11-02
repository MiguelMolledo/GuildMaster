class_name NpcPanel
extends PanelContainer
## The sheet of a townsperson (H7, GDD 4.11.5): opens with a click on somebody who is not of the player's family. Its
## trade and what it is doing now, its relation with the selected person, its emotions (icon colour, name, intensity)
## and the actions Talk / Give a gift / Flatter / Insult / Threaten. The reason a button cannot be used is its tooltip;
## far away, the selected person walks there first with the action queued (like courtship). Gift = the most valuable
## thing the selected person carries. H10: the office it holds in the info line and, while the selected person is a
## candidate, the campaign actions Visit / Bribe / Defame (defame only on another candidate of the same election;
## GDD 4.12.4). H11: «Accuse…»: a public fact against the townsperson's family, or fabricated proofs of a charge
## (GDD 4.12.5; the reason as tooltip). Only reads the state and gives orders (order_sink).

signal closed

const ACTIONS: Array[String] = ["talk", "gift", "flatter", "insult", "threaten"]
const CAMPAIGN: Array[String] = ["visit", "bribe", "defame"]  # H10

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # the selected person (who acts)
var target: String = ""  # the townsperson of the sheet
var _sig: String = ""
var _bound: bool = false
var _accuse_pick: int = 0  # H11: the chosen entry of the accuse picker (facts first, then fabricated charges)


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
	var camp: Array = []  # H10: the campaign actions while the selected person is a candidate
	if actor != "" and not Elections.candidacy(st, actor).is_empty():
		for k: String in CAMPAIGN:
			var why := Elections.action_status(sim, actor, k, target)
			if k != "defame" or why != "not_a_candidate":
				camp.append([k, why])
	var sig := "%s|%s|%s|%s|%s|%s|%d|%s|%s" % [actor, target, SimQuery.town_state_text(sim, target), emos, gift, statuses,
		Emotions.relation(st, actor, target) if actor != "" else 0, camp, Offices.of_character(st, target)] \
		+ "|%s|%d" % [Tribunal.accuse_options(sim, actor, target) if actor != "" else {}, _accuse_pick]
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
	var office := Offices.of_character(st, target)  # H10
	if office != "":
		info.append(SimQuery.office_name(office))
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
	if actor != "" and str(st.characters.get(actor, {}).get("family", "")) != str(t.get("family", "")):
		acts.add_child(_accuse_row())  # H11
	for c: Array in camp:  # H10: the campaign
		var kind := str(c[0])
		var why := str(c[1])
		var b := Button.new()
		b.name = "Campaign" + kind.capitalize()
		b.text = SimQuery.t_("campaign." + kind)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		b.disabled = not why in ["", "too_far"]
		b.tooltip_text = SimQuery.t_("ui.court.walk") if why == "too_far" else (SimQuery.reason_text(why) if why != "" \
			else SimQuery.t_("ui.npc.campaign_tip"))
		b.pressed.connect(func() -> void: do_campaign(kind))
		acts.add_child(b)
	reset_size()


## H11: the accuse picker (public facts against the target's family, then «fabricate: <charge>») and its button.
func _accuse_entries() -> Array:
	var o := Tribunal.accuse_options(sim, actor, target)
	var out: Array = []
	for f: Variant in o["facts"]:
		var fa := Tribunal.fact(sim.state, str(f))
		out.append({"fact": str(f), "text": SimQuery.t_("ui.npc.accuse_fact") % [SimQuery.t_("charge." + str(fa["charge"])),
			int(fa["day"]) + 1]})
	for c: Variant in o["charges"]:
		out.append({"charge": str(c), "fabricate": true, "text": SimQuery.t_("ui.npc.accuse_fabricate") %
			SimQuery.t_("charge." + str(c))})
	return out


func _accuse_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "AccuseRow"
	var entries := _accuse_entries()
	_accuse_pick = clampi(_accuse_pick, 0, maxi(0, entries.size() - 1))
	var ob := OptionButton.new()
	ob.name = "AccusePick"
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 10)
	for e: Dictionary in entries:
		ob.add_item(str(e["text"]))
	if not entries.is_empty():
		ob.select(_accuse_pick)
	ob.item_selected.connect(func(i: int) -> void:
		_accuse_pick = i
		_sig = "")
	row.add_child(ob)
	var b := Button.new()
	b.name = "Accuse"
	b.text = SimQuery.t_("ui.npc.accuse")
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	var e: Dictionary = entries[_accuse_pick] if not entries.is_empty() else {}
	var why := Tribunal.accuse_status(sim, actor, target, str(e.get("fact", "")), str(e.get("charge", "")),
		bool(e.get("fabricate", false)))
	b.disabled = why != "" or e.is_empty()
	b.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.npc.accuse_tip_fabricate" if bool(e.get(
		"fabricate", false)) else "ui.npc.accuse_tip")
	b.pressed.connect(func() -> void:
		var o := {"type": "accuse", "actor": actor, "target": target}
		if bool(e.get("fabricate", false)):
			o["fabricate"] = true
			o["charge"] = str(e["charge"])
		else:
			o["fact"] = str(e.get("fact", ""))
		ViewConfig.info("NpcPanel", "order %s" % [o])
		if order_sink.is_valid():
			order_sink.call(o)
		_sig = "")
	row.add_child(b)
	return row


## H10: a campaign action on the townsperson: at once in range (defame anywhere), else walking there first.
func do_campaign(kind: String) -> void:
	if sim == null or actor == "":
		return
	var o := {"type": "campaign_action", "actor": actor, "kind": kind, "target": target}
	var orders: Array = []
	if kind == "defame" or NpcActions.in_range(sim, actor, target):
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
