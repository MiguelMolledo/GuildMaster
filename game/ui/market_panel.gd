class_name MarketPanel
extends PanelContainer
## The one buy/sell panel of every stall and shop (docs/ui/mecanicas/mercado_y_libro.md §4.1-4.2; GDD 4.5.1-4.5.3,
## 4.5.7), in the management zone. Header: the stall, whether it is open and until when, the family's gold. Tabs Buy /
## Sell filtered by the stall (Market.offers). Every row shows its demand without the mouse (5 steps, word and number;
## the cuts are the view's, data/view.json market_demand).
##   Buy: price per unit, − quantity +, total, Buy, and the errand button with its surcharge and time written
##       («Enviar → Forja +8 · 2 h»); under them what limits the quantity («caben 23 (peso)» / «oro para 19») and, when
##       a button is disabled, why.
##   Sell: Sell 1 · price and Sell all with the sum unit by unit («59+57+54 = 170», Market.sell_preview), the demand
##       it leaves and that it recovers at dawn, and «mañana valdrá ~ N» when the demand is low.
## Closes with ESC (the HUD), X, or when the person is no longer at the stall (Market.stall_at). Only gives orders
## (buy, sell); the sim decides.

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
	(%BuyTab as Button).theme_type_variation = &"TabButton"
	(%SellTab as Button).theme_type_variation = &"TabButton"
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


## The demand of `item` as the indicator says it: {steps 1..5, word, color, value}.
func demand_view(item: String) -> Dictionary:
	var d := Market.demand(sim, item)
	var cuts: Array = (ViewConfig.value("market_demand", {}) as Dictionary).get("steps", [])
	for i: int in cuts.size():
		if d < float(cuts[i].get("below", 99.0)):
			return {"steps": i + 1, "word": str(cuts[i].get("word", "")), "color": str(cuts[i].get("color", "texto")), "value": d}
	return {"steps": 5, "word": "very_high", "color": "positivo", "value": d}


## «demanda ▃▄▅ alta 1,10»: the indicator as a label (bars drawn with the block glyphs of the kit's font).
func _demand_label(item: String) -> Label:
	var v := demand_view(item)
	var l := Label.new()
	l.name = "Demand"
	l.text = "%s %s" % [SimQuery.t_("ui.market.demand." + str(v["word"])), _num(float(v["value"]))]
	l.add_theme_color_override("font_color", Color.html(StationMenu._token(str(v["color"]))))
	l.tooltip_text = SimQuery.t_("ui.market.demand_tip") % [_num(float(v["value"])),
		_num(float(sim.catalog.market.get("demand", {}).get("recover_per_day", 0.4))),
		_num(float(sim.catalog.market.get("demand", {}).get("rest", 1.0)))]
	return l


## The 5-step indicator (20×8): as many steps filled as the demand's, in its colour (kit piece «indicador de demanda»).
func _demand_bars(item: String) -> Control:
	var v := demand_view(item)
	var c := Control.new()
	c.name = "DemandBars"
	c.custom_minimum_size = Vector2(20, 13)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var on := Color.html(StationMenu._token(str(v["color"])))
	var off := Color.html(StationMenu._token("hueco"))
	var steps := int(v["steps"])
	c.draw.connect(func() -> void:
		for i: int in 5:
			var h := 2.0 + 1.5 * float(i)
			c.draw_rect(Rect2(float(i) * 4.0, 11.0 - h, 3.0, h), on if i < steps else off))
	return c


static func _num(f: float) -> String:
	return ("%.2f" % f).replace(".", ",")


## «abierto hasta las 21:00» (the start of the first phase after the open ones today), or "".
func _open_until() -> String:
	var open: Array = sim.catalog.market.get("open_phases", [])
	var t: Dictionary = sim.catalog.time
	var season := str(sim.now().get("season", "spring"))
	var starts: Dictionary = t.get("phase_starts", {}).get(season, {})
	var phase := Clock.phase(int(sim.state.clock["minute"]), t)
	if not phase in open:
		return ""
	var i := Clock.PHASES.find(phase)
	for k: int in range(1, Clock.PHASES.size() + 1):
		var nxt: String = Clock.PHASES[(i + k) % Clock.PHASES.size()]
		if not nxt in open:
			var m := int(starts.get(nxt, 0))
			return SimQuery.t_("ui.market.open_until") % [m / 60, m % 60]
	return ""


