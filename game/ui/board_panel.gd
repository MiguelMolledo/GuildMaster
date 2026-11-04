class_name BoardPanel
extends PanelContainer
## The contract board of the square (GDD 4.5.6; docs/ui/mecanicas/ciudad_viva.md §3-4), in the management zone.
## First the family's gold and its accepted contracts (item icon × quantity, client, pay; quality, what it carries and
## what the family's buildings hold «llevas 1/2 · almacén 3», the time left as a bar that turns red in the last 6 h;
## the reason Deliver is off written under it; Abandon asks first with its reputation cost). Then the open contracts
## as pinned parchment notes (icon × quantity, client, quality, days, pay and «tienes x/y», green when the family
## already has enough) with Accept (off with its reason). Closes with ESC (the HUD), X, or when the person leaves the
## board. Only gives orders (accept_contract, deliver_contract, abandon_contract).

signal closed

const URGENT_HOURS: int = 6

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)


func open_for(s: Sim, who: String) -> void:
	_bind()
	sim = s
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.board.title")
	(%OpenLabel as Label).text = SimQuery.t_("ui.board.open_short")
	(%MineLabel as Label).text = SimQuery.t_("ui.board.mine")
	(%Hint as Label).text = SimQuery.t_("ui.board.hint")
	(%GoldIcon as TextureRect).texture = UiIcons.ui("icon_oro")
	visible = true
	refresh(true)
	ViewConfig.info("BoardPanel", "open (actor=%s)" % who)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		if bool(SimQuery.board_view(sim, actor).get("at_board", false)):
			refresh()
		else:
			close()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var view := SimQuery.board_view(sim, actor)
	var fam := Money.family_of(sim.state, actor)
	var g := Money.gold(sim.state, fam)
	var sig := str(view) + "|" + str(g) + "|" + str(_stock_sig(view, fam))
	if sig == _sig and not force:
		return
	_sig = sig
	(%GoldLabel as Label).text = MenuKit.gold_text(g)
	var mine: Array = view.get("accepted", [])
	(%MineLabel as Control).visible = not mine.is_empty()
	(%MineList as Control).visible = not mine.is_empty()
	_fill_mine(%MineList as VBoxContainer, mine, fam)
	_fill_open(%OpenList as GridContainer, view.get("open", []), fam)
	reset_size()


func _stock_sig(view: Dictionary, fam: String) -> Array:
	var out: Array = []
	for c: Dictionary in view.get("open", []) + view.get("accepted", []):
		out.append(family_stock(sim, fam, str(c.get("item", "")), int(c.get("min_quality", 0))))
	return out


## How many pieces of `item` (at least `min_quality`) the buildings of `fam` hold (a read: what «almacén» shows).
static func family_stock(s: Sim, fam: String, item: String, min_quality: int) -> int:
	var n := 0
	for b: Dictionary in s.state.buildings.values():
		if str(b.get("owner", "")) == fam and b.get("inventory") is Dictionary:
			n += Contracts.count_valid(b["inventory"], item, min_quality)
	return n


## What the actor carries of a contract's item.
func carried(c: Dictionary) -> int:
	var inv: Dictionary = sim.state.characters.get(actor, {}).get("inventory", {})
	var kept := LiveForge.crate_units(c, int(c.get("min_quality", 0)))  # 03b §3b.3: made to its spec, kept for it
	return kept + (Contracts.count_valid(inv, str(c.get("item", "")), int(c.get("min_quality", 0))) if not inv.is_empty() else 0)


func _quality_text(c: Dictionary) -> String:
	var q := int(c.get("min_quality", 0))
	return SimQuery.t_("ui.board.min_quality") % SimQuery.quality_name(q) if q > 0 else SimQuery.t_("ui.board.any_quality")


func _what(c: Dictionary) -> String:
	return SimQuery.t_("ui.board.what_short") % [int(c.get("qty", 1)), SimQuery.item_name(sim.catalog, str(c.get("item", "")))]


func _icon(c: Dictionary) -> Control:
	var r := UiIcons.item_rect(str(c.get("item", "")))
	if r != null:
		return r
	var hold := Control.new()
	hold.custom_minimum_size = Vector2(16, 16)
	return hold


