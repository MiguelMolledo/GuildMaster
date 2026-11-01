class_name BoardPanel
extends PanelContainer
## The contract board of the square (GDD 4.5.6): the open contracts (item, quantity, minimum quality, deadline, pay)
## with Accept, and the family's accepted ones (time left) with Deliver / Abandon. What the sim would refuse is
## disabled with the reason in the tooltip (Contracts.board_view status). Closes with ESC (the HUD), X, or when the
## person leaves the board. Only gives orders (accept_contract, deliver_contract, abandon_contract).

signal closed

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
	(%OpenLabel as Label).text = SimQuery.t_("ui.board.open")
	(%MineLabel as Label).text = SimQuery.t_("ui.board.mine")
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
	var g := Money.gold(sim.state, Money.family_of(sim.state, actor))
	var sig := str(view) + "|" + str(g)
	if sig == _sig and not force:
		return
	_sig = sig
	(%GoldLabel as Label).text = SimQuery.t_("ui.market.gold") % g
	_fill(%OpenList as VBoxContainer, view.get("open", []), false)
	_fill(%MineList as VBoxContainer, view.get("accepted", []), true)
	reset_size()


func _fill(list: VBoxContainer, rows: Array, mine: bool) -> void:
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if rows.is_empty():
		var l := Label.new()
		l.text = SimQuery.t_("ui.board.none_mine" if mine else "ui.board.none_open")
		l.modulate = Color(1, 1, 1, 0.6)
		list.add_child(l)
		return
	for c: Dictionary in rows:
		var id := str(c.get("id", ""))
		var row := VBoxContainer.new()
		row.name = id
		row.add_theme_constant_override("separation", 0)
		var top := HBoxContainer.new()
		top.name = "Top"
		var what := Label.new()
		what.name = "What"
		what.text = SimQuery.t_("ui.board.what") % [SimQuery.client_name(str(c.get("client", ""))), int(c.get("qty", 1)),
			SimQuery.item_name(sim.catalog, str(c.get("item", "")))]
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(what)
		var pay := Label.new()
		pay.name = "Pay"
		pay.text = SimQuery.t_("ui.board.pay") % int(c.get("pay", 0))
		pay.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		top.add_child(pay)
		row.add_child(top)
		var bottom := HBoxContainer.new()
		bottom.name = "Bottom"
		var terms := Label.new()
		terms.name = "Terms"
		var q := int(c.get("min_quality", 0))
		var quality := SimQuery.t_("ui.board.min_quality") % SimQuery.quality_name(q) if q > 0 else SimQuery.t_("ui.board.any_quality")
		var time := ""
		if mine:
			time = SimQuery.t_("ui.board.left") % SimQuery.hours_label(float(c.get("hours_left", 0)))
		else:
			time = SimQuery.t_("ui.board.deadline") % int(c.get("deadline_days", 1))
		terms.text = "%s · %s" % [quality, time]
		terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(terms)
		var status := str(c.get("status", "ok"))
		if mine:
			var deliver := _button("Deliver", SimQuery.t_("ui.board.deliver"), func() -> void: deliver_contract(id))
			deliver.disabled = status != "ok"
			deliver.tooltip_text = SimQuery.t_("reason." + status) if status != "ok" else SimQuery.t_("ui.board.deliver_tip")
			bottom.add_child(deliver)
			var abandon := _button("Abandon", SimQuery.t_("ui.board.abandon"), func() -> void: abandon_contract(id))
			abandon.tooltip_text = SimQuery.t_("ui.board.abandon_tip")
			bottom.add_child(abandon)
		else:
			var accept := _button("Accept", SimQuery.t_("ui.board.accept"), func() -> void: accept_contract(id))
			accept.disabled = status != "ok"
			accept.tooltip_text = SimQuery.t_("reason." + status) if status != "ok" else ""
			bottom.add_child(accept)
		row.add_child(bottom)
		list.add_child(row)


func _button(n: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## The row of contract `id` in the open list (false) or the family's (true), or null.
func row_of(id: String, mine: bool) -> Control:
	return ((%MineList if mine else %OpenList) as VBoxContainer).get_node_or_null(id) as Control


func accept_contract(id: String) -> void:
	_give({"type": "accept_contract", "actor": actor, "contract": id})


func deliver_contract(id: String) -> void:
	_give({"type": "deliver_contract", "actor": actor, "contract": id})


func abandon_contract(id: String) -> void:
	_give({"type": "abandon_contract", "actor": actor, "contract": id})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("BoardPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