## Rebuilds the lists when the offers or the gold changed (or always with `force`).
func refresh(force: bool = false) -> void:
	if sim == null:
		return
	_offers = SimQuery.market_offers(sim, actor, stall)
	var g := gold()
	var sig := str(_offers) + "|" + str(g) + "|" + tab + "|" + str(_qty) + "|" + str(Clock.day(int(sim.state.clock["minute"]))) \
		+ "|" + str(sim.state.market.get("demand", {}))
	if (sig == _sig or UiFeel.hold_rebuild(self)) and not force:
		return
	_sig = sig
	(%GoldLabel as Label).text = SimQuery.t_("ui.market.gold") % g
	var status := %StatusLabel as Label
	var reason := str(_offers.get("reason", ""))
	status.visible = true
	status.theme_type_variation = &"ReasonLabel" if reason != "" else &"DimLabel"
	status.text = SimQuery.t_("reason." + reason) if reason != "" else _open_until()
	if reason == "market_closed":
		var opens := SimQuery.market_opens_text(sim)
		if opens != "":
			status.text += " · " + opens   # H5: when to come back
	status.visible = status.text != ""
	if tab == "buy":
		_fill_buy()
	else:
		_fill_sell()


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
	_hint(SimQuery.t_("ui.market.nothing_to_buy") if rows.is_empty() else SimQuery.t_("ui.market.errand_help") % [
		roundi(_errand_rate() * 100.0),
		SimQuery.duration_label(Market.errand_minutes(sim))])
	var homes: Array = _offers.get("deliver_to", [])
	for o: Dictionary in rows:
		list.add_child(_buy_row(o, homes))


func _buy_row(o: Dictionary, homes: Array) -> VBoxContainer:
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
	row.add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 4)
	var icon := UiIcons.item_rect(item)
	if icon != null:
		top.add_child(icon)
	var name_l := Label.new()
	name_l.name = "Name"
	name_l.text = SimQuery.item_label(sim.catalog, item, q)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	top.add_child(name_l)
	var price_l := Label.new()
	price_l.name = "Price"
	price_l.text = SimQuery.t_("ui.market.unit_price") % price
	price_l.theme_type_variation = &"GoldLabel"
	top.add_child(price_l)
	top.add_child(_demand_bars(item))
	top.add_child(_demand_label(item))
	row.add_child(top)
	var why_text := SimQuery.price_reason(sim, item)  # H13: why the price is not the base (season, events, demand)
	if why_text != "":
		row.add_child(_why_label(why_text))
	var bottom := HFlowContainer.new()   # − qty + = total on one line, Buy and the errand under them
	bottom.name = "Controls"
	bottom.add_theme_constant_override("h_separation", 3)
	bottom.add_theme_constant_override("v_separation", 1)
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
	if plus.disabled:   # an off button says why (verificación A7; jugador J: coal's «+» said nothing)
		plus.tooltip_text = SimQuery.t_("ui.market.plus_max") % max_qty
	bottom.add_child(plus)
	var total_l := Label.new()
	total_l.text = SimQuery.t_("ui.market.total") % (price * qty)
	total_l.custom_minimum_size = Vector2(240, 0)
	bottom.add_child(total_l)
	var buy_b := _button("Buy", SimQuery.t_("ui.market.buy"), func() -> void: buy(item, q, int(_qty[key])))
	var why := _buy_reason(st, price * qty, max_qty, qty)
	buy_b.disabled = why != ""
	buy_b.tooltip_text = SimQuery.t_("reason." + why) if why != "" else SimQuery.t_("ui.market.buy_tip") % [qty, price * qty]
	bottom.add_child(buy_b)
	var send := MenuButton.new()
	send.name = "Send"
	send.focus_mode = Control.FOCUS_NONE
	send.flat = false
	var cost := price * qty
	var extra := Market.errand_surcharge(sim, cost, stall)
	var to_name := SimQuery.building_label(sim.state, sim.catalog, str(homes[0])) if homes.size() == 1 else ""
	send.text = SimQuery.t_("ui.market.send_to") % [to_name if to_name != "" else SimQuery.t_("ui.market.send_choose"), extra,
		SimQuery.duration_label(Market.errand_minutes(sim))]
	var send_why := _send_reason(st, cost + extra, homes, item, q, qty)
	send.disabled = send_why != ""
	send.tooltip_text = SimQuery.t_("reason." + send_why) if send_why != "" else SimQuery.t_("ui.market.send_tip") % [
		roundi(_errand_rate() * 100.0), cost + extra]
	var pop := send.get_popup()
	for i: int in homes.size():
		pop.add_item(SimQuery.building_label(sim.state, sim.catalog, str(homes[i])), i)
	pop.id_pressed.connect(func(i: int) -> void: buy(item, q, int(_qty[key]), str(homes[i])))
	bottom.add_child(send)
	row.add_child(bottom)
	var limit := Label.new()
	limit.name = "Limit"
	limit.theme_type_variation = &"DimLabel"
	limit.text = _limit_text(item, q, price, max_qty)
	limit.visible = limit.text != ""
	row.add_child(limit)
	if why != "" or send_why != "":
		var r := Label.new()
		r.name = "Reason"
		r.theme_type_variation = &"ReasonLabel"
		r.text = _reason_words(why if why != "" else send_why, price * qty, item, q, homes)
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(r)
	return row


