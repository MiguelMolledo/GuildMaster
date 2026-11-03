class_name NpcPanel
extends PanelContainer
## The sheet of a townsperson (H7, GDD 4.11.5; docs/ui/mecanicas/ciudad_viva.md §3-4), in the management zone: opens
## with a click on somebody who is not of the player's family. First the portrait with the family's border, name and
## family, trade · age, the rank badge and what it is doing now; then the relation with the selected person as a
## bipolar bar with its word and number; then its emotions towards the player's family (name, intensity bar, time
## left and what they do: prices, refuses to talk or to trade), the ones towards other families folded in one line.
## Actions Talk / Give a gift / Flatter / Insult / Threaten with their foreseen effect in the tooltip (the odds of a
## skill check as a band, _social rule 3) and the reason a button is off written under them (the hovered one, else
## the first one off). Insult and Threaten always ask first, a gift worth 50 gold or more too (_social rule 2). Far
## away, the selected person walks there first with the action queued. H10: the office it holds and, while the
## selected person is a candidate, Visit / Bribe / Defame (bribe and defame ask first). H11: «Accuse…» (asks first).
## Only reads the state and gives orders (order_sink).

signal closed

const ACTIONS: Array[String] = ["talk", "gift", "flatter", "insult", "threaten"]
const CAMPAIGN: Array[String] = ["visit", "bribe", "defame"]  # H10
const ALWAYS_ASK: Array[String] = ["insult", "threaten"]
const CAMPAIGN_ASK: Array[String] = ["bribe", "defame"]

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # the selected person (who acts)
var target: String = ""  # the townsperson of the sheet
var _sig: String = ""
var _bound: bool = false
var _accuse_pick: int = 0  # H11: the chosen entry of the accuse picker (facts first, then fabricated charges)
var _reasons: Dictionary = {}  # button name -> the reason it is off ("" if on)
var _hovered: String = ""      # the button under the mouse (its reason is the one written)
var _bar: RelationBar = null


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%FamilyLink as Button).pressed.connect(open_family)   # rivales.md: «de la familia Soler ›»
	_bar = RelationBar.new()
	_bar.name = "Bar"
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(%RelationBar as Control).add_child(_bar)


func setup(s: Sim, who: String, npc: String) -> void:
	_bind()
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
	_bind()
	var st := sim.state
	var t: Dictionary = st.characters.get(target, {})
	if t.is_empty() or not bool(t.get("alive", true)):
		close()
		return
	var my_fam := str(st.characters.get(actor, {}).get("family", "")) if actor != "" else SimQuery.player_family(st)
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
	var rel := Emotions.relation(st, actor, target) if actor != "" else 0
	var sig := "%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%d|%s" % [actor, target, SimQuery.town_state_text(sim, target), emos, gift,
		statuses, rel, camp, Offices.of_character(st, target), Tribunal.accuse_options(sim, actor, target) if actor != "" \
		else {}, _accuse_pick, _hovered] + "|%s" % [Courtship.affinity(st, actor, target) if actor != "" else 0]
	if sig == _sig and not force:
		return
	_sig = sig
	_fill_head(t)
	_fill_relation(rel)
	_fill_emotions(emos, my_fam)
	_fill_actions(statuses, gift, camp, t)
	_fill_court()
	_update_reason()
	reset_size()


