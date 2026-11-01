class_name StaffPanel
extends PanelContainer
## Staff panel of a building (H4, GDD 4.7 and 4.6.4 "Empleados"): two tabs.
## - Staff: each employee with rank, role (a selector -> set_role), loyalty and its band, wage and what they are doing
##   (routine, task, starts / leaves on day...), Bonus (bonus) and Fire (fire); a pending promotion shows Accept /
##   Refuse (promote accept true / false).
## - Hire: the candidates (unemployed townsfolk) with name, rank, Craft / Charisma / Constitution and wage; Hire
##   (hire), disabled with the reason when the sim says no (Staff.candidates status).
## Reads only SimQuery (Staff.candidates / Staff.employees); every change is an order through order_sink. The orders
## are signed by the selected person if they belong to the building's family, else by its first member.

signal closed

const TABS: Array[String] = ["staff", "hire"]

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var preferred: String = ""   # the person selected (signs the orders if they are of the building's family)
var tab: String = "staff"
var _rows: Dictionary = {}   # chr -> row Control of the tab shown
var _sig: String = ""
var _bound: bool = false


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
	refresh(true)


func set_actor(who: String) -> void:
	preferred = who


## Who signs this panel's orders ("" if the building has no family with people).
func actor() -> String:
	if sim == null:
		return ""
	return SimQuery.building_actor(sim.state, building, preferred)


func open(start_tab: String = "") -> void:
	if start_tab in TABS:
		tab = start_tab
	visible = true
	refresh(true)
	ViewConfig.info("StaffPanel", "open (building=%s, tab=%s, actor=%s)" % [building, tab, actor()])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func show_tab(t: String) -> void:
	if not t in TABS:
		return
	tab = t
	ViewConfig.info("StaffPanel", "tab %s (building=%s)" % [t, building])
	refresh(true)


func tab_button(t: String) -> Button:
	return get_node("%StaffTab" if t == "staff" else "%HireTab")


func _process(_delta: float) -> void:
	if visible:
		refresh()


## Rebuilds the list when what it shows changed (not every frame: the buttons must stay pressable).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	for t: String in TABS:
		tab_button(t).set_pressed_no_signal(t == tab)
	var data: Array = SimQuery.employees(sim, building) if tab == "staff" else SimQuery.candidates(sim, actor(), building)
	var sig := tab + JSON.stringify(data) + str(Clock.day(int(sim.state.clock["minute"])))
	if not force and sig == _sig:
		return
	if not force and _menu_open():
		return  # a role selector is open: wait until it closes
	_sig = sig
	var used := SimQuery.slots(sim.state, building) - SimQuery.free_slots(sim.state, building)
	(%SlotsLabel as Label).text = SimQuery.t_("ui.staff.slots") % [used, SimQuery.slots(sim.state, building)]
	var list := %List as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if data.is_empty():
		list.add_child(_label(SimQuery.t_("ui.staff.none" if tab == "staff" else "ui.staff.no_candidates"),
			Color(1, 1, 1, 0.6)))
		return
	for d: Dictionary in data:
		var row := _employee_row(d) if tab == "staff" else _candidate_row(d)
		row.name = str(d["character"])
		list.add_child(row)
		_rows[str(d["character"])] = row


func _menu_open() -> bool:
	for id: String in _rows:
		var ob := (_rows[id] as Node).find_child("Role", true, false) as OptionButton
		if ob != null and ob.get_popup().visible:
			return true
	return false


## The row of `chr` in the tab shown (null if not there): tests press its buttons.
func row_of(chr: String) -> Control:
	return _rows.get(chr, null)


