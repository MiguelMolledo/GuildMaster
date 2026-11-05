class_name TownHallPanel
extends PanelContainer
## The town hall (GDD 4.12.2, H9; docs/ui/mecanicas/titulos_y_reputacion.md), in the management zone. The family's
## ribbon, name, reputation and today's changes; the ladder of the five titles (the current one marked, the next one
## lit, the ones reached in gold); the next title with its cost and each requirement as a bar with its figure (green
## when met, red with what is missing); what it opens; who approves it (Titles.approver: portrait, office, affinity
## against the mark it needs, or vacant: approved by itself); «Pedir el título» (asks first: it costs gold, «Te quedan
## …») off with its reason written; «Cargos y elecciones». Opens on the service tile (as before) or, from far away, in
## consult mode (open_consult): the same panel, asking says «hay que ir» and «Ir allí» walks there; that one does not
## close when the person moves. Only gives orders (request_title, move_to).

signal closed
signal offices_requested(actor: String)  # H10: the «Offices» button (the chart, OfficesPanel)

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var consult: bool = false
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%AskButton as Button).pressed.connect(request_ask)
	(%GoButton as Button).pressed.connect(go_there)
	(%OfficesButton as Button).pressed.connect(func() -> void: offices_requested.emit(actor))


func open_for(s: Sim, who: String) -> void:
	_open(s, who, false)


## From far away (the top bar's title): everything to read; asking needs to be there, «Ir allí» walks.
func open_consult(s: Sim, who: String) -> void:
	_open(s, who, true)


func _open(s: Sim, who: String, far: bool) -> void:
	_bind()
	sim = s
	actor = who
	consult = far
	(%Title as Label).text = SimQuery.t_("ui.town_hall.title")
	(%AskButton as Button).text = SimQuery.t_("ui.town_hall.ask")
	(%GoButton as Button).text = SimQuery.t_("ui.town_hall.go")
	(%OfficesButton as Button).text = SimQuery.t_("ui.town_hall.offices")
	(%OfficesKey as Label).text = SimQuery.t_("ui.town_hall.offices_key")
	(%ApproverTitle as Label).text = SimQuery.t_("ui.town_hall.approves")
	visible = true
	refresh(true)
	ViewConfig.info("TownHallPanel", "open (actor=%s, consult=%s)" % [who, far])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		if consult or Titles.at_town_hall(sim, actor):
			refresh()
		else:
			close()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var st := Titles.status(sim, actor)
	var fam := str(st["family"])
	var sig := str(st) + "|" + str(Reputation.of(sim.state, fam)) + "|" + str(Titles.approver(sim, actor)) + str(consult)
	if (sig == _sig or UiFeel.hold_rebuild(self)) and not force:
		return
	_sig = sig
	var f: Dictionary = sim.state.families.get(fam, {})
	var slot := %RibbonSlot as Control
	SocialKit.clear(slot)
	slot.add_child(SocialKit.ribbon(sim.state, fam, Vector2(8, 26)))
	(%CurrentLabel as Label).text = SimQuery.t_("ui.town_hall.family_rep") % [str(f.get("name", "")),
		Reputation.of(sim.state, fam)]
	(%TodayLabel as Label).text = _today_text(f)
	_fill_ladder(str(st["current"]), str(st["next"]))
	var nx := str(st["next"])
	var list := %ReqList as VBoxContainer
	SocialKit.clear(list)
	(%NextBox as Control).visible = nx != ""
	if nx == "":
		(%NextLabel as Label).text = SimQuery.t_("ui.town_hall.top")
		(%Cost as Label).text = ""
	else:
		(%NextLabel as Label).text = SimQuery.t_("ui.town_hall.next_short") % SimQuery.title_name(nx).capitalize()
		(%Cost as Label).text = SimQuery.t_("ui.town_hall.cost") % int(st["cost"])
		for r: Dictionary in st["requirements"]:
			list.add_child(_req_row(r))
		(%UnlocksLabel as Label).text = SimQuery.t_("ui.town_hall.unlocks") % unlocks_text(sim.catalog, nx, Titles.current(sim, fam))
		_fill_approver()
	var why := str(st["reason"])
	var ask := %AskButton as Button
	ask.visible = nx != ""
	ask.disabled = why != ""
	ask.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.town_hall.ask_tip") % int(st["cost"])
	SocialKit.set_reason(%Reason as Label, reason_line(st) if nx != "" else "")
	(%GoButton as Button).visible = consult and why == "not_at_town_hall"
	reset_size()


