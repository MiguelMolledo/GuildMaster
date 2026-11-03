class_name LedgerPanel
extends PanelContainer
## The account book of the family (GDD 4.18), from the HUD button: tabs Today · By day (last 8 days) · By building ·
## Debts and contracts (loans with their due date and the payment: all of it or an amount -> repay_loan; the accepted
## contracts with their time left) · Notices (newest first; showing them marks them read -> read_notices; a click on
## one -> notice_clicked, the HUD centres the camera or opens its panel). Reads Ledger / Loans / Notices / Contracts;
## only gives orders.
## H9: tab Reputation (GDD 4.12.1): the title and what it opens, the global reputation and the one with each class,
## the next title's requirements (asked for at the town hall), the passive reputation of today and the last changes.

signal closed
signal notice_clicked(notice: Dictionary)

const TABS: Array[String] = ["today", "days", "buildings", "debts", "notices", "reputation"]

var order_sink: Callable = Callable()
var sim: Sim
var family: String = ""
var actor: String = ""   # who gives the family's orders (repay_loan, read_notices)
var tab: String = "today"
var _pay: Dictionary = {}  # loan id -> amount chosen
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	var tabs := %Tabs as Container
	var group := ButtonGroup.new()
	for t: String in TABS:
		var b := Button.new()
		b.name = t.capitalize().replace(" ", "")
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"TabButton"   # the kit's tab (docs/ui/00 §5) and its sound (ui.tab)
		b.pressed.connect(func() -> void: show_tab(t))
		tabs.add_child(b)


func tab_button(t: String) -> Button:
	return (%Tabs as Container).get_node_or_null(t.capitalize().replace(" ", "")) as Button


func open_for(s: Sim, fam: String, who: String, start_tab: String = "") -> void:
	_bind()
	sim = s
	family = fam
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.ledger.title") % str(s.state.families.get(fam, {}).get("name", fam))
	for t: String in TABS:
		tab_button(t).text = SimQuery.t_("ui.ledger.tab." + t)
	visible = true
	show_tab(start_tab if start_tab in TABS else tab)
	ViewConfig.info("LedgerPanel", "open (family=%s, actor=%s, tab=%s)" % [fam, who, tab])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func show_tab(t: String) -> void:
	tab = t
	for x: String in TABS:
		tab_button(x).set_pressed_no_signal(x == t)
	if t == "notices":
		mark_read()
	refresh(true)


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


## The unread notices of the family become read (read_notices), when the Notices tab is shown.
func mark_read() -> void:
	var ids: Array = []
	for n: Dictionary in Notices.list(sim, family, true):
		ids.append(str(n.get("id", "")))
	if not ids.is_empty():
		_give({"type": "read_notices", "actor": actor, "ids": ids})


func _gold() -> int:
	return Money.gold(sim.state, family)


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var data: Variant = _data()
	var sig := tab + "|" + str(data) + "|" + str(_gold()) + "|" + str(_pay) + "|" + SimQuery.events_line(sim) \
		+ SimQuery.season_prices_line(sim)  # H13: the season and the events of the Today tab
	if sig == _sig and not force:
		return
	_sig = sig
	(%GoldLabel as Label).text = SimQuery.t_("ui.market.gold") % _gold()
	var content := %Content as VBoxContainer
	for c: Node in content.get_children():
		content.remove_child(c)
		c.queue_free()
	match tab:
		"today":
			_fill_today(data)
		"days":
			_fill_days(data)
		"buildings":
			_fill_buildings(data)
		"debts":
			_fill_debts(data)
		"notices":
			_fill_notices(data)
		"reputation":
			_fill_reputation(data)


func _data() -> Variant:
	match tab:
		"today":
			return Ledger.summary(sim, family, "today")
		"days":
			return Ledger.summary(sim, family, "days")
		"buildings":
			return Ledger.summary(sim, family, "buildings")
		"debts":
			return {"loans": SimQuery.loans_of(sim, family), "contracts": SimQuery.board_view(sim, actor).get("accepted", [])}
		"notices":
			return Notices.list(sim, family)
		"reputation":
			var f: Dictionary = sim.state.families.get(family, {})
			return {"reputation": Reputation.of(sim.state, family), "classes": f.get("class_reputation", {}),
				"title": Titles.current(sim, family), "log": f.get("reputation_log", []),
				"next": Titles.next_of(sim, family)}
	return {}