## What limits the quantity: «Lleva 14/60 kg: caben 23» or «oro para 19» ("" if it is not the limit now).
func _limit_text(item: String, q: int, price: int, max_qty: int) -> String:
	if actor == "" or not sim.state.characters.has(actor):
		return ""
	var by_gold := gold() / maxi(1, price)
	var bag: Dictionary = sim.state.characters[actor]["inventory"]
	var by_weight := Inventory.fit_count(bag, sim.catalog, item, q, maxi(by_gold, 1) + 50)
	if by_weight <= by_gold:
		return SimQuery.t_("ui.market.fits_weight") % [String.num(SimQuery.carried_weight(sim, actor), 0),
			String.num(SimQuery.max_weight(sim, actor), 0), by_weight]
	return SimQuery.t_("ui.market.gold_for") % by_gold if max_qty >= 0 else ""


## A refusal in words with its figures (_comun.md): «Te faltan 12 de oro», «El almacén de la Forja no tiene hueco».
func _reason_words(why: String, cost: int, item: String, q: int, homes: Array) -> String:
	match why:
		"not_enough_gold":
			return SimQuery.t_("ui.market.missing_gold") % maxi(0, cost - gold())
		"storage_full", "no_room":
			var b := str(homes[0]) if not homes.is_empty() else ""
			var inv: Dictionary = sim.state.buildings.get(b, {}).get("inventory", {})
			return SimQuery.t_("ui.market.storage_full") % [SimQuery.building_label(sim.state, sim.catalog, b),
				(inv.get("stacks", []) as Array).size(), int(inv.get("limit", 0))]
		"too_heavy":
			return SimQuery.t_("ui.market.too_heavy") % String.num(maxf(0.0, SimQuery.max_weight(sim, actor) - SimQuery.carried_weight(sim, actor)), 0)
	return SimQuery.reason_text(why)


## Why Buy is disabled ("" = enabled): the sim's status, or the gold for this quantity. The weight is the sim's to
## judge: max_qty already counts it.
func _buy_reason(status: String, cost: int, max_qty: int, qty: int) -> String:
	if status != "ok":
		return status
	if cost > gold():
		return "not_enough_gold"
	if qty > max_qty:
		return "too_heavy"
	return ""


## Why the errand is disabled: the market being closed or not at the stall, no own building, the gold (with the
## surcharge), no room in the building's storage (Market.max_buy with the building, counting the errands on the way).
func _send_reason(status: String, cost: int, homes: Array, item: String, q: int, qty: int) -> String:
	if status != "ok" and status != "too_heavy" and status != "not_enough_gold":
		return status
	if homes.is_empty():
		return "no_own_building"
	if cost > gold():
		return "not_enough_gold"
	if homes.size() == 1 and Market.max_buy(sim, actor, stall, item, q, str(homes[0])) < qty:
		return "storage_full"
	return ""


func _fill_sell() -> void:
	var list := %SellList as VBoxContainer
	_clear(list)
	var rows: Array = _offers.get("sell", [])
	_hint(_nothing_to_sell() if rows.is_empty() else SimQuery.t_("ui.market.sell_help"))
	var where := str(_offers.get("reason", ""))
	for o: Dictionary in rows:
		var srow := _sell_row(o, where)
		list.add_child(srow)
		var why_text := SimQuery.price_reason(sim, str(o["item"]))  # H13: why the price is not the base
		if why_text != "":
			var why_l := _why_label(why_text)
			why_l.name = srow.name + "_Why"
			list.add_child(why_l)