## «6 cambios hoy: +4» from the family's reputation log.
func _today_text(f: Dictionary) -> String:
	var today := Clock.day(int(sim.state.clock["minute"]))
	var n := 0
	var sum := 0
	for e: Dictionary in f.get("reputation_log", []):
		if Clock.day(int(e.get("minute", 0))) == today:
			n += 1
			sum += int(e.get("amount", 0))
	return SimQuery.t_("ui.town_hall.today") % [n, SocialKit.signed(sum)] if n > 0 else ""


func _fill_ladder(current: String, next: String) -> void:
	var box := %Ladder as HBoxContainer
	SocialKit.clear(box)
	var ladder := sim.catalog.title_ladder()
	var cur := ladder.find(current)
	for i: int in ladder.size():
		var t := str(ladder[i])
		var step := PanelContainer.new()
		step.name = t
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.theme_type_variation = &"TitleStepCurrent" if t == current else (&"TitleStepFar" if i > cur and t != next \
			else &"TitleStep")
		step.set_meta("current", t == current)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		step.add_child(v)
		var badge := TextureRect.new()
		badge.texture = UiIcons.mark("badge_title_" + t)
		badge.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		badge.custom_minimum_size = Vector2(0, 16)
		v.add_child(badge)
		var tn := SimQuery.title_name(t)
		var l := SocialKit.label(tn.substr(0, 1).to_upper() + tn.substr(1), &"GoldLabel" if t == next else \
			(&"" if i <= cur else &"DimLabel"), "Name")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # whole: the step takes its name's width (B10)
		v.add_child(l)
		var def: Dictionary = sim.catalog.titles().get(t, {})
		step.tooltip_text = SimQuery.t_("ui.town_hall.step_tip") % [tn, int(def.get("reputation", 0)), int(def.get("cost_gold", 0)),
			unlocks_text(sim.catalog, t)]
		box.add_child(step)


func _req_row(r: Dictionary) -> Control:
	var kind := str(r["kind"])
	var row := HBoxContainer.new()
	row.name = kind
	row.add_theme_constant_override("separation", 6)
	var n := SocialKit.label(SimQuery.t_("ui.town_hall.req_" + kind), &"", "Name")
	n.custom_minimum_size = Vector2(84, 0)
	row.add_child(n)
	var ok := bool(r["ok"])
	if kind == "event":
		row.add_child(SocialKit.label(SimQuery.t_("ui.town_hall.event_" + str(r.get("event", "")) if SimQuery.t_(
			"ui.town_hall.event_" + str(r.get("event", ""))) != "ui.town_hall.event_" + str(r.get("event", "")) \
			else "ui.town_hall.event_undefined"), &"PositiveLabel" if ok else &"DimLabel", "Value"))
		return row
	var bar := SocialKit.bar(float(r["have"]) / maxf(1.0, float(r["need"])), 140.0, "Bar")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var v := SocialKit.label("%d / %d" % [int(r["have"]), int(r["need"])], &"PositiveLabel" if ok else &"ReasonLabel", "Value")
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


