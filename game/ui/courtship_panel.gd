class_name CourtshipPanel
extends PanelContainer
## Courtship (GDD 4.10.1; docs/ui/mecanicas/cortejo_y_boda.md), in the management zone. Header: who courts (portrait,
## Charisma and what it multiplies) and how many are ready to propose. Filters Todos · Cerca · Listos. The list (most
## affinity first, scrolls): portrait with the family colour, name and age, family (rival), its title badge; the
## affinity as a bar with the mark of courtship.propose_min (change the data, the mark moves) and Talk / Gift /
## Propose; under them, with its colour, the state of the row: ready to propose, already talked today · tomorrow, far
## (where it is), blocked by an emotion and for how long; else «destaca en» its two highest stats (decision b, no
## numbers). Propose asks first with its consequences; a gift worth 50 gold or more too. Far away: the person walks
## there first with the action queued. Only reads Courtship.candidates and gives orders (order_sink).

signal closed

const FILTERS: Array[String] = ["all", "near", "ready"]
const STATS: Array[String] = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial",
	"constitution", "rhetoric", "stealth"]

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var filter: String = "all"
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	for f: String in FILTERS:
		var k := f
		(get_node("%Filter_" + f) as Button).pressed.connect(func() -> void: set_filter(k))


func setup(s: Sim, who: String) -> void:
	_bind()
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


func set_filter(f: String) -> void:
	filter = f
	refresh(true)


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	_bind()
	var st := sim.state
	var ch: Dictionary = st.characters.get(actor, {})
	var cands := Courtship.candidates(sim, actor) if not ch.is_empty() else []
	var gift := best_gift(sim, actor)
	var sig := "%s|%s|%s|%d|%s" % [actor, cands, gift, Clock.day(int(st.clock["minute"])), filter]
	if (sig == _sig or UiFeel.hold_rebuild(self)) and not force:
		return
	_sig = sig
	var cfg: Dictionary = sim.catalog.family.get("courtship", {})
	var min_aff := int(cfg.get("propose_min", 80))
	var max_aff := int(cfg.get("affinity_max", 100))
	(%Title as Label).text = SimQuery.t_("ui.court.panel_title")
	var slot := %PortraitSlot as Control
	SocialKit.clear(slot)
	if not ch.is_empty():
		slot.add_child(SocialKit.portrait(st, actor))
	var cha := SkillCheck.stat(sim, actor, "charisma")
	(%Who as Label).text = SimQuery.t_("ui.court.who") % [str(ch.get("name", "")), cha]
	var mult := 1.0 + (cha - 5) * float(cfg.get("charisma_step", 0.1))
	(%Mult as Label).text = SimQuery.t_("ui.court.mult") % ("%.2f" % mult).rstrip("0").rstrip(".").replace(".", ",")
	var ready := cands.filter(func(c: Dictionary) -> bool: return int(c["affinity"]) >= min_aff and str(c["status"]) in ["", "too_far"])
	(%Ready as Label).text = SimQuery.t_("ui.court.ready_n") % ready.size() if not ready.is_empty() else ""
	(%Hint as Label).text = SimQuery.t_("ui.court.hint") % min_aff
	for f: String in FILTERS:
		(get_node("%Filter_" + f) as Button).set_pressed_no_signal(f == filter)
		(get_node("%Filter_" + f) as Button).text = SimQuery.t_("ui.court.filter_" + f)
	var list := %List as VBoxContainer
	SocialKit.clear(list)
	(%Filters as Control).visible = not ch.is_empty() and Kin.is_single(st, actor) and Kin.is_adult(sim, actor)
	if ch.is_empty() or not Kin.is_single(st, actor) or not Kin.is_adult(sim, actor):
		list.add_child(SocialKit.label(_why_not(ch), &"DimLabel", "Why"))
		return
	if cands.is_empty():
		list.add_child(SocialKit.label(SimQuery.t_("ui.court.nobody"), &"", "Nobody"))
		list.add_child(SocialKit.label(SimQuery.t_("ui.court.nobody_hint"), &"DimLabel", "NobodyHint"))
	for c: Dictionary in cands:
		var row := _row(c, gift, min_aff, max_aff)
		row.visible = filter == "all" or (filter == "near" and str(c["status"]) != "too_far") or \
			(filter == "ready" and int(c["affinity"]) >= min_aff)
		list.add_child(row)


func _why_not(ch: Dictionary) -> String:
	if ch.is_empty():
		return SimQuery.t_("ui.npc.no_actor")
	if not Kin.is_adult(sim, actor):
		var maj := int(sim.catalog.family.get("life", {}).get("majority_age", 16))
		return SimQuery.t_("ui.court.minor") % [str(ch.get("name", "")), Kin.age(sim, actor), maj]
	var sp := str(ch.get("spouse", ""))
	return SimQuery.t_("ui.court.married") % [str(ch.get("name", "")), str(sim.state.characters.get(sp, {}).get("name", ""))]