## «No llevas nada que se venda aquí. La Armería compra espadas, martillos y armaduras.»
func _nothing_to_sell() -> String:
	var takes: Array = sim.catalog.market.get("stalls", {}).get(stall, {}).get("sells", [])
	var names: PackedStringArray = []
	for it: String in sim.catalog.items():
		if str(sim.catalog.item(it).get("market_stall", "")) in takes and names.size() < 4:
			names.append(SimQuery.item_name(sim.catalog, it).to_lower())
	return SimQuery.t_("ui.market.nothing_to_sell") + (". " + SimQuery.t_("ui.market.stall_takes") % [
		SimQuery.stall_name(sim.catalog, stall), ", ".join(names)] if not names.is_empty() else "")


## One thing to sell: an HFlow so that Name / Price / Demand go on the first line, the buttons under them and the
## demand lines under those (children named as the tests and the smoke scripts look for them).
func _sell_row(o: Dictionary, where: String) -> HFlowContainer:
	var item := str(o["item"])
	var q := int(o["quality"])
	var have := int(o.get("qty", 0))
	var price := int(o.get("price", 0))
	var row := HFlowContainer.new()
	row.name = "%s_%d" % [item, q]
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 1)
	var name_l := Label.new()
	name_l.name = "Name"
	name_l.text = "%s ×%d" % [SimQuery.item_label(sim.catalog, item, q), have]
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.clip_text = true
	row.add_child(name_l)
	var price_l := Label.new()
	price_l.name = "Price"
	price_l.text = SimQuery.t_("ui.market.unit_price") % price
	price_l.theme_type_variation = &"GoldLabel"
	row.add_child(price_l)
	row.add_child(_demand_bars(item))
	row.add_child(_demand_label(item))
	var why := where
	if why == "" and have <= 0:
		why = "not_enough"
	var preview := Market.sell_preview(sim, actor, stall, item, q, have)
	var one := _button("SellOne", SimQuery.t_("ui.market.sell_one_at") % price, func() -> void: sell(item, q, 1))
	var sum := " + ".join((preview.get("prices", []) as Array).map(func(p: Variant) -> String: return str(int(p))))
	var all_text := SimQuery.t_("ui.market.sell_all_at") % [have, ("%s = %d" % [sum, int(preview.get("total", 0))]) if have > 1 else str(price)]
	var all := _button("SellAll", all_text, func() -> void: sell(item, q, have))
	for b: Button in [one, all]:
		b.disabled = why != ""
		b.tooltip_text = SimQuery.t_("reason." + why) if why != "" else ""
		row.add_child(b)
	all.visible = have > 1   # with one, «Vender todo» would repeat «Vender 1» (jugador J3)
	if why == "":
		one.tooltip_text = SimQuery.t_("ui.market.sell_tip") % [1, price]
		all.tooltip_text = SimQuery.t_("ui.market.sell_tip") % [have, int(preview.get("total", 0))]
	if have > 1:
		var after := Label.new()
		after.name = "After"
		after.theme_type_variation = &"DimLabel"
		after.custom_minimum_size = Vector2(330, 0)
		after.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var d_after := float(preview.get("demand_after", 1.0))
		after.text = SimQuery.t_("ui.market.after_selling") % [have, _num(d_after), _word_of(d_after),
			_num(float(sim.catalog.market.get("demand", {}).get("rest", 1.0)))]
		row.add_child(after)
	if Market.demand(sim, item) < 0.9:
		var tomorrow := Label.new()
		tomorrow.name = "Tomorrow"
		tomorrow.theme_type_variation = &"WarningLabel"
		tomorrow.custom_minimum_size = Vector2(330, 0)
		tomorrow.text = SimQuery.t_("ui.market.tomorrow") % Market.sell_price_at(sim, item, q, Market.demand_tomorrow(sim, item))
		row.add_child(tomorrow)
	return row


func _word_of(d: float) -> String:
	var cuts: Array = (ViewConfig.value("market_demand", {}) as Dictionary).get("steps", [])
	for c: Dictionary in cuts:
		if d < float(c.get("below", 99.0)):
			return SimQuery.t_("ui.market.demand." + str(c.get("word", "")))
	return ""


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


## The errand's surcharge rate at this stall (H12 Patrón: the cattle fair's animals walk there for nothing).
func _errand_rate() -> float:
	var sdef: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	return float(sdef.get("errand_surcharge", sim.catalog.market.get("errand", {}).get("surcharge", 0.2)))