func _fill_head(t: Dictionary) -> void:
	var st := sim.state
	var fam: Dictionary = st.families.get(str(t.get("family", "")), {})
	(%Title as Label).text = "%s · %s" % [str(t.get("name", target)), str(fam.get("name", ""))]
	var slot := %PortraitSlot as Control
	SocialKit.clear(slot)
	slot.add_child(SocialKit.portrait(st, target))
	var info: Array = []
	var occ := SimQuery.occupation_name(str(t.get("occupation", "")))
	if occ != "":
		info.append(occ)
	info.append(SimQuery.t_("ui.npc.age") % Kin.age(sim, target))
	var office := Offices.of_character(st, target)  # H10
	if office != "":
		info.append(SimQuery.office_name(office))
	(%Info as Label).text = " · ".join(info)
	var rank := str(t.get("rank", ""))
	(%RankRow as Control).visible = rank != ""
	if rank != "":
		var ids: Array = (sim.catalog.employees.get("ranks", {}) as Dictionary).keys()
		var path := "res://assets/art/ui/marks/rank_%d.png" % (ids.find(rank) + 1)
		(%RankBadge as TextureRect).texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
		(%Rank as Label).text = SimQuery.rank_name(sim.catalog, rank)
	var icon_slot := %DoingIcon as Control
	SocialKit.clear(icon_slot)
	var bubble := SimQuery.bubble_of(sim, target)
	if bubble != "":
		var b := VisualPaths.instantiate("bubbles", bubble)
		if b != null:
			VisualPaths.place(b, Vector2(13, 20))
			icon_slot.add_child(b)
	(%Doing as Label).text = SimQuery.town_state_text(sim, target)
	(%FamilyLink as Button).text = SimQuery.t_("ui.npc.family_link") % str(fam.get("name", ""))
	(%FamilyLink as Button).visible = fam.size() > 0 and str(t.get("family", "")) != SimQuery.player_family(st)


func _fill_relation(rel: int) -> void:
	var a: Dictionary = sim.state.characters.get(actor, {})
	(%Relation as Label).text = SimQuery.t_("ui.npc.relation_with") % str(a.get("name", "—")) if not a.is_empty() \
		else SimQuery.t_("ui.npc.no_actor")
	(%RelationWord as Label).text = "%s %s" % [SocialKit.relation_word(rel), SocialKit.signed(rel) if rel != 0 else "0"]
	_bar.value = rel


## The emotions towards the player's family, with what they do; the ones towards other families folded.
func _fill_emotions(emos: Array, my_fam: String) -> void:
	var st := sim.state
	(%EmotionsTitle as Label).text = SimQuery.t_("ui.npc.towards_family")
	var box := %Emotions as VBoxContainer
	SocialKit.clear(box)
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	var others: PackedStringArray = []
	for e: Dictionary in emos:
		if str(e["source"]) != my_fam:
			others.append(SimQuery.t_("ui.npc.emotion_other") % [SimQuery.t_(str(e["name_key"])),
				str(st.families.get(str(e["source"]), {}).get("name", e["source"]))])
			continue
		box.add_child(_emotion_row(e, defs.get(str(e["state"]), {})))
	if box.get_child_count() == 0:
		box.add_child(SocialKit.label(SimQuery.t_("ui.npc.no_emotions"), &"DimLabel", "None"))
	(%Others as Label).visible = not others.is_empty()
	(%Others as Label).text = SimQuery.t_("ui.npc.others") % others.size()
	(%Others as Label).tooltip_text = "\n".join(others)


