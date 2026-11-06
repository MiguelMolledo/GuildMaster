class_name StaffPanel
extends PanelContainer
## Staff panel of a building (docs/ui/mecanicas/empleados.md; GDD 4.7, 4.6.4): two tabs under a common header (places
## used, the day's wages and the family's gold).
## - Staff (default when there is someone): a card per employee, a pending promotion first with a gold edge (from → to,
##   wage and speed written on Accept / Refuse); what they do now (task with its progress, arrives tomorrow, leaves
##   today, at home, idle and why); the loyalty bar with the band cuts of data/employees.json as marks, the band's word
##   and its effect written; the progress to the next rank (days and loyalty needed); the role as one button per
##   station plus Anything (set_role); Reward (bonus) and Fire (fire, asked first in the confirmation modal, with the
##   reputation lost if they were loyal). The foot: tomorrow's wages against the gold.
## - Hire (default when the staff is empty): the table of ranks from data/employees.json (wage, speed, efficiency, how
##   common, the upgrade a gated rank needs); a strip naming the upgrades that open a place when there is none; each
##   candidate with portrait, rank badge, Craft as a 10-step bar, the other stats, «Can:» with the building's recipes
##   (locked over their Craft) and Hire, which asks a second click saying the daily wage. The reason of a refusal is
##   written with the figure or the upgrade. A line says how many rows are below the scroll.
## Reads only the sim (Staff via SimQuery, the catalog, Upgrades, Upkeep); every change is an order through order_sink.
## The orders are signed by the selected person if they belong to the building's family, else by its first member.

signal closed

const TABS: Array[String] = ["staff", "hire"]
const FRAME := preload("res://game/ui/portrait_frame.tscn")
const BAR_STEPS := 10

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the orders if they are of the building's family)
var tab: String = "staff"
var _rows: Dictionary = {}   # chr -> row Control of the tab shown
var _sig: String = ""
var _bound: bool = false
var _armed: String = ""      # the candidate whose Hire waits for the second click
var _hidden: int = 0         # rows below the scroll's view


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%StaffTab as Button).pressed.connect(show_tab.bind("staff"))
	(%HireTab as Button).pressed.connect(show_tab.bind("hire"))


func setup(s: Sim, bld: String, who: String = "") -> void:
	_bind()
	sim = s
	building = bld
	preferred = who
	(%Title as Label).text = SimQuery.t_("ui.staff.title") % SimQuery.building_label(s.state, s.catalog, bld)
	(%StaffTab as Button).text = SimQuery.t_("ui.staff.tab.staff")
	(%HireTab as Button).text = SimQuery.t_("ui.staff.tab.hire")
	(%Foot as Label).text = ""
	refresh(true)


func set_actor(who: String) -> void:
	preferred = who


## Who signs this panel's orders ("" if the building has no family with people).
func actor() -> String:
	if sim == null:
		return ""
	return SimQuery.building_actor(sim.state, building, preferred)


## `start_tab` "staff" / "hire"; "" = Hire when the staff is empty, else the last one shown.
func open(start_tab: String = "") -> void:
	if start_tab in TABS:
		tab = start_tab
	elif sim != null and SimQuery.employees(sim, building).is_empty():
		tab = "hire"
	_armed = ""
	visible = true
	refresh(true)
	ViewConfig.info("StaffPanel", "open (building=%s, tab=%s, actor=%s)" % [building, tab, actor()])


func close() -> void:
	if visible:
		visible = false
		_armed = ""
		closed.emit()


func show_tab(t: String) -> void:
	if not t in TABS:
		return
	tab = t
	_armed = ""
	ViewConfig.info("StaffPanel", "tab %s (building=%s)" % [t, building])
	refresh(true)


func tab_button(t: String) -> Button:
	return get_node("%StaffTab" if t == "staff" else "%HireTab")


func _process(_delta: float) -> void:
	if visible:
		refresh()
		_refresh_more()


func _family() -> String:
	return SimQuery.building_family(sim.state, building)


func _gold() -> int:
	return Money.gold(sim.state, _family())


func _today() -> int:
	return Clock.day(int(sim.state.clock["minute"]))


func _night() -> bool:
	return Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) == "night"