func _gold(amount: int, variation: StringName = &"GoldLabel") -> Control:
	var h := HBoxContainer.new()
	h.name = "Pay"
	h.add_theme_constant_override("separation", 2)
	var t := TextureRect.new()
	t.texture = UiIcons.ui("icon_oro")
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	h.add_child(t)
	h.add_child(SocialKit.label(MenuKit.gold_text(amount), variation, "Amount"))
	h.tooltip_text = SimQuery.t_("ui.board.pay") % amount
	return h


## The family's contracts: what, how much it has, the time left and Deliver / Abandon with the reason.
func _fill_mine(list: VBoxContainer, rows: Array, fam: String) -> void:
	SocialKit.clear(list)
	for c: Dictionary in rows:
		var id := str(c.get("id", ""))
		var row := VBoxContainer.new()
		row.name = id
		row.add_theme_constant_override("separation", 0)
		var top := HBoxContainer.new()
		top.name = "Top"
		top.add_theme_constant_override("separation", 4)
		top.add_child(_icon(c))
		var what := SocialKit.label("%s · %s" % [_what(c), SimQuery.client_name(str(c.get("client", "")))], &"BoldLabel", "What")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		top.add_child(what)
		var pay := _gold(int(c.get("pay", 0)))
		top.add_child(pay)
		var pay_text := SocialKit.label(SimQuery.t_("ui.board.pay") % int(c.get("pay", 0)), &"", "PayText")
		pay_text.visible = false  # the plain «70 de oro» (tests and screen readers)
		top.add_child(pay_text)
		row.add_child(top)
		var have := carried(c)
		var stock := family_stock(sim, fam, str(c.get("item", "")), int(c.get("min_quality", 0)))
		var terms := SocialKit.label("%s · %s" % [_quality_text(c), SimQuery.t_("ui.board.have_mine") % [have,
			int(c.get("qty", 1)), stock]], &"DimLabel", "Terms")
		terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		terms.custom_minimum_size = Vector2(300, 0)
		var mid := HBoxContainer.new()
		mid.name = "Mid"
		mid.add_child(terms)
		row.add_child(mid)
		var timer := HBoxContainer.new()
		timer.name = "Timer"
		timer.add_theme_constant_override("separation", 4)
		var hours := int(c.get("hours_left", 0))
		var due := int(c.get("due", 0))
		var span := maxf(1.0, float(due - int(c.get("accepted", due - 60))) / 60.0)
		var bar := SocialKit.bar(float(hours) / span, 120.0, "Time")
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if hours <= URGENT_HOURS:
			bar.theme_type_variation = &"UrgentBar"
		timer.add_child(bar)
		timer.add_child(SocialKit.label(SimQuery.hours_label(float(hours)), &"ReasonLabel" if hours <= URGENT_HOURS else &"DimLabel", "Left"))
		row.add_child(timer)
		var bottom := HBoxContainer.new()
		bottom.name = "Bottom"
		var status := str(c.get("status", "ok"))
		var why := SocialKit.label("", &"ReasonLabel", "Why")
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.clip_text = true
		if status == "missing_items":
			why.text = SimQuery.t_("ui.board.missing") % [int(c.get("qty", 1)) - have, SimQuery.item_name(sim.catalog,
				str(c.get("item", ""))).to_lower()]
		elif status != "ok":
			why.text = SimQuery.t_("reason." + status)
		bottom.add_child(why)
		var deliver := _button("Deliver", SimQuery.t_("ui.board.deliver"), func() -> void: deliver_contract(id))
		deliver.disabled = status != "ok"
		deliver.tooltip_text = SimQuery.t_("reason." + status) if status != "ok" else SimQuery.t_("ui.board.deliver_tip")
		bottom.add_child(deliver)
		var abandon := _button("Abandon", SimQuery.t_("ui.board.abandon"), func() -> void: request_abandon(id))
		abandon.tooltip_text = SimQuery.t_("ui.board.abandon_tip")
		bottom.add_child(abandon)
		row.add_child(bottom)
		var panel := PanelContainer.new()
		panel.name = "Row_" + id
		panel.theme_type_variation = &"RowPanel"
		panel.add_child(row)
		list.add_child(panel)