func _emotion_row(e: Dictionary, d: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "Emotion_" + str(e["state"])
	col.add_theme_constant_override("separation", -2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(26, 20)
	var icon := VisualPaths.instantiate("bubbles", str(e["icon"]))  # the same bubble as over the head
	if icon != null:
		VisualPaths.place(icon, Vector2(13, 20))
		holder.add_child(icon)
	row.add_child(holder)
	var bad := float(d.get("buy_mult", 1.0)) > 1.0 or bool(d.get("refuses_talk", false))
	var n := SocialKit.label(SimQuery.t_(str(e["name_key"])), &"ReasonLabel" if bad else &"PositiveLabel", "Name")
	n.custom_minimum_size = Vector2(92, 0)
	row.add_child(n)
	var bar := SocialKit.bar(float(e["intensity"]) / 100.0, 140.0, "Intensity")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var left := _minutes_left(e)
	var time := SocialKit.label(SocialKit.duration_text(left), &"DimLabel", "Left")
	time.custom_minimum_size = Vector2(44, 0)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(time)
	col.add_child(row)
	var fx := effects_text(d)
	if fx != "":
		var l := SocialKit.label(fx, &"DimLabel", "Effects")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		col.add_child(l)
	return col


## Minutes until an emotion of Emotions.list ends (its record in the state; intensity falls to 0 at the end).
func _minutes_left(e: Dictionary) -> int:
	for r: Dictionary in sim.state.emotions.get(target, []):
		if str(r.get("state", "")) == str(e["state"]) and str(r.get("source", "")) == str(e["source"]):
			return maxi(0, int(r.get("start", 0)) + int(r.get("duration", 0)) - int(sim.state.clock["minute"]))
	return 0


## What an emotion does, from data/town.json emotions.<id> ("precios +25 % · no quiere hablar · no comercia > 80").
static func effects_text(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	var buy := float(d.get("buy_mult", 1.0))
	if not is_equal_approx(buy, 1.0):
		parts.append(SimQuery.t_("ui.npc.fx_prices") % SocialKit.signed(roundi((buy - 1.0) * 100.0)))
	if bool(d.get("refuses_talk", false)):
		parts.append(SimQuery.t_("ui.npc.fx_no_talk"))
	if d.get("refuses_trade_over") != null:
		parts.append(SimQuery.t_("ui.npc.fx_no_trade") % int(d["refuses_trade_over"]))
	return " · ".join(parts)


func _fill_actions(statuses: Array, gift: Dictionary, camp: Array, t: Dictionary) -> void:
	var st := sim.state
	var acts := %Actions as HFlowContainer
	SocialKit.clear(acts)
	_reasons.clear()
	var cfg: Dictionary = sim.catalog.town.get("actions", {})
	for i: int in ACTIONS.size():
		var act: String = ACTIONS[i]
		var why: String = statuses[i]
		if act == "gift" and gift.is_empty() and why in ["", "too_far"]:
			why = "no_item"
		var b := Button.new()
		b.name = act.capitalize()
		b.text = SimQuery.t_("npc_action." + act)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not why in ["", "too_far"]
		b.tooltip_text = action_tip(act, gift, cfg)
		if why == "too_far":
			b.tooltip_text += "\n" + SimQuery.t_("ui.court.walk")
		_reasons[b.name] = SimQuery.t_("ui.npc.reason_line") % [b.text, _reason_text(why)] if b.disabled else ""
		b.mouse_entered.connect(_hover.bind(b.name))
		b.mouse_exited.connect(_hover.bind(""))
		b.pressed.connect(func() -> void: request_action(act))
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
		b.theme_type_variation = &"BodyButton"
		b.disabled = not why in ["", "too_far"]
		b.tooltip_text = SimQuery.t_("ui.court.walk") if why == "too_far" else (SimQuery.reason_text(why) if why != "" \
			else SimQuery.t_("ui.npc.campaign_tip"))
		_reasons[b.name] = SimQuery.t_("ui.npc.reason_line") % [b.text, SimQuery.reason_text(why)] if b.disabled else ""
		b.mouse_entered.connect(_hover.bind(b.name))
		b.mouse_exited.connect(_hover.bind(""))
		b.pressed.connect(func() -> void: request_campaign(kind))
		acts.add_child(b)


## The sheet of the townsperson's family (the families panel, rivales.md).
func open_family() -> void:
	if not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group(FamiliesPanel.GROUP) as FamiliesPanel
	if p != null:
		p.open_for(sim, actor, str(sim.state.characters.get(target, {}).get("family", "")))


## cortejo_y_boda.md §6: while the townsperson is someone the selected person could court, a Courtship section with
## the affinity bar (the mark of propose_min) and Talk / Gift / Propose (the same orders as the courtship panel).
func _fill_court() -> void:
	var box := %CourtBox as Control
	var entry := {}
	if actor != "":
		for c: Dictionary in Courtship.candidates(sim, actor):
			if str(c["character"]) == target:
				entry = c
	box.visible = not entry.is_empty() and Kin.is_single(sim.state, actor)
	if not box.visible:
		return
	var cfg: Dictionary = sim.catalog.family.get("courtship", {})
	var min_aff := int(cfg.get("propose_min", 80))
	var aff := int(entry["affinity"])
	(%CourtTitle as Label).text = SimQuery.t_("ui.court.section")
	(%CourtAffinity as Label).text = SimQuery.t_("ui.court.affinity") % aff
	var slot := %CourtBarSlot as Control
	SocialKit.clear(slot)
	var bar := SocialKit.threshold_bar(float(aff), float(cfg.get("affinity_max", 100)), float(min_aff), 300.0, "Affinity")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(bar)
	var acts := %CourtActions as Control
	SocialKit.clear(acts)
	var status := str(entry["status"])
	var can := status in ["", "too_far"]
	var talked := CourtshipPanel.talked(sim, actor, target)
	var gift := CourtshipPanel.best_gift(sim, actor)
	for spec: Array in [["CourtTalk", "ui.court.talk_short", can and not talked, func() -> void: _court({"type": "court_talk"})],
			["CourtGift", "ui.court.gift", can and not gift.is_empty(), _court_gift],
			["CourtPropose", "ui.court.propose_short", can and aff >= min_aff, _court_propose]]:
		var b := Button.new()
		b.name = str(spec[0])
		b.text = SimQuery.t_(str(spec[1]))
		b.theme_type_variation = &"BodyButton"
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not bool(spec[2])
		b.pressed.connect(spec[3])
		acts.add_child(b)
	var line: Array = CourtshipPanel.status_line_for(sim, actor, entry, min_aff)
	(%CourtStatus as Label).text = str(line[0])
	(%CourtStatus as Label).theme_type_variation = StringName(line[1])


func _court(o: Dictionary) -> void:
	_give(CourtshipPanel.orders_for(sim, actor, target, o))


func _court_gift() -> void:
	var g := CourtshipPanel.best_gift(sim, actor)
	if g.is_empty():
		return
	var o := {"type": "court_gift", "item": str(g["item"]), "quality": int(g["quality"])}
	var value := Market.price(sim, str(g["item"]), int(g["quality"]), "sell")
	if value >= int(sim.catalog.town.get("actions", {}).get("gift", {}).get("grateful_min_value", 50)):
		SocialKit.ask(self, SimQuery.t_("ui.npc.ask_gift") % [SimQuery.item_label(sim.catalog, str(g["item"]),
			int(g["quality"])), value, str(sim.state.characters.get(target, {}).get("name", ""))], "",
			SimQuery.t_("npc_action.gift"), func() -> void: _court(o))
		return
	_court(o)


## Proposing asks first with its consequences (cortejo_y_boda.md §4).
func _court_propose() -> void:
	var t: Dictionary = sim.state.characters.get(target, {})
	var full := "%s %s" % [str(t.get("name", "")), str(sim.state.families.get(str(t.get("family", "")), {}).get("name", ""))]
	SocialKit.ask(self, SimQuery.t_("ui.court.propose_q") % full.strip_edges(), "· " + "\n· ".join(
		CourtshipPanel.propose_lines(sim, actor, target)), SimQuery.t_("ui.court.propose_yes"),
		func() -> void: _court({"type": "propose"}), SimQuery.t_("ui.menu.cannot_undo"), true)


## The reason of a status, saying when it is mended if it is a matter of time (_social rule 1).
func _reason_text(why: String) -> String:
	match why:
		"refuses_talk":
			var left := 0
			var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
			var defs: Dictionary = sim.catalog.town.get("emotions", {})
			for e: Dictionary in Emotions.list(sim, target):
				if str(e["source"]) == fam and bool(defs.get(str(e["state"]), {}).get("refuses_talk", false)):
					left = maxi(left, _minutes_left(e))
			return SimQuery.t_("ui.npc.why_refuses") % SocialKit.duration_text(left)
		"already_today":
			return SimQuery.t_("ui.npc.why_today")
	return SimQuery.reason_text(why)


## The foreseen effect of an action (its tooltip): figures of data/town.json actions, odds as a band.
func action_tip(act: String, gift: Dictionary, cfg: Dictionary) -> String:
	var c: Dictionary = cfg.get(act, {})
	match act:
		"talk":
			return SimQuery.t_("ui.npc.tip_talk") % int(c.get("relation", 2))
		"gift":
			if gift.is_empty():
				return SimQuery.t_("reason.no_item")
			var value := Market.price(sim, str(gift["item"]), int(gift["quality"]), "sell")
			return SimQuery.t_("ui.npc.tip_gift") % [SimQuery.item_label(sim.catalog, str(gift["item"]), int(gift["quality"])),
				value]
		"flatter", "threaten":
			var a_stat := str(c.get("actor_stat", "charisma"))
			var t_stat := str(c.get("target_stat", "empathy"))
			var band := SocialKit.check_band(sim, actor, target, a_stat, t_stat)
			return SimQuery.t_("ui.npc.tip_check") % [SocialKit.check_text(band, a_stat, t_stat),
				SocialKit.signed(int(c.get("success_relation", 0))), SocialKit.signed(int(c.get("fail_relation", 0)))]
		"insult":
			return SimQuery.t_("ui.npc.tip_insult") % SocialKit.signed(int(c.get("relation", -10)))
	return ""


func _hover(button: String) -> void:
	_hovered = button
	_update_reason()


## The reason line: the one of the hovered button, else of the first button that is off.
func _update_reason() -> void:
	var text := str(_reasons.get(_hovered, ""))
	if text == "":
		for n: String in _reasons:
			if str(_reasons[n]) != "":
				text = str(_reasons[n])
				break
	SocialKit.set_reason(%Reason as Label, text)


func reason_text() -> String:
	return (%Reason as Label).text if (%Reason as Label).visible else ""


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
	row.custom_minimum_size = Vector2(320, 0)
	var entries := _accuse_entries()
	_accuse_pick = clampi(_accuse_pick, 0, maxi(0, entries.size() - 1))
	var ob := OptionButton.new()
	ob.name = "AccusePick"
	ob.focus_mode = Control.FOCUS_NONE
	ob.clip_text = true   # fits the management zone (356): the long charges are cut, the tooltip has them
	ob.fit_to_longest_item = false
	ob.theme_type_variation = &"BodyButton"
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var e: Dictionary = entries[_accuse_pick] if not entries.is_empty() else {}
	var why := Tribunal.accuse_status(sim, actor, target, str(e.get("fact", "")), str(e.get("charge", "")),
		bool(e.get("fabricate", false)))
	b.disabled = why != "" or e.is_empty()
	b.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.npc.accuse_tip_fabricate" if bool(e.get(
		"fabricate", false)) else "ui.npc.accuse_tip")
	_reasons[b.name] = SimQuery.t_("ui.npc.reason_line") % [b.text, SimQuery.reason_text(why)] if why != "" else ""
	b.mouse_entered.connect(_hover.bind(b.name))
	b.mouse_exited.connect(_hover.bind(""))
	b.pressed.connect(func() -> void:
		var o := {"type": "accuse", "actor": actor, "target": target}
		if bool(e.get("fabricate", false)):
			o["fabricate"] = true
			o["charge"] = str(e["charge"])
		else:
			o["fact"] = str(e.get("fact", ""))
		var name_t := str(sim.state.characters.get(target, {}).get("name", target))
		SocialKit.ask(self, SimQuery.t_("ui.npc.accuse_q") % name_t, accuse_risk(e), SimQuery.t_("ui.npc.accuse"),
			func() -> void: _give([o]), SimQuery.t_("ui.menu.cannot_undo")))
	row.add_child(b)
	return row


