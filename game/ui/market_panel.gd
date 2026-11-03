class_name MarketPanel
extends PanelContainer
## The one buy/sell panel of every stall and shop (GDD 4.5.1-4.5.2, 4.5.7): tabs Buy / Sell filtered by the stall
## (what Market.offers returns), unit price, quantity −/+, Buy, "Buy and send to…" with the family's buildings
## (errand), Sell 1 / Sell all. A button the sim would refuse is disabled with the reason in its tooltip. The family's
## gold is always shown. Closes with ESC (the HUD), X, or when the person is no longer at the stall
## (Market.stall_at). Only gives orders (buy, sell); the sim decides.

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var stall: String = ""
var tab: String = "buy"   # "buy" | "sell"
var _qty: Dictionary = {}  # "<item>_<q>" -> chosen quantity (buy tab)
var _sig: String = ""
var _offers: Dictionary = {}
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%BuyTab as Button).pressed.connect(func() -> void: show_tab("buy"))
	(%SellTab as Button).pressed.connect(func() -> void: show_tab("sell"))


## Opens the panel of `stall_id` for `who` (who has to be at it: the HUD opens it on arrival).
func open_for(s: Sim, who: String, stall_id: String) -> void:
	_bind()
	sim = s
	actor = who
	stall = stall_id
	_qty.clear()
	(%Title as Label).text = SimQuery.stall_name(s.catalog, stall_id)
	(%BuyTab as Button).text = SimQuery.t_("ui.market.buy_tab")
	(%SellTab as Button).text = SimQuery.t_("ui.market.sell_tab")
	visible = true
	show_tab("buy")
	ViewConfig.info("MarketPanel", "open (stall=%s, actor=%s)" % [stall_id, who])


func close() -> void:
	if visible:
		visible = false
		ViewConfig.info("MarketPanel", "close (stall=%s, actor=%s)" % [stall, actor])
		closed.emit()


func show_tab(t: String) -> void:
	tab = t
	(%BuyTab as Button).set_pressed_no_signal(t == "buy")
	(%SellTab as Button).set_pressed_no_signal(t == "sell")
	(%BuyList as Control).visible = t == "buy"
	(%SellList as Control).visible = t == "sell"
	refresh(true)


func _process(_delta: float) -> void:
	if visible and sim != null:
		if still_there():
			refresh()
		else:
			close()


## Whether the person is still at the stall (or inside the shop): the panel closes otherwise (GDD 4.5.2).
func still_there() -> bool:
	return actor != "" and SimQuery.stall_at(sim, actor) == stall


func gold() -> int:
	return Money.gold(sim.state, Money.family_of(sim.state, actor))


## Rebuilds the lists when the offers or the gold changed (or always with `force`).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	_offers = SimQuery.market_offers(sim, actor, stall)
	var g := gold()
	var sig := str(_offers) + "|" + str(g) + "|" + tab + "|" + str(_qty) + "|" + str(Clock.day(int(sim.state.clock["minute"])))
	if sig == _sig and not force:
		return
	_sig = sig
	(%GoldLabel as Label).text = SimQuery.t_("ui.market.gold") % g
	var status := %StatusLabel as Label
	status.visible = str(_offers.get("reason", "")) != ""
	status.text = SimQuery.t_("reason." + str(_offers.get("reason", "")))
	if str(_offers.get("reason", "")) == "market_closed":
		var opens := SimQuery.market_opens_text(sim)
		if opens != "":
			status.text += " · " + opens   # H5: when to come back
	if tab == "buy":
		_fill_buy()
	else:
		_fill_sell()
	reset_size()


func _clear(list: VBoxContainer) -> void:
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()


func _hint(text: String) -> void:
	var h := %Hint as Label
	h.visible = text != ""
	h.text = text


func _fill_buy() -> void:
	var list := %BuyList as VBoxContainer
	_clear(list)
	var rows: Array = _offers.get("buy", [])
	_hint(SimQuery.t_("ui.market.nothing_to_buy") if rows.is_empty() else "")
	var homes: Array = _offers.get("deliver_to", [])
	var surcharge := float(sim.catalog.market.get("errand", {}).get("surcharge", 0.2))
	for o: Dictionary in rows:
		var item := str(o["item"])
		var q := int(o["quality"])
		var key := "%s_%d" % [item, q]
		var price := int(o.get("price", 0))
		var max_qty := int(o.get("max_qty", 0))
		var st := str(o.get("status", "ok"))
		var qty := clampi(int(_qty.get(key, 1)), 1, maxi(1, max_qty) if st == "ok" else 99)
		_qty[key] = qty
		var row := VBoxContainer.new()
		row.name = key
		row.add_theme_constant_override("separation", 0)
		var top := HBoxContainer.new()
		top.name = "Top"
		var name_l := Label.new()
		name_l.name = "Name"
		name_l.text = SimQuery.item_label(sim.catalog, item, q)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_l)
		var price_l := Label.new()
		price_l.name = "Price"
		price_l.text = SimQuery.t_("ui.market.unit_price") % price
		price_l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		top.add_child(price_l)
		row.add_child(top)
		var why_text := SimQuery.price_reason(sim, item)  # H13: why the price is not the base (season, events, demand)
		if why_text != "":
			row.add_child(_why_label(why_text))
		var bottom := HBoxContainer.new()
		bottom.name = "Controls"
		var minus := _button("Minus", "−", func() -> void: set_qty(item, q, qty - 1))
		minus.disabled = qty <= 1
		bottom.add_child(minus)
		var qty_l := Label.new()
		qty_l.name = "Qty"
		qty_l.text = str(qty)
		qty_l.custom_minimum_size = Vector2(20, 0)
		qty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bottom.add_child(qty_l)
		var plus := _button("Plus", "+", func() -> void: set_qty(item, q, qty + 1))
		plus.disabled = st == "ok" and qty >= max_qty
		bottom.add_child(plus)
		var total_l := Label.new()
		total_l.text = SimQuery.t_("ui.market.total") % (price * qty)
		total_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(total_l)
		var buy_b := _button("Buy", SimQuery.t_("ui.market.buy"), func() -> void: buy(item, q, int(_qty[key])))
		var why := _buy_reason(st, price * qty, max_qty, qty)
		buy_b.disabled = why != ""
		buy_b.tooltip_text = SimQuery.t_("reason." + why) if why != "" else SimQuery.t_("ui.market.buy_tip") % [qty, price * qty]
		bottom.add_child(buy_b)
		var send := MenuButton.new()
		send.name = "Send"
		send.text = SimQuery.t_("ui.market.send")
		send.focus_mode = Control.FOCUS_NONE
		send.flat = false
		var cost := roundi(price * qty * (1.0 + surcharge))
		var send_why := _send_reason(st, cost, homes)
		send.disabled = send_why != ""
		send.tooltip_text = SimQuery.t_("reason." + send_why) if send_why != "" else SimQuery.t_("ui.market.send_tip") % [
			roundi(surcharge * 100.0), cost]
		var pop := send.get_popup()
		for i: int in homes.size():
			pop.add_item(SimQuery.building_label(sim.state, sim.catalog, str(homes[i])), i)
		pop.id_pressed.connect(func(i: int) -> void: buy(item, q, int(_qty[key]), str(homes[i])))
		bottom.add_child(send)
		row.add_child(bottom)
		list.add_child(row)