## The open contracts as notes: what, client, quality, days and pay, «tienes x/y» and Accept.
func _fill_open(grid: GridContainer, rows: Array, fam: String) -> void:
	SocialKit.clear(grid)
	if rows.is_empty():
		var l := SocialKit.label(SimQuery.t_("ui.board.none_open_tomorrow"), &"DimLabel", "None")
		grid.add_child(l)
		return
	for c: Dictionary in rows:
		var id := str(c.get("id", ""))
		var note := PanelContainer.new()
		note.name = "Note_" + id
		note.theme_type_variation = &"ParchmentPanel"
		note.custom_minimum_size = Vector2(160, 0)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := VBoxContainer.new()
		row.name = id
		row.add_theme_constant_override("separation", -1)
		var top := HBoxContainer.new()
		top.name = "Top"
		top.add_theme_constant_override("separation", 4)
		top.add_child(_icon(c))
		var what := SocialKit.label(_what(c), &"InkBold", "What")
		what.clip_text = true
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(what)
		var pay_text := SocialKit.label(SimQuery.t_("ui.board.pay") % int(c.get("pay", 0)), &"InkLabel", "Pay")
		pay_text.visible = false
		top.add_child(pay_text)
		row.add_child(top)
		row.add_child(SocialKit.label(SimQuery.client_name(str(c.get("client", ""))), &"InkLabel", "Client"))
		var terms := SocialKit.label(_quality_text(c), &"InkLabel", "Quality")
		terms.clip_text = true
		row.add_child(terms)
		if c.get("spec") is Dictionary and not (c["spec"] as Dictionary).is_empty():  # 03b §3b.3
			var sp := SocialKit.label(SimQuery.t_("ui.board.spec") % [SimQuery.t_("spec.%s.desc" % str(c["spec"].get(
				"id", ""))), int(c.get("spec_pay", 0))], &"InkLabel", "Spec")
			sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sp.custom_minimum_size = Vector2(140, 0)
			row.add_child(sp)
		var line := HBoxContainer.new()
		line.name = "Line"
		line.add_child(_gold(int(c.get("pay", 0)), &"InkBold"))
		var days := SocialKit.label(SimQuery.t_("ui.board.days") % int(c.get("deadline_days", 1)), &"InkLabel", "Days")
		days.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		days.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(days)
		row.add_child(line)
		var bottom := HBoxContainer.new()
		bottom.name = "Bottom"
		var stock := family_stock(sim, fam, str(c.get("item", "")), int(c.get("min_quality", 0))) + carried(c)
		var enough := stock >= int(c.get("qty", 1))
		var have := SocialKit.label(SimQuery.t_("ui.board.have") % [stock, int(c.get("qty", 1))],
			&"PositiveInkLabel" if enough else &"InkLabel", "Terms")
		have.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(have)
		var status := str(c.get("status", "ok"))
		var accept := _button("Accept", SimQuery.t_("ui.board.accept"), func() -> void: accept_contract(id))
		accept.disabled = status != "ok"
		accept.tooltip_text = SimQuery.t_("reason." + status) if status != "ok" else SimQuery.t_("ui.board.accept_tip")
		bottom.add_child(accept)
		row.add_child(bottom)
		if status != "ok":
			var why := SocialKit.label(SimQuery.t_("reason." + status), &"ReasonLabel", "Why")
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.custom_minimum_size = Vector2(140, 0)
			row.add_child(why)
		note.add_child(row)
		grid.add_child(note)


func _button(n: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## The row of contract `id` in the open list (false) or the family's (true), or null.
func row_of(id: String, mine: bool) -> Control:
	return ((%MineList if mine else %OpenList) as Container).find_child(id, true, false) as Control


func accept_contract(id: String) -> void:
	_give({"type": "accept_contract", "actor": actor, "contract": id})


func deliver_contract(id: String) -> void:
	_give({"type": "deliver_contract", "actor": actor, "contract": id})


## Abandon asks first, with its cost (the contract table's fail_reputation, GDD 4.12.1).
func request_abandon(id: String) -> void:
	var c := {}
	for a: Dictionary in sim.state.contracts.get("accepted", []):
		if str(a.get("id", "")) == id:
			c = a
	var t := Contracts.table_for_item(sim.catalog, str(c.get("item", "")))
	SocialKit.ask(self, SimQuery.t_("ui.board.abandon_q"), SimQuery.t_("ui.board.abandon_body") % absi(int(t.get(
		"fail_reputation", 0))), SimQuery.t_("ui.board.abandon"), func() -> void: abandon_contract(id),
		SimQuery.t_("ui.menu.cannot_undo"))


func abandon_contract(id: String) -> void:
	_give({"type": "abandon_contract", "actor": actor, "contract": id})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("BoardPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