## What an accusation risks (tribunal.md §4): a false one lost costs reputation; fabricated proofs, its odds.
func accuse_risk(e: Dictionary) -> String:
	var ac: Dictionary = sim.catalog.justice.get("accuse", {})
	var out := str(e.get("text", "")) + ". " + SimQuery.t_("ui.npc.accuse_false") % SocialKit.signed(int(ac.get("false_reputation", -50)))
	if bool(e.get("fabricate", false)):
		var fc: Dictionary = ac.get("fabricate", {})
		var b := SocialKit.check_band(sim, actor, target, str(fc.get("stat", "stealth")), "", int(fc.get("target", 5)))
		out += " " + SimQuery.t_("ui.npc.accuse_fabricate_risk") % [SocialKit.check_text(b, str(fc.get("stat", "stealth")), ""),
			SocialKit.signed(int(fc.get("fail_reputation", -50)))]
	return out


## A button of the sheet: the irreversible ones ask first (_social rule 2), the others go at once.
func request_action(act: String) -> void:
	if sim == null or actor == "":
		return
	var name_t := str(sim.state.characters.get(target, {}).get("name", target))
	if act in ALWAYS_ASK:
		var c: Dictionary = sim.catalog.town.get("actions", {}).get(act, {})
		var body := action_tip(act, {}, sim.catalog.town.get("actions", {}))
		SocialKit.ask(self, SimQuery.t_("ui.npc.ask_" + act) % name_t, body, SimQuery.t_("npc_action." + act),
			func() -> void: do_action(act), SimQuery.t_("ui.menu.cannot_undo") if c.has("emotion") or act == "insult" else "")
		return
	if act == "gift":
		var g := CourtshipPanel.best_gift(sim, actor)
		if g.is_empty():
			return
		var value := Market.price(sim, str(g["item"]), int(g["quality"]), "sell")
		var min_v := int(sim.catalog.town.get("actions", {}).get("gift", {}).get("grateful_min_value", 50))
		if value >= min_v:
			SocialKit.ask(self, SimQuery.t_("ui.npc.ask_gift") % [SimQuery.item_label(sim.catalog, str(g["item"]),
				int(g["quality"])), value, name_t], "", SimQuery.t_("npc_action.gift"), func() -> void: do_action(act))
			return
	do_action(act)