func _row(c: Dictionary, gift: Dictionary, min_aff: int, max_aff: int) -> Control:
	var st := sim.state
	var id := str(c["character"])
	var fam := str(c["family"])
	var status := str(c["status"])
	var aff := int(c["affinity"])
	var panel := PanelContainer.new()
	panel.name = id
	panel.theme_type_variation = &"BlockedRow" if status == "offended" else &"RowPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	panel.add_child(h)
	h.add_child(SocialKit.portrait(st, id))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", -1)
	h.add_child(col)
	var top := HBoxContainer.new()
	var n := SocialKit.label("%s · %d" % [str(c["name"]), int(c["age"])], &"BoldLabel", "Name")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var title := Titles.current(sim, fam) if st.families.has(fam) else ""
	if title != "" and title != "common":
		var badge := TextureRect.new()
		badge.texture = UiIcons.mark("badge_title_" + title)
		badge.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		top.add_child(badge)
		var tn := SimQuery.title_name(title)
		top.add_child(SocialKit.label(tn.substr(0, 1).to_upper() + tn.substr(1), &"DimLabel", "Title"))
	col.add_child(top)
	var fam_name := str(st.families.get(fam, {}).get("name", ""))
	if str(st.families.get(fam, {}).get("ai_profile", "")) != "":
		fam_name = SimQuery.t_("ui.court.rival") % fam_name
	col.add_child(SocialKit.label(fam_name, &"DimLabel", "Family"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	var bar := SocialKit.threshold_bar(float(aff), float(max_aff), float(min_aff), 70.0, "Affinity")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(bar)
	var av := SocialKit.label(str(aff), &"", "Value")
	av.custom_minimum_size = Vector2(20, 0)
	av.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(av)
	var can := status in ["", "too_far"]
	line.add_child(_button("Talk", SimQuery.t_("ui.court.talk_short"), can and not talked_today(id),
		"already_today" if talked_today(id) else status,
		func() -> void: act(id, {"type": "court_talk"})))
	var gifted := Courtship.gifted_today(sim.state, actor, id)  # Equilibrio 1: the next gift today does not count
	line.add_child(_button("Gift", SimQuery.t_("ui.court.gift_done") if gifted else SimQuery.t_("ui.court.gift"),
		can and not gift.is_empty(), ("gifted_today" if gifted else status) if not gift.is_empty() else "not_enough",
		func() -> void: request_gift(id)))
	line.add_child(_button("Propose", SimQuery.t_("ui.court.propose_short"), can and aff >= min_aff,
		status if aff >= min_aff else "low_affinity", func() -> void: request_propose(id)))
	col.add_child(line)
	var st_line := status_line(c, min_aff)
	col.add_child(SocialKit.label(str(st_line[0]), StringName(st_line[1]), "Status"))
	return panel


## The state line of a candidate row: [text, label variation].
func status_line(c: Dictionary, min_aff: int) -> Array:
	return status_line_for(sim, actor, c, min_aff)


static func status_line_for(sim: Sim, actor: String, c: Dictionary, min_aff: int) -> Array:
	var id := str(c["character"])
	var status := str(c["status"])
	if status == "offended":
		var left := 0
		var name_k := ""
		var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
		for e: Dictionary in Emotions.list(sim, id):
			if str(e["source"]) == fam and str(e["state"]) in sim.catalog.family.get("courtship", {}).get("blocking_emotions", []):
				name_k = str(e["name_key"])
				for r: Dictionary in sim.state.emotions.get(id, []):
					if str(r.get("state", "")) == str(e["state"]) and str(r.get("source", "")) == fam:
						left = maxi(left, int(r.get("start", 0)) + int(r.get("duration", 0)) - int(sim.state.clock["minute"]))
		return [SimQuery.t_("ui.court.blocked") % [SimQuery.t_(name_k).to_lower(), SocialKit.duration_text(left)], "ReasonLabel"]
	if int(c["affinity"]) >= min_aff and status in ["", "too_far"]:
		return [SimQuery.t_("ui.court.ready"), "PositiveLabel"]
	var gifted := Courtship.gifted_today(sim.state, actor, id)
	if talked(sim, actor, id):
		return [SimQuery.t_("ui.court.talked_gifted" if gifted else "ui.court.talked"), "DimLabel"]
	if gifted:
		return [SimQuery.t_("ui.court.gifted"), "DimLabel"]
	if status == "too_far":
		var loc := str(sim.state.characters.get(id, {}).get("location", ""))
		if loc != "" and sim.state.buildings.has(loc):
			return [SimQuery.t_("ui.court.far_in") % SimQuery.building_label(sim.state, sim.catalog, loc), "DimLabel"]
		return [SimQuery.t_("ui.court.far"), "DimLabel"]
	return [SimQuery.t_("ui.court.stands_out") % ", ".join(stands_out(sim, id)), "DimLabel"]


## Decision (b): the two highest stats of `chr`, by name, no numbers.
static func stands_out(s: Sim, chr: String) -> PackedStringArray:
	var sd: Dictionary = s.state.characters.get(chr, {}).get("stats", {})
	var keys: Array = []
	for k: String in STATS:
		if sd.has(k):
			keys.append(k)
	keys.sort_custom(func(a: String, b: String) -> bool:
		if int(sd[a]) != int(sd[b]):
			return int(sd[a]) > int(sd[b])
		return STATS.find(a) < STATS.find(b))
	var out: PackedStringArray = []
	for k: String in keys.slice(0, 2):
		out.append(SimQuery.t_("stat." + k))
	return out


## Whether the actor already talked with `target` today (read, never created).
func talked_today(target: String) -> bool:
	return talked(sim, actor, target)


static func talked(s: Sim, who: String, target: String) -> bool:
	var r: Variant = s.state.relationships.get(Ids.pair_key(who, target))
	return r is Dictionary and int((r as Dictionary).get("talk_day", -1)) == Clock.day(int(s.state.clock["minute"]))


func _button(n: String, text: String, enabled: bool, why: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"BodyButton"
	b.disabled = not enabled
	if why != "" and why != "too_far":
		b.tooltip_text = SimQuery.reason_text(why)
	elif why == "too_far":
		b.tooltip_text = SimQuery.t_("ui.court.walk")
	b.pressed.connect(cb)
	return b


## The row of candidate `chr` (tests).
func row_of(chr: String) -> Control:
	return (%List as VBoxContainer).get_node_or_null(chr) as Control


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


## The consequences of a proposal (cortejo_y_boda.md §4): who marries whom, the job left, the home.
static func propose_lines(s: Sim, who: String, target: String) -> PackedStringArray:
	var st := s.state
	var a: Dictionary = st.characters.get(who, {})
	var t: Dictionary = st.characters.get(target, {})
	var out: PackedStringArray = [SimQuery.t_("ui.court.cons_marry") % [str(a.get("name", "")),
		str(st.families.get(str(a.get("family", "")), {}).get("name", ""))]]
	if t.get("job") is Dictionary:
		var b := str(t["job"].get("building", ""))
		out.append(SimQuery.t_("ui.court.cons_job") % SimQuery.building_label(st, s.catalog, b))
	elif str(t.get("occupation", "")) != "":
		out.append(SimQuery.t_("ui.court.cons_job") % SimQuery.occupation_name(str(t["occupation"])))
	out.append(SimQuery.t_("ui.court.cons_home"))
	return out


func request_propose(target: String) -> void:
	var st := sim.state
	var t: Dictionary = st.characters.get(target, {})
	var full := "%s %s" % [str(t.get("name", "")), str(st.families.get(str(t.get("family", "")), {}).get("name", ""))]
	SocialKit.ask(self, SimQuery.t_("ui.court.propose_q") % full.strip_edges(), "· " + "\n· ".join(propose_lines(sim, actor, target)),
		SimQuery.t_("ui.court.propose_yes"), func() -> void: act(target, {"type": "propose"}), SimQuery.t_("ui.menu.cannot_undo"), true)


func request_gift(target: String) -> void:
	var g := best_gift(sim, actor)
	if g.is_empty():
		return
	var o := {"type": "court_gift", "item": str(g["item"]), "quality": int(g["quality"])}
	var value := Market.price(sim, str(g["item"]), int(g["quality"]), "sell")
	var who := str(sim.state.characters.get(target, {}).get("name", ""))
	if Courtship.gifted_today(sim.state, actor, target):  # Equilibrio 1: says it before giving it away
		SocialKit.ask(self, SimQuery.t_("ui.court.gift_again_q") % who, SimQuery.t_("ui.court.gift_again_body"),
			SimQuery.t_("ui.court.gift_anyway"), func() -> void: act(target, o))
		return
	if value >= int(sim.catalog.town.get("actions", {}).get("gift", {}).get("grateful_min_value", 50)):
		SocialKit.ask(self, SimQuery.t_("ui.npc.ask_gift") % [SimQuery.item_label(sim.catalog, str(g["item"]),
			int(g["quality"])), value, who], "", SimQuery.t_("npc_action.gift"), func() -> void: act(target, o))
		return
	act(target, o)


## Does `order` (court_talk / court_gift / propose) towards `target`: at once if in range, else walk there first.
func act(target: String, order: Dictionary) -> void:
	for x: Dictionary in orders_for(sim, actor, target, order):
		ViewConfig.info("CourtshipPanel", "order %s" % [x])
		if order_sink.is_valid():
			order_sink.call(x)
	_sig = ""


## The orders to do a courtship `order` on `target`: itself in range, else leave / walk and the order queued behind.
static func orders_for(s: Sim, who: String, target: String, order: Dictionary) -> Array:
	var o := order.duplicate()
	o["actor"] = who
	o["target"] = target
	if Courtship.in_range(s, who, target):
		return [o]
	var orders: Array = [{"type": "hail", "actor": who, "target": target}]   # A8: they stop and wait for you
	var spot := Courtship.spot(s.state, target)
	if str(s.state.characters[who].get("location", "")) != "":
		orders.append({"type": "exit_building", "actor": who})
		orders.append({"type": "move_to", "actor": who, "tile": spot, "queued": true})
	else:
		orders.append({"type": "move_to", "actor": who, "tile": spot})
	var q := o.duplicate()
	q["queued"] = true
	orders.append(q)
	return orders