## Rebuilds the list when what it shows changed (not every frame: the buttons must stay pressable).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	for t: String in TABS:
		tab_button(t).set_pressed_no_signal(t == tab)
	var data: Array = SimQuery.employees(sim, building) if tab == "staff" else SimQuery.candidates(sim, actor(), building)
	var sig := tab + JSON.stringify(data) + str(_today()) + "|" + str(_gold()) + "|" + str(_night()) \
		+ str(sim.state.buildings.get(building, {}).get("upgrades", []))
	if not force and (sig == _sig or UiFeel.hold_rebuild(self)):
		return
	_sig = sig
	_refresh_head()
	(%Ranks as Control).visible = tab == "hire"
	if tab == "hire":
		_fill_ranks()
	_refresh_strip()
	var list := %List as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if data.is_empty():
		var l := _label(SimQuery.t_("ui.staff.none" if tab == "staff" else "ui.staff.no_candidates"), &"DimLabel")
		l.name = "Empty"
		list.add_child(l)
	if tab == "staff":   # a pending promotion first
		data = data.duplicate()
		data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := bool(a.get("promotion_offered", false))
			if pa != bool(b.get("promotion_offered", false)):
				return pa
			return str(a["character"]) < str(b["character"]))
	for d: Dictionary in data:
		var row := _employee_row(d) if tab == "staff" else _candidate_row(d)
		row.name = str(d["character"])
		list.add_child(row)
		_rows[str(d["character"])] = row
	_refresh_foot()


## «Places 1/2 · 27/day · 65 gold»: the places used, the wages of the staff a day and the family's gold.
func _refresh_head() -> void:
	var used := SimQuery.slots(sim.state, building) - SimQuery.free_slots(sim.state, building)
	(%SlotsLabel as Label).text = SimQuery.t_("ui.staff.head") % [used, SimQuery.slots(sim.state, building),
		day_wages(), _gold()]


## The wages of the building's employees a day.
func day_wages() -> int:
	var total := 0
	for c: Variant in Staff.employees_of(sim.state, building):
		total += Staff.wage(sim, str(c))
	return total


func _refresh_foot() -> void:
	var foot := %Foot as Label
	if tab == "hire":
		foot.text = SimQuery.t_("ui.staff.hire_foot")
	else:
		var due := Upkeep.due_next_dawn(sim, _family())
		foot.text = SimQuery.t_("ui.staff.wages_tomorrow") % [int(due["wages"]), _gold()]
		foot.theme_type_variation = &"WarningLabel" if int(due["wages"]) > _gold() else &"DimLabel"


## The strip on top: no place to hire (with the upgrades that open one) or the night.
func _refresh_strip() -> void:
	var text := ""
	if tab == "hire" and SimQuery.free_slots(sim.state, building) <= 0:
		var ups := slot_upgrades()
		var names: PackedStringArray = []
		for u: String in ups:
			names.append(SimQuery.t_("ui.staff.slot_upgrade") % [SimQuery.upgrade_name(sim.catalog, u),
				int(_effect_amount(u, "max_employees"))])
		text = SimQuery.t_("ui.staff.no_slot_strip") % SimQuery.t_("ui.staff.or").join(names) if not names.is_empty() \
			else SimQuery.t_("ui.staff.no_slot_left")
	elif tab == "staff" and _night() and not SimQuery.employees(sim, building).is_empty():
		var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)]
		var dawn := int(starts["dawn"])
		text = SimQuery.t_("ui.staff.night_strip") % ("%02d:%02d" % [dawn / 60, dawn % 60])
	(%Strip as Control).visible = text != ""
	(%StripLabel as Label).text = text


## The building's upgrades not built yet that add employee places (max_employees), in tree order.
func slot_upgrades() -> Array:
	var out: Array = []
	for id: String in sim.catalog.upgrade_tree(Upgrades.tree_of(sim, building)):
		if _effect_amount(id, "max_employees") > 0.0 and not Upgrades.has(sim.state, building, id):
			out.append(id)
	return out


func _effect_amount(upgrade: String, kind: String) -> float:
	var n := 0.0
	for e: Dictionary in sim.catalog.upgrade(upgrade).get("effects", []):
		if str(e.get("kind", "")) == kind:
			n += float(e.get("amount", 0.0))
	return n


## The upgrade of the building's tree that allows `rank` ("" if none gates it).
func rank_upgrade(rank: String) -> String:
	for id: String in sim.catalog.upgrade_tree(Upgrades.tree_of(sim, building)):
		for e: Dictionary in sim.catalog.upgrade(id).get("effects", []):
			if str(e.get("kind", "")) == "allow_rank" and str(e.get("rank", "")) == rank:
				return id
	return ""