func request_campaign(kind: String) -> void:
	if kind in CAMPAIGN_ASK:
		var name_t := str(sim.state.characters.get(target, {}).get("name", target))
		SocialKit.ask(self, SimQuery.t_("ui.npc.ask_" + kind) % name_t, campaign_risk(kind),
			SimQuery.t_("campaign." + kind), func() -> void: do_campaign(kind), SimQuery.t_("ui.menu.cannot_undo"))
		return
	do_campaign(kind)


## What a bribe or a defamation risks, with its odds as a band (data/politics.json elections.actions).
func campaign_risk(kind: String) -> String:
	var a: Dictionary = sim.catalog.politics.get("elections", {}).get("actions", {}).get(kind, {})
	if kind == "bribe":
		var b := SocialKit.check_band(sim, actor, target, "stealth", "empathy")
		return SimQuery.t_("ui.npc.risk_bribe") % [int(a.get("gold", 20)), SocialKit.check_text(b, "stealth", "empathy"),
			SocialKit.signed(int(a.get("scandal", -10)))]
	var d := SocialKit.check_band(sim, actor, target, "stealth", "", int(a.get("target_value", 5)), int(a.get("modifier", 0)))
	return SimQuery.t_("ui.npc.risk_defame") % [SocialKit.check_text(d, "stealth", ""), SocialKit.signed(int(a.get("scandal", -20)))]