func _fill_approver() -> void:
	var a := Titles.approver(sim, actor)
	var slot := %ApproverPortrait as Control
	SocialKit.clear(slot)
	var bar_slot := %ApproverBar as Control
	SocialKit.clear(bar_slot)
	if a.is_empty():
		(%ApproverName as Label).text = SimQuery.t_("ui.town_hall.approver_vacant")
		(%ApproverAffinity as Label).text = ""
		return
	var who := str(a["character"])
	slot.add_child(SocialKit.portrait(sim.state, who))
	(%ApproverName as Label).text = "%s, %s" % [str(sim.state.characters.get(who, {}).get("name", who)),
		SimQuery.office_name(str(a["office"]))]
	var bar := SocialKit.threshold_bar(float(a["affinity"]), 100.0, float(a["need"]), 120.0, "Affinity")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_slot.add_child(bar)
	(%ApproverAffinity as Label).text = SimQuery.t_("ui.town_hall.approver_affinity") % [int(a["affinity"]), int(a["need"])]
	(%ApproverAffinity as Label).theme_type_variation = &"PositiveLabel" if bool(a["ok"]) else &"ReasonLabel"


## The reason line next to «Pedir el título», with the figures ("Falta reputación (60/200)").
func reason_line(st: Dictionary) -> String:
	var why := str(st["reason"])
	if why == "":
		return ""
	for r: Dictionary in st["requirements"]:
		if not bool(r["ok"]) and str(Titles.REQ_REASON.get(str(r["kind"]), "")) == why and str(r["kind"]) != "event":
			return SimQuery.t_("ui.town_hall.missing_req") % [SimQuery.t_("ui.town_hall.req_" + str(r["kind"])).to_lower(),
				int(r["have"]), int(r["need"])]
	if why == "title_not_approved":
		var a := Titles.approver(sim, actor)
		if not a.is_empty():
			return SimQuery.t_("ui.town_hall.not_approved") % [SimQuery.office_name(str(a["office"])), int(a["affinity"]), int(a["need"])]
	return SimQuery.reason_text(why)


## What a title opens, as text: «2 → 4 edificios, votar, cargos medios» (from the current one if given).
static func unlocks_text(catalog: Catalog, title: String, from: String = "") -> String:
	var u: Dictionary = catalog.titles().get(title, {}).get("unlocks", {})
	var parts: PackedStringArray = []
	var mb: Variant = u.get("max_buildings", null)
	var before: Variant = catalog.titles().get(from, {}).get("unlocks", {}).get("max_buildings", null) if from != "" else null
	if mb == null:
		parts.append(SimQuery.t_("ui.town_hall.buildings_any"))
	elif before != null and int(before) != int(mb):
		parts.append(SimQuery.t_("ui.town_hall.buildings_from") % [int(before), int(mb)])
	else:
		parts.append(SimQuery.t_("ui.town_hall.buildings") % int(mb))
	if bool(u.get("vote", false)):
		parts.append(SimQuery.t_("ui.town_hall.vote"))
	var rank := str(u.get("office_rank", "none"))
	if rank != "none":
		parts.append(SimQuery.t_("ui.town_hall.offices_" + rank))
	return ", ".join(parts)


## «Pedir el título» asks first: it costs gold (titulos_y_reputacion.md §4).
func request_ask() -> void:
	var st := Titles.status(sim, actor)
	if str(st["reason"]) != "":
		return
	var cost := int(st["cost"])
	var left := Money.gold(sim.state, str(st["family"])) - cost
	SocialKit.ask(self, SimQuery.t_("ui.town_hall.ask_q") % SimQuery.title_name(str(st["next"])),
		SimQuery.t_("ui.town_hall.ask_body") % [cost, SimQuery.title_name(str(st["next"])), left],
		SimQuery.t_("ui.town_hall.ask"), _ask, "", true)


func _ask() -> void:
	if order_sink.is_valid():
		ViewConfig.info("TownHallPanel", "request_title (actor=%s)" % actor)
		order_sink.call({"type": "request_title", "actor": actor})


## «Ir allí»: walks to the town hall's service tile (leaving the building first if inside).
func go_there() -> void:
	var svc := Titles.service(sim)
	if svc.size() != 2 or not order_sink.is_valid():
		return
	if str(sim.state.characters.get(actor, {}).get("location", "")) != "":
		order_sink.call({"type": "exit_building", "actor": actor})
		order_sink.call({"type": "move_to", "actor": actor, "tile": svc, "queued": true})
	else:
		order_sink.call({"type": "move_to", "actor": actor, "tile": svc})