## The ranks' table of data/employees.json: badge, name, wage a day, speed, efficiency, and how common (or the upgrade
## a gated rank needs here).
func _fill_ranks() -> void:
	var box := %RankRows as VBoxContainer
	_clear(box)
	(%RanksLabel as Label).text = SimQuery.t_("ui.staff.ranks").to_upper()
	var order: Array = sim.catalog.employees.get("rank_order", [])
	for i: int in order.size():
		var rk := str(order[i])
		var def := sim.catalog.rank(rk)
		var row := HBoxContainer.new()
		row.name = "Rank_" + rk
		row.add_theme_constant_override("separation", 6)
		row.add_child(_mark(i + 1))
		row.add_child(_fixed(SimQuery.rank_name(sim.catalog, rk).to_upper(), 74, &"SmallLabel"))
		row.add_child(_fixed(SimQuery.t_("ui.staff.per_day") % int(def.get("wage", 0)), 52, &"GoldLabel", true))
		row.add_child(_fixed("×%s" % _num(float(def.get("speed", 1.0))), 26, &"", true))
		row.add_child(_fixed("%d %%" % roundi(float(def.get("efficiency", 1.0)) * 100.0), 40, &"", true))
		var gate := rank_upgrade(rk)
		if gate != "" and not Upgrades.rank_ok(sim, building, rk):
			var lock := TextureRect.new()
			lock.texture = UiIcons.ui("icon_locked")
			lock.custom_minimum_size = Vector2(16, 16)
			lock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			lock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(lock)
			var l := _label(SimQuery.upgrade_name(sim.catalog, gate), &"ReasonLabel")
			l.name = "Gate"
			l.clip_text = true
			row.add_child(l)
		else:
			var l := _label(SimQuery.t_("ui.staff.avail." + str(def.get("availability", "medium"))), &"DimLabel")
			l.name = "Availability"
			row.add_child(l)
		row.tooltip_text = SimQuery.t_("ui.staff.rank_tip") % [SimQuery.rank_name(sim.catalog, rk),
			int(def.get("wage", 0)), _num(float(def.get("speed", 1.0))), roundi(float(def.get("efficiency", 1.0)) * 100.0)]
		box.add_child(row)


## «↓ 3 more»: the rows below the scroll's view.
func _refresh_more() -> void:
	var sc := %Scroll as ScrollContainer
	var bottom := float(sc.scroll_vertical) + sc.size.y
	var n := 0
	for c: Node in (%List as VBoxContainer).get_children():
		if c is Control and (c as Control).position.y + 6.0 > bottom:
			n += 1
	_hidden = n
	var more := %More as Label
	more.visible = n > 0
	if n > 0:
		more.text = SimQuery.t_("ui.staff.more_hire" if tab == "hire" else "ui.staff.more_staff") % n


## The rows below the scroll's view (the line «↓ N more»; tests).
func hidden_below() -> int:
	_refresh_more()
	return _hidden


## The row of `chr` in the tab shown (null if not there): tests press its buttons.
func row_of(chr: String) -> Control:
	return _rows.get(chr, null)


# --- pieces ----------------------------------------------------------------------------------------------------------