## H10: a campaign action on the townsperson: at once in range (defame anywhere), else walking there first.
func do_campaign(kind: String) -> void:
	if sim == null or actor == "":
		return
	var o := {"type": "campaign_action", "actor": actor, "kind": kind, "target": target}
	_give(_reach(o, kind == "defame" or NpcActions.in_range(sim, actor, target)))


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
	_give(_reach(o, NpcActions.in_range(sim, actor, target)))


## The orders to do `o`: itself if `here`, else leave the building / walk to the target and `o` queued behind.
func _reach(o: Dictionary, here: bool) -> Array:
	if here:
		return [o]
	var orders: Array = []
	var spot := Courtship.spot(sim.state, target)
	if str(sim.state.characters[actor].get("location", "")) != "":
		orders.append({"type": "exit_building", "actor": actor})
		orders.append({"type": "move_to", "actor": actor, "tile": spot, "queued": true})
	else:
		orders.append({"type": "move_to", "actor": actor, "tile": spot})
	var q := o.duplicate()
	q["queued"] = true
	orders.append(q)
	return orders


func _give(orders: Array) -> void:
	for x: Dictionary in orders:
		ViewConfig.info("NpcPanel", "order %s" % [x])
		if order_sink.is_valid():
			order_sink.call(x)
	_sig = ""