## Why Buy is disabled ("" = enabled): the sim's status, or the gold for this quantity (GDD 4.5.2: the reason in the
## tooltip). The weight is the sim's to judge: max_qty already counts it.
func _buy_reason(status: String, cost: int, max_qty: int, qty: int) -> String:
	if status != "ok":
		return status
	if cost > gold():
		return "not_enough_gold"
	if qty > max_qty:
		return "too_heavy"
	return ""


## Why "Buy and send to…" is disabled: the market being closed or not at the stall, no own building, the gold.
## The weight does not count (the errand carries it); the storage room is the sim's to judge.
func _send_reason(status: String, cost: int, homes: Array) -> String:
	if status != "ok" and status != "too_heavy" and status != "not_enough_gold":
		return status
	if homes.is_empty():
		return "no_own_building"
	if cost > gold():
		return "not_enough_gold"
	return ""


func _fill_sell() -> void:
	var list := %SellList as VBoxContainer
	_clear(list)
	var rows: Array = _offers.get("sell", [])
	_hint(SimQuery.t_("ui.market.nothing_to_sell") if rows.is_empty() else "")
	var where := str(_offers.get("reason", ""))
	for o: Dictionary in rows:
		var item := str(o["item"])
		var q := int(o["quality"])
		var have := int(o.get("qty", 0))
		var price := int(o.get("price", 0))
		var row := HBoxContainer.new()
		row.name = "%s_%d" % [item, q]
		var name_l := Label.new()
		name_l.name = "Name"
		name_l.text = "%s ×%d" % [SimQuery.item_label(sim.catalog, item, q), have]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var price_l := Label.new()
		price_l.name = "Price"
		price_l.text = SimQuery.t_("ui.market.unit_price") % price
		price_l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		row.add_child(price_l)
		var why := ""
		if where != "":
			why = where
		elif have <= 0:
			why = "not_enough"
		var one := _button("SellOne", SimQuery.t_("ui.market.sell_one"), func() -> void: sell(item, q, 1))
		var all := _button("SellAll", SimQuery.t_("ui.market.sell_all"), func() -> void: sell(item, q, have))
		for b: Button in [one, all]:
			b.disabled = why != ""
			b.tooltip_text = SimQuery.t_("reason." + why) if why != "" else ""
			row.add_child(b)
		if why == "":
			one.tooltip_text = SimQuery.t_("ui.market.sell_tip") % [1, price]
			all.tooltip_text = SimQuery.t_("ui.market.sell_tip") % [have, price * have]
		list.add_child(row)
		var why_text := SimQuery.price_reason(sim, item)  # H13
		if why_text != "":
			var why_l := _why_label(why_text)
			why_l.name = row.name + "_Why"
			list.add_child(why_l)


## H13: the small line under a price that says why it moves (SimQuery.price_reason).
func _why_label(text: String) -> Label:
	var l := Label.new()
	l.name = "Why"
	l.text = SimQuery.t_("ui.market.price_why") % text
	l.theme_type_variation = &"DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(n: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## The row of (item, quality) in the list of the open tab, or null.
func row_of(item: String, quality: int) -> Control:
	var list := (%BuyList if tab == "buy" else %SellList) as VBoxContainer
	return list.get_node_or_null("%s_%d" % [item, quality]) as Control


func set_qty(item: String, quality: int, qty: int) -> void:
	_qty["%s_%d" % [item, quality]] = maxi(1, qty)
	refresh(true)


func buy(item: String, quality: int, qty: int, deliver_to: String = "") -> void:
	if qty <= 0:
		return
	var o := {"type": "buy", "actor": actor, "stall": stall, "item": item, "quality": quality, "qty": qty}
	if deliver_to != "":
		o["deliver_to"] = deliver_to
	_give(o)


func sell(item: String, quality: int, qty: int) -> void:
	if qty <= 0:
		return
	_give({"type": "sell", "actor": actor, "stall": stall, "item": item, "quality": quality, "qty": qty})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("MarketPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