func _label(text: String, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


func _button(id: String, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _box() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Panel"  # the row look of the greybox theme
	return p


## One employee: name and rank with the role selector; loyalty, wage, what they do; Bonus / Fire; the promotion.
func _employee_row(d: Dictionary) -> Control:
	var chr := str(d["character"])
	var cat := sim.catalog
	var box := _box()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(_label("%s · %s" % [str(d["name"]), SimQuery.rank_name(cat, str(d["rank"]))],
		Color(0.95, 0.85, 0.6)))
	var ob := OptionButton.new()
	ob.name = "Role"
	ob.focus_mode = Control.FOCUS_NONE
	ob.tooltip_text = SimQuery.t_("ui.staff.role_tip")
	var roles := SimQuery.building_roles(sim.state, cat, building)
	for i: int in roles.size():
		ob.add_item(SimQuery.role_name(cat, str(roles[i])), i)
		ob.set_item_metadata(i, str(roles[i]))
	var cur := roles.find(str(d["role"]))
	if cur < 0:
		ob.add_item(SimQuery.role_name(cat, str(d["role"])), roles.size())
		ob.set_item_metadata(roles.size(), str(d["role"]))
		cur = roles.size()
	ob.select(cur)
	ob.item_selected.connect(func(i: int) -> void: set_role(chr, str(ob.get_item_metadata(i))))
	top.add_child(ob)
	v.add_child(top)
	var band := SimQuery.band_name(str(d["band"]))
	v.add_child(_label(SimQuery.t_("ui.staff.loyalty_line") % [int(d["loyalty"]), band, int(d["wage"])]))
	v.add_child(_label(_doing(d), Color(0.85, 0.85, 0.75)))
	if int(d.get("unpaid_days", 0)) > 0:
		v.add_child(_label(SimQuery.t_("ui.staff.unpaid") % int(d["unpaid_days"]), Color(1.0, 0.55, 0.45)))
	if bool(d.get("promotion_offered", false)):
		var nxt := str(cat.rank(str(d["rank"])).get("next", ""))
		var p := HBoxContainer.new()
		p.name = "Promotion"
		p.add_child(_label(SimQuery.t_("ui.staff.promotion") % [SimQuery.rank_name(cat, nxt),
			int(cat.rank(nxt).get("wage", 0))], Color(0.95, 0.85, 0.35)))
		p.add_child(_button("Accept", SimQuery.t_("ui.staff.accept"), SimQuery.t_("ui.staff.accept_tip"),
			promote.bind(chr, true)))
		p.add_child(_button("Refuse", SimQuery.t_("ui.staff.refuse"), SimQuery.t_("ui.staff.refuse_tip"),
			promote.bind(chr, false)))
		v.add_child(p)
	var acts := HBoxContainer.new()
	acts.alignment = BoxContainer.ALIGNMENT_END
	var bonus_b := _button("Bonus", SimQuery.t_("ui.staff.bonus") % int(cat.employees.get("bonus_gold", 0)),
		SimQuery.t_("ui.staff.bonus_tip"), bonus.bind(chr))
	var leaving := int(d.get("end_day", -1)) >= 0
	bonus_b.disabled = leaving
	acts.add_child(bonus_b)
	var fire_b := _button("Fire", SimQuery.t_("ui.staff.fire"), SimQuery.t_("ui.staff.fire_tip"), fire.bind(chr))
	fire_b.disabled = leaving
	acts.add_child(fire_b)
	v.add_child(acts)
	return box


## What an employee is doing now: starts on day N / leaves today / the queue task / where they are.
func _doing(d: Dictionary) -> String:
	var today := Clock.day(int(sim.state.clock["minute"]))
	if int(d.get("end_day", -1)) >= 0:
		return SimQuery.t_("ui.staff.leaving")
	if not bool(d.get("active", false)) and int(d.get("start_day", 0)) > today:
		return SimQuery.t_("ui.staff.starts") % (int(d["start_day"]) + 1)
	var task: Dictionary = d.get("task", {})
	if not task.is_empty():
		return SimQuery.t_("ui.staff.task") % [SimQuery.recipe_name(sim.catalog, str(task.get("recipe", ""))),
			SimQuery.zone_name(str(task.get("zone", "")))]
	var r := str(d.get("routine", ""))
	var key := "ui.staff.routine." + r
	var s := SimQuery.t_(key)
	return r if s == key else s


## One candidate: name, rank and wage with Hire; the three stats; the reason if they cannot be hired.
func _candidate_row(d: Dictionary) -> Control:
	var chr := str(d["character"])
	var box := _box()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(_label(SimQuery.t_("ui.staff.candidate") % [str(d["name"]), SimQuery.rank_name(sim.catalog,
		str(d["rank"])), int(d["wage"])], Color(0.95, 0.85, 0.6)))
	var ok := str(d.get("status", "")) == "ok"
	var hb := _button("Hire", SimQuery.t_("ui.staff.hire"), SimQuery.t_("ui.staff.hire_tip"), hire.bind(chr))
	hb.disabled = not ok
	top.add_child(hb)
	v.add_child(top)
	var st: Dictionary = d.get("stats", {})
	v.add_child(_label("%s %d · %s %d · %s %d" % [SimQuery.t_("stat.craft"), int(st.get("craft", 0)),
		SimQuery.t_("stat.charisma"), int(st.get("charisma", 0)), SimQuery.t_("stat.constitution"),
		int(st.get("constitution", 0))]))
	if not ok:
		var why := _label(SimQuery.reason_text(str(d.get("status", ""))), Color(1.0, 0.65, 0.5))
		why.name = "Reason"
		v.add_child(why)
		hb.tooltip_text = why.text
	return box


# --- orders ----------------------------------------------------------------------------------------------------------

func hire(chr: String) -> void:
	_give({"type": "hire", "actor": actor(), "building": building, "candidate": chr})


func fire(chr: String) -> void:
	_give({"type": "fire", "actor": actor(), "employee": chr})


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