## H9: the Reputation tab (docs/ui/mecanicas/titulos_y_reputacion.md: ReputationView builds it).
func _fill_reputation(_d: Dictionary) -> void:
	ReputationView.fill(%Content as VBoxContainer, sim, family)


## The text of a reputation change's reason (rep.reason.<id>; microevents share one).
static func reason_text(reason: String) -> String:
	var key := "rep.reason." + ("microevent" if reason.begins_with("microevent_") else reason)
	var t := SimQuery.t_(key)
	return reason if t == key else t


func _label(text: String, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	(%Content as VBoxContainer).add_child(l)
	return l


func _line(left: String, right: String, n: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	if n != "":
		row.name = n
	var a := Label.new()
	a.text = left
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # fits the management zone (356)
	row.add_child(a)
	var b := Label.new()
	b.text = right
	b.name = "Value"
	row.add_child(b)
	(%Content as VBoxContainer).add_child(row)
	return row


static func signed(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


func _fill_today(d: Variant) -> void:
	var t: Dictionary = d if d is Dictionary else {}
	_line(SimQuery.t_("ui.ledger.income"), signed(int(t.get("income", 0))), "Income")
	_line(SimQuery.t_("ui.ledger.expense"), signed(int(t.get("expense", 0))), "Expense")
	_line(SimQuery.t_("ui.ledger.net"), signed(int(t.get("net", 0))), "Net")
	(%Content as VBoxContainer).add_child(HSeparator.new())
	var cats: Dictionary = t.get("by_category", {})
	if cats.is_empty():
		_label(SimQuery.t_("ui.ledger.nothing_today"), Color(1, 1, 1, 0.6))
	var keys: Array = cats.keys()
	keys.sort()
	for c: String in keys:
		_line(SimQuery.category_name(c), signed(int(cats[c])), c)
	_fill_prices()


## H13: why prices move today: the season's multipliers and each global event in force with its time left.
func _fill_prices() -> void:
	(%Content as VBoxContainer).add_child(HSeparator.new())
	var l := _label(SimQuery.season_prices_line(sim))
	l.name = "SeasonPrices"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for v: Dictionary in WorldEvents.view(sim):
		var key := str(v["text_key"])
		var e := _label(SimQuery.t_("ui.ledger.event") % [SimQuery.t_(key), SimQuery.time_left(int(v["minutes_left"])),
			SimQuery.t_(key + ".desc")], Color(0.94, 0.75, 0.38))
		e.name = "Event_" + str(v["def"])
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _fill_days(d: Variant) -> void:
	var rows: Array = d if d is Array else []
	if rows.is_empty():
		_label(SimQuery.t_("ui.ledger.nothing"), Color(1, 1, 1, 0.6))
		return
	_line(SimQuery.t_("ui.ledger.day_header"), SimQuery.t_("ui.ledger.days_cols"))
	for r: Dictionary in rows:
		_line(SimQuery.t_("ui.ledger.day") % (int(r.get("day", 0)) + 1), "%s  %s  = %s" % [signed(int(r.get("income", 0))),
			signed(int(r.get("expense", 0))), signed(int(r.get("net", 0)))], "Day%d" % int(r.get("day", 0)))


func _fill_buildings(d: Variant) -> void:
	var t: Dictionary = d if d is Dictionary else {}
	if t.is_empty():
		_label(SimQuery.t_("ui.ledger.nothing"), Color(1, 1, 1, 0.6))
		return
	var ids: Array = t.keys()
	ids.sort()
	for b: String in ids:
		var cats: Dictionary = t[b]
		var net := 0
		for c: String in cats:
			net += int(cats[c])
		var title := SimQuery.building_label(sim.state, sim.catalog, b) if b != "" else SimQuery.t_("ui.ledger.no_building")
		var head := _line(title, signed(net), "B_" + (b if b != "" else "none"))
		(head.get_child(0) as Label).add_theme_color_override("font_color", Color(0.85, 0.7, 0.42))
		var keys: Array = cats.keys()
		keys.sort()
		for c: String in keys:
			_line("   " + SimQuery.category_name(c), signed(int(cats[c])))


func _fill_debts(d: Variant) -> void:
	var t: Dictionary = d
	var loans: Array = t.get("loans", [])
	_label(SimQuery.t_("ui.ledger.loans"), Color(0.85, 0.7, 0.42))
	if loans.is_empty():
		_label(SimQuery.t_("ui.ledger.no_loans"), Color(1, 1, 1, 0.6))
	var g := _gold()
	for l: Dictionary in loans:
		var id := str(l.get("id", ""))
		var owed := int(l.get("outstanding", 0))
		var line := _line(SimQuery.t_("ui.ledger.loan") % [SimQuery.t_("lender." + str(l.get("lender", ""))), owed],
			SimQuery.t_("ui.ledger.due") % [SimQuery.minute_label(int(l.get("due_minute", 0)) - 1),
			int(l.get("days_left", 0))], id)
		if bool(l.get("extended", false)):
			(line.get_child(1) as Label).text += " · " + SimQuery.t_("ui.ledger.extended")
		var pay := HBoxContainer.new()
		pay.name = id + "_pay"
		var amount := SpinBox.new()
		amount.name = "Amount"
		amount.min_value = 1
		amount.max_value = maxi(1, mini(owed, g))
		amount.value = clampi(int(_pay.get(id, mini(owed, g))), 1, maxi(1, mini(owed, g)))
		amount.custom_minimum_size = Vector2(64, 0)
		amount.value_changed.connect(func(v: float) -> void: _pay[id] = int(v))
		pay.add_child(amount)
		var some := Button.new()
		some.name = "Pay"
		some.text = SimQuery.t_("ui.ledger.pay")
		some.focus_mode = Control.FOCUS_NONE
		some.disabled = g <= 0
		some.tooltip_text = SimQuery.t_("reason.not_enough_gold") if g <= 0 else ""
		some.pressed.connect(func() -> void: repay(id, int(amount.value)))
		pay.add_child(some)
		var all := Button.new()
		all.name = "PayAll"
		all.text = SimQuery.t_("ui.ledger.pay_all") % owed
		all.focus_mode = Control.FOCUS_NONE
		all.disabled = g < owed
		all.tooltip_text = SimQuery.t_("reason.not_enough_gold") if g < owed else ""
		all.pressed.connect(func() -> void: repay(id, owed))
		pay.add_child(all)
		(%Content as VBoxContainer).add_child(pay)
	(%Content as VBoxContainer).add_child(HSeparator.new())
	_label(SimQuery.t_("ui.ledger.contracts"), Color(0.85, 0.7, 0.42))
	var cs: Array = t.get("contracts", [])
	if cs.is_empty():
		_label(SimQuery.t_("ui.board.none_mine"), Color(1, 1, 1, 0.6))
	for c: Dictionary in cs:
		_line(SimQuery.t_("ui.board.what") % [SimQuery.client_name(str(c.get("client", ""))), int(c.get("qty", 1)),
			SimQuery.item_name(sim.catalog, str(c.get("item", "")))],
			SimQuery.t_("ui.board.left") % SimQuery.hours_label(float(c.get("hours_left", 0))), str(c.get("id", "")))


func _fill_notices(d: Variant) -> void:
	var rows: Array = d if d is Array else []
	if rows.is_empty():
		_label(SimQuery.t_("ui.ledger.no_notices"), Color(1, 1, 1, 0.6))
		return
	var colors: Dictionary = ViewConfig.value("notices", {}).get("colors", {})
	for n: Dictionary in rows:
		var b := Button.new()
		b.name = str(n.get("id", ""))
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%s  %s%s" % [SimQuery.minute_label(int(n.get("minute", 0))), "" if bool(n.get("read", false)) else "• ",
			SimQuery.notice_text(sim.state, sim.catalog, n)]
		b.add_theme_color_override("font_color", ViewConfig.color(str(colors.get(str(n.get("severity", "info")), "#d8d0c0"))))
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		var notice := n.duplicate(true)
		b.pressed.connect(func() -> void: notice_clicked.emit(notice))
		(%Content as VBoxContainer).add_child(b)


## The row (or button) named `n` in the content of the open tab, or null.
func row_of(n: String) -> Control:
	return (%Content as VBoxContainer).get_node_or_null(n) as Control


func repay(loan: String, amount: int) -> void:
	if amount <= 0:
		return
	_give({"type": "repay_loan", "actor": actor, "loan": loan, "amount": amount})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("LedgerPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