func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _fixed(text: String, width: int, variation: StringName = &"", right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.clip_text = width > 0
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _num(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, roundf(f)) else String.num(f, 1).replace(".", ",")


func _button(id: String, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _mark(n: int) -> TextureRect:
	var r := TextureRect.new()
	r.name = "RankMark"
	r.texture = UiIcons.mark("rank_%d" % clampi(n, 1, 3))
	r.custom_minimum_size = Vector2(12, 12)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


func _rank_n(rank: String) -> int:
	return (sim.catalog.employees.get("rank_order", []) as Array).find(rank) + 1


func _portrait(chr: String) -> Control:
	var f := FRAME.instantiate() as PortraitFrame
	f.name = "Portrait"
	f.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	f.show_character(sim.state, chr, {"controlled": true})
	return f


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


## A bar of `steps` cells, `value` of them full (a stat 0-10).
func _steps_bar(value: int, steps: int = BAR_STEPS) -> Control:
	var bar := Control.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(steps * 5, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var on := Color.html(StationMenu._token("positivo"))
	var off := Color.html(StationMenu._token("hueco"))
	bar.draw.connect(func() -> void:
		for i: int in steps:
			bar.draw_rect(Rect2(i * 5, 0, 4, 8), on if i < value else off))
	return bar


## The loyalty bar: 0-100 with a mark at each band cut (data/employees.json bands), filled in the band's colour.
func _loyalty_bar(loyalty: int) -> Control:
	var bar := Control.new()
	bar.name = "LoyaltyBar"
	bar.custom_minimum_size = Vector2(120, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := Color.html(StationMenu._token(band_color(loyalty)))
	var cuts := band_cuts()
	var mx := float(sim.catalog.employees.get("loyalty", {}).get("max", 100))
	bar.draw.connect(func() -> void:
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 1, w, 6), Color(0.12, 0.09, 0.07))
		bar.draw_rect(Rect2(0, 1, w * clampf(loyalty / mx, 0.0, 1.0), 6), fill)
		for c: int in cuts:
			var x := roundf(w * c / mx)
			bar.draw_rect(Rect2(x, 0, 1, 8), Color(0.93, 0.89, 0.82)))
	return bar


## The band cuts drawn as marks: each band's minimum above 0 (20, 40, 70).
func band_cuts() -> Array:
	var out: Array = []
	for b: Dictionary in sim.catalog.employees.get("bands", []):
		if int(b["min"]) > 0:
			out.append(int(b["min"]))
	out.sort()
	return out


func band_color(loyalty: int) -> String:
	var b := Staff.band(sim, loyalty)
	if float(b.get("quit_chance", 0.0)) > 0.0 or float(b.get("theft_chance", 0.0)) > 0.0:
		return "negativo"
	if float(b.get("efficiency_mult", 1.0)) < 1.0:
		return "aviso"
	return "positivo"


## What the band of `loyalty` does, written: «−20 % efficiency and rumours (−1 rep.)», «May leave without notice (5 %
## a day)», «May steal and run (3 % a day) · Security halves it».
func band_effect(loyalty: int) -> String:
	var b := Staff.band(sim, loyalty)
	var parts: PackedStringArray = []
	var eff := float(b.get("efficiency_mult", 1.0))
	var rumor := int(b.get("rumor_reputation", 0))
	if eff < 1.0 and rumor != 0:
		parts.append(SimQuery.t_("ui.staff.effect.eff_rumor") % [roundi((1.0 - eff) * 100.0), rumor])
	elif eff < 1.0:
		parts.append(SimQuery.t_("ui.staff.effect.eff") % roundi((1.0 - eff) * 100.0))
	if float(b.get("quit_chance", 0.0)) > 0.0:
		parts.append(SimQuery.t_("ui.staff.effect.quit") % roundi(float(b["quit_chance"]) * 100.0))
	if float(b.get("theft_chance", 0.0)) > 0.0:
		var t := SimQuery.t_("ui.staff.effect.theft") % roundi(float(b["theft_chance"]) * 100.0)
		if not Staff.has_security(sim, building):
			t += " · " + SimQuery.t_("ui.staff.effect.security") % int(sim.catalog.employees.get("theft", {}).get("security_divisor", 2))
		parts.append(t)
	if parts.is_empty():
		return SimQuery.t_("ui.staff.effect.none")
	return " · ".join(parts)


# --- staff -----------------------------------------------------------------------------------------------------------

## One employee's card (see the class doc).
func _employee_row(d: Dictionary) -> Control:
	var chr := str(d["character"])
	var cat := sim.catalog
	var promo := bool(d.get("promotion_offered", false))
	var box := PanelContainer.new()
	box.theme_type_variation = &"SelectedRow" if promo else &"RowPanel"
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 1)
	box.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	card.add_child(h)
	h.add_child(_portrait(chr))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var rk := str(d["rank"])
	var nxt := str(cat.rank(rk).get("next", ""))
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 4)
	var name_l := _fixed(str(d["name"]), 0, &"BoldLabel")
	name_l.clip_text = false
	top.add_child(name_l)
	top.add_child(_mark(_rank_n(rk)))
	var rank_l := _label(SimQuery.rank_name(cat, rk), &"SmallLabel")
	rank_l.name = "Rank"
	rank_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	rank_l.clip_text = true
	rank_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if promo and nxt != "":
		rank_l.text += " → " + SimQuery.rank_name(cat, nxt)
	top.add_child(rank_l)
	top.add_child(_fixed(SimQuery.t_("ui.staff.per_day") % int(d["wage"]), 0, &"GoldLabel"))
	v.add_child(top)
	if promo and nxt != "":
		card.add_child(_promotion(chr, rk, nxt))
	if int(d.get("unpaid_days", 0)) > 0:
		var grace := int(cat.employees.get("wages", {}).get("grace_days", 1))
		var u := _label(SimQuery.t_("ui.staff.unpaid_strip") % [int(d["unpaid_days"]),
			int(cat.employees.get("loyalty", {}).get("wage_unpaid", -5)),
			int(cat.employees.get("wages", {}).get("unpaid_reputation", -2))] if int(d["unpaid_days"]) <= grace \
			else SimQuery.t_("ui.staff.unpaid_late") % [int(d["unpaid_days"]),
			int(cat.employees.get("loyalty", {}).get("wage_unpaid", -5)),
			int(cat.employees.get("wages", {}).get("unpaid_reputation", -2))], &"ReasonLabel")
		u.name = "Unpaid"
		card.add_child(u)
	var doing := HBoxContainer.new()
	doing.name = "Doing"
	doing.add_theme_constant_override("separation", 4)
	var dv := doing_view(d)
	var ic := TextureRect.new()
	ic.texture = UiIcons.ui(str(dv["icon"]))
	ic.custom_minimum_size = Vector2(16, 16)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	doing.add_child(ic)
	var dl := _label(str(dv["text"]), &"DimLabel" if str(dv["icon"]) in ["icon_moon", "icon_pending"] else &"")
	dl.name = "Text"
	doing.add_child(dl)
	v.add_child(doing)
	var loy := int(d["loyalty"])
	var lrow := HBoxContainer.new()
	lrow.name = "Loyalty"
	lrow.add_theme_constant_override("separation", 6)
	lrow.add_child(_fixed(SimQuery.t_("ui.staff.loyalty_n") % loy, 0))
	lrow.add_child(_loyalty_bar(loy))
	var word := _fixed(SimQuery.band_name(str(d["band"])), 0, &"BoldLabel")
	word.name = "Band"
	word.add_theme_color_override("font_color", Color.html(StationMenu._token(band_color(loy))))
	lrow.add_child(word)
	lrow.tooltip_text = _bands_tip()
	card.add_child(lrow)
	var eff := _label(band_effect(loy), &"SmallLabel")
	eff.name = "Effect"
	eff.add_theme_color_override("font_color", Color.html(StationMenu._token(band_color(loy))))
	card.add_child(eff)
	if nxt != "" and not promo and int(d.get("end_day", -1)) < 0:
		var nx := _label(next_rank_text(d), &"SmallLabel")
		nx.name = "Next"
		var ready := int(d.get("rank_days", 0)) >= int(cat.rank(rk).get("promote_after_days", 0)) \
			and loy >= int(cat.rank(rk).get("promote_min_loyalty", 0))
		nx.theme_type_variation = &"PositiveLabel" if ready else &"DimLabel"
		card.add_child(nx)
	var leaving := int(d.get("end_day", -1)) >= 0
	if not leaving:
		card.add_child(_roles(chr, str(d["role"])))
	var acts := HBoxContainer.new()
	acts.name = "Acts"
	var gold := int(cat.employees.get("bonus_gold", 0))
	var bonus_b := _button("Bonus", SimQuery.t_("ui.staff.reward") % [gold, int(cat.employees.get("loyalty", {}).get("bonus", 0))],
		SimQuery.t_("ui.staff.bonus_tip"), bonus.bind(chr))
	bonus_b.disabled = leaving or _gold() < gold
	if not leaving and _gold() < gold:
		bonus_b.tooltip_text = SimQuery.t_("ui.staff.need_gold") % gold
	acts.add_child(bonus_b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(sp)
	var fire_b := _button("Fire", SimQuery.t_("ui.staff.fire"), SimQuery.t_("ui.staff.fire_tip"), fire.bind(chr))
	fire_b.disabled = leaving
	acts.add_child(fire_b)
	card.add_child(acts)
	return box


## The pending promotion: wage and speed from → to, and Accept / Refuse with the loyalty each gives.
func _promotion(chr: String, rk: String, nxt: String) -> Control:
	var cat := sim.catalog
	var p := VBoxContainer.new()
	p.name = "Promotion"
	p.add_theme_constant_override("separation", 1)
	var a := cat.rank(rk)
	var b := cat.rank(nxt)
	p.add_child(_label(SimQuery.t_("ui.staff.promotion_line") % [SimQuery.rank_name(cat, nxt), int(a.get("wage", 0)),
		int(b.get("wage", 0)), _num(float(a.get("speed", 1.0))), _num(float(b.get("speed", 1.0)))], &"GoldLabel"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var loy: Dictionary = cat.employees.get("loyalty", {})
	var acc := _button("Accept", SimQuery.t_("ui.staff.accept_n") % int(loy.get("promotion_accepted", 0)),
		SimQuery.t_("ui.staff.accept_tip"), promote.bind(chr, true))
	acc.theme_type_variation = &"PrimaryButton"
	row.add_child(acc)
	row.add_child(_button("Refuse", SimQuery.t_("ui.staff.refuse_n") % int(loy.get("promotion_refused", 0)),
		SimQuery.t_("ui.staff.refuse_tip"), promote.bind(chr, false)))
	p.add_child(row)
	return p


## «Promotion to master: 3/16 days · loyalty ≥ 71 (not yet)», plus the upgrade the next rank needs here.
func next_rank_text(d: Dictionary) -> String:
	var cat := sim.catalog
	var rk := str(d["rank"])
	var def := cat.rank(rk)
	var nxt := str(def.get("next", ""))
	var need := int(def.get("promote_min_loyalty", 0))
	var s := SimQuery.t_("ui.staff.next_rank") % [SimQuery.rank_name(cat, nxt), mini(int(d.get("rank_days", 0)),
		int(def.get("promote_after_days", 0))), int(def.get("promote_after_days", 0)), need,
		SimQuery.t_("ui.staff.met" if int(d["loyalty"]) >= need else "ui.staff.not_met")]
	if not Upgrades.rank_ok(sim, building, nxt):
		s += " · " + SimQuery.t_("ui.staff.needs") % SimQuery.upgrade_name(cat, rank_upgrade(nxt))
	return s


func _bands_tip() -> String:
	var lines: PackedStringArray = []
	for b: Dictionary in sim.catalog.employees.get("bands", []):
		lines.append("%d-%d %s: %s" % [int(b["min"]), int(b["max"]), SimQuery.band_name(str(b["id"])),
			band_effect(int(b["min"]))])
	return "\n".join(lines)


## The role selector: a button per station of the building and Anything, the current one pressed.
func _roles(chr: String, current: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Role"
	row.add_theme_constant_override("separation", 2)
	row.add_child(_fixed(SimQuery.t_("ui.staff.role"), 0, &"SmallLabel"))
	var roles := SimQuery.building_roles(sim.state, sim.catalog, building)
	var any := str(sim.catalog.employees.get("default_role", "any"))
	var ordered: Array = roles.filter(func(r: Variant) -> bool: return str(r) != any)
	ordered.append(any)
	if not current in ordered:
		ordered.append(current)
	for r: Variant in ordered:
		var id := str(r)
		var b := _button(id, SimQuery.role_name(sim.catalog, id), SimQuery.t_("ui.staff.role_any_tip") if id == any \
			else SimQuery.t_("ui.staff.role_only_tip") % SimQuery.role_name(sim.catalog, id).to_lower(), Callable())
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.set_pressed_no_signal(id == current)
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(true)
			if id != current:
				set_role(chr, id))
		row.add_child(b)
	return row


## What an employee is doing now: {text, icon}. Task with its progress, arrives on day N, leaves today, at home (night),
## idle and why (the queue's stall reason), on the way.
func doing_view(d: Dictionary) -> Dictionary:
	var today := _today()
	if int(d.get("end_day", -1)) >= 0:
		return {"text": SimQuery.t_("ui.staff.leaving"), "icon": "icon_pending"}
	if not bool(d.get("active", false)) and int(d.get("start_day", 0)) > today:
		var start := int(d["start_day"])
		return {"text": SimQuery.t_("ui.staff.arrives_tomorrow" if start == today + 1 else "ui.staff.starts") % (start + 1),
			"icon": "icon_pending"}
	var task: Dictionary = d.get("task", {})
	if not task.is_empty():
		var zone := str(task.get("zone", ""))
		var job := Production.job_view(sim, building, zone)
		var pct := roundi(float(job.get("progress", 0.0)) * 100.0)
		return {"text": SimQuery.t_("ui.staff.task_now") % [SimQuery.zone_name(zone),
			SimQuery.recipe_name(sim.catalog, str(task.get("recipe", ""))), pct], "icon": "icon_working"}
	var r := str(d.get("routine", ""))
	if r == "home":
		return {"text": SimQuery.t_("ui.staff.home_night" if _night() else "ui.staff.routine.home"), "icon": "icon_moon"}
	if r == "at_work":
		var stalled := str(SimQuery.queue_view(sim, building).get("stalled", ""))
		if stalled != "":
			return {"text": SimQuery.t_("ui.staff.idle_why") % SimQuery.reason_text(stalled), "icon": "icon_idle"}
		return {"text": SimQuery.t_("ui.staff.routine.at_work"), "icon": "icon_idle"}
	var key := "ui.staff.routine." + r
	var s := SimQuery.t_(key)
	return {"text": r if s == key else s, "icon": "icon_in_progress"}


# --- hire ------------------------------------------------------------------------------------------------------------

## One candidate: portrait, name, rank badge, wage and Hire; Craft as a bar with the other stats; «Can:» with the
## building's recipes (locked over their Craft); the reason if they cannot be hired.
func _candidate_row(d: Dictionary) -> Control:
	var chr := str(d["character"])
	var cat := sim.catalog
	var box := PanelContainer.new()
	box.theme_type_variation = &"SelectedRow" if chr == _armed else &"RowPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	h.add_child(_portrait(chr))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 4)
	var nm := _fixed(str(d["name"]), 0, &"BoldLabel")
	nm.clip_text = false
	top.add_child(nm)
	top.add_child(_mark(_rank_n(str(d["rank"]))))
	var rank_l := _label(SimQuery.rank_name(cat, str(d["rank"])), &"SmallLabel")
	rank_l.name = "Rank"
	rank_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	rank_l.clip_text = true
	rank_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(rank_l)
	top.add_child(_fixed(SimQuery.t_("ui.staff.per_day") % int(d["wage"]), 0, &"GoldLabel"))
	var ok := str(d.get("status", "")) == "ok"
	var hb := _button("Hire", SimQuery.t_("ui.staff.hire_ask") % int(d["wage"]) if chr == _armed else SimQuery.t_("ui.staff.hire"),
		SimQuery.t_("ui.staff.hire_tip"), _on_hire.bind(chr))
	hb.theme_type_variation = &"PrimaryButton" if chr == _armed else &""
	hb.disabled = not ok
	top.add_child(hb)
	v.add_child(top)
	var st: Dictionary = d.get("stats", {})
	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 4)
	stats.add_child(_fixed("%s %d" % [SimQuery.t_("stat.craft"), int(st.get("craft", 0))], 0, &"SmallLabel"))
	stats.add_child(_steps_bar(int(st.get("craft", 0))))
	stats.add_child(_label("%s %d · %s %d" % [SimQuery.t_("stat.charisma"), int(st.get("charisma", 0)),
		SimQuery.t_("ui.staff.constitution_short"), int(st.get("constitution", 0))], &"SmallLabel"))
	v.add_child(stats)
	var can := HBoxContainer.new()
	can.name = "Can"
	can.add_theme_constant_override("separation", 2)
	can.add_child(_fixed(SimQuery.t_("ui.staff.can"), 0, &"SmallLabel"))
	var cm := can_make(int(st.get("craft", 0)))
	for rid: String in cm:
		can.add_child(_recipe_icon(rid, bool(cm[rid])))
	v.add_child(can)
	if not ok:
		var why := _label(reason_of(d), &"ReasonLabel")
		why.name = "Reason"
		v.add_child(why)
		hb.tooltip_text = why.text
	return box


## The building's recipes and whether a Craft of `craft` reaches each (min_craft): {recipe: bool}, in station order.
func can_make(craft: int) -> Dictionary:
	var out := {}
	for rid: Variant in SimQuery.building_recipes(sim.state, sim.catalog, building):
		out[str(rid)] = craft >= int(sim.catalog.recipes()[str(rid)].get("min_craft", 0))
	return out


func _recipe_icon(rid: String, ok: bool) -> Control:
	var r: Dictionary = sim.catalog.recipes()[rid]
	var holder := Control.new()
	holder.name = "Can_" + rid
	holder.custom_minimum_size = Vector2(16, 16)
	holder.set_meta("locked", not ok)
	var item := str(r.get("output", {}).get("item", ""))
	var ic := UiIcons.item_rect(item)
	if ic != null:
		if not ok:
			ic.modulate = Color(1, 1, 1, 0.35)
		holder.add_child(ic)
	if not ok:
		var lock := TextureRect.new()
		lock.name = "Lock"
		lock.texture = UiIcons.ui("icon_locked")
		lock.custom_minimum_size = Vector2(16, 16)
		lock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		lock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lock)
	holder.tooltip_text = SimQuery.recipe_name(sim.catalog, rid) + (" · " + SimQuery.t_("ui.staff.min_craft") % int(r.get("min_craft", 0)) if not ok else "")
	return holder


## Why a candidate cannot be hired, with the figure or the upgrade: «No place (2/2) → Apprentice dormitory +1», «You need
## 20 gold (1 day of wages)», «Stole from you: not back until day 17», «Master: needs Master's workshop».
func reason_of(d: Dictionary) -> String:
	var status := str(d.get("status", ""))
	match status:
		"no_slot":
			var ups := slot_upgrades()
			var s := SimQuery.slots(sim.state, building)
			if ups.is_empty():
				return SimQuery.t_("ui.staff.why.no_slot_none") % [s, s]
			return SimQuery.t_("ui.staff.why.no_slot") % [s, s, SimQuery.upgrade_name(sim.catalog, str(ups[0])),
				int(_effect_amount(str(ups[0]), "max_employees"))]
		"not_enough_gold":
			return SimQuery.t_("ui.staff.why.gold") % int(d["wage"])
		"banned":
			var ch: Dictionary = sim.state.characters.get(str(d["character"]), {})
			var until := int((ch.get("hire_bans", {}) as Dictionary).get(_family(), _today()))
			return SimQuery.t_("ui.staff.why.banned") % (until + 2)
		"needs_upgrade":
			return SimQuery.t_("ui.staff.why.rank") % [SimQuery.rank_name(sim.catalog, str(d["rank"])),
				SimQuery.upgrade_name(sim.catalog, rank_upgrade(str(d["rank"])))]
	return SimQuery.reason_text(status)


## Hire asks a second click that says the daily wage (an inline confirmation: the wage is paid every dawn).
func _on_hire(chr: String) -> void:
	if _armed != chr:
		_armed = chr
		ViewConfig.info("StaffPanel", "hire armed (candidate=%s)" % chr)
		refresh(true)
		return
	_armed = ""
	hire(chr)


## Whether Hire of `chr` waits for its second click.
func armed() -> String:
	return _armed


# --- orders ----------------------------------------------------------------------------------------------------------

func hire(chr: String) -> void:
	_give({"type": "hire", "actor": actor(), "building": building, "candidate": chr})


## Fire asks first in the confirmation modal (fire_spec); without the HUD's modal (tests) it gives the order.
func fire(chr: String) -> void:
	var o := {"type": "fire", "actor": actor(), "employee": chr}
	if is_inside_tree() and ConfirmModal.ask_in(get_tree(), fire_spec(chr), func() -> void: _give(o)):
		return
	_give(o)


## The confirmation of firing `chr`: when they leave, and the reputation lost if their loyalty is over the line.
func fire_spec(chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	var job: Dictionary = ch.get("job", {}) if ch.get("job") is Dictionary else {}
	var nm := str(ch.get("name", chr))
	var body := ""
	if int(job.get("start_day", 0)) > _today():
		body = SimQuery.t_("ui.staff.fire_cancel") % nm
	else:
		body = SimQuery.t_("ui.staff.fire_body") % nm
	var f: Dictionary = sim.catalog.employees.get("fire", {})
	var loyal := int(job.get("loyalty", 0)) > int(f.get("reputation_loyalty_over", 70))
	if loyal:
		body += "\n" + SimQuery.t_("ui.staff.fire_loyal") % int(f.get("reputation", -2))
	return {"title": SimQuery.t_("ui.staff.fire_title") % nm, "body": body, "action": SimQuery.t_("ui.staff.fire"),
		"irreversible": loyal}


func bonus(chr: String) -> void:
	_give({"type": "bonus", "actor": actor(), "employee": chr})


func promote(chr: String, accept: bool) -> void:
	_give({"type": "promote", "actor": actor(), "employee": chr, "accept": accept})


func set_role(chr: String, role: String) -> void:
	_give({"type": "set_role", "actor": actor(), "employee": chr, "role": role})


func _give(o: Dictionary) -> void:
	ViewConfig.info("StaffPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""  # show the effect as soon as the sim has it
