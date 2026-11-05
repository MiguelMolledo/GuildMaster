class_name CityScreen
extends MenuScreen
## The page of a city away from home (docs/gdd/09b_region.md §9b.5): opened when the traveller arrives (or from its
## card on the region map). On the paper of the page kit: the city's illustration (VisualPaths.city_art, a visible
## placeholder until its art lands), who rules, the family's reputation there and the tariff it pays (0 with an
## exemption); and three tabs: Mercado (every traded item: buy and sell prices there, what the traveller carries,
## Comprar / Vender one unit, ×5 with Shift), Encargos (the city's offers to accept, the accepted ones to deliver) and
## Tratados (the three kinds: what each asks and gives, signed or the button to sign, with the item for exclusivity
## and quota). At the foot: the region map and «Volver a casa».
## The clock keeps running (the traveller is there): the page refreshes twice a second. Orders through `order_sink`
## (Game.give). Reads the state; nothing of its own is saved.

signal map_requested

const TABS: Array[String] = ["market", "board", "treaties"]
const PANEL_SIZE := Vector2(720, 436)   # under the HUD's top bar (its clock stays usable)

var game: Node = null
var sim: Sim = null
var actor: String = ""
var city: String = ""
var tab: String = "market"
var order_sink: Callable = Callable()
var _bound: bool = false
var _t: float = 0.0
var _sig: String = ""
var _item_pick: Dictionary = {}      # treaty kind -> OptionButton
var _art: TextureRect
var _art_label: Label
var _name: Label
var _facts: VBoxContainer
var _tabs: HBoxContainer
var _body: VBoxContainer
var _foot: HBoxContainer


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	if game == null and is_inside_tree():
		game = get_node_or_null("/root/Game")
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the HUD's clock (pause, speeds) stays usable around the page
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := page_panel(PANEL_SIZE)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var art_box := Control.new()
	art_box.custom_minimum_size = Vector2(240, 135)
	head.add_child(art_box)
	_art = TextureRect.new()
	_art.name = "Art"
	_art.size = Vector2(240, 135)
	_art.stretch_mode = TextureRect.STRETCH_KEEP
	art_box.add_child(_art)
	_art_label = Label.new()
	_art_label.name = "ArtLabel"
	_art_label.theme_type_variation = &"PageSmall"
	_art_label.size = Vector2(240, 135)
	_art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	art_box.add_child(_art_label)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_name = Label.new()
	_name.name = "CityName"
	_name.theme_type_variation = &"PageTitle"
	info.add_child(_name)
	_facts = VBoxContainer.new()
	_facts.name = "Facts"
	_facts.add_theme_constant_override("separation", 1)
	info.add_child(_facts)
	var sep := HSeparator.new()
	sep.theme_type_variation = &"DividerSeparator"
	col.add_child(sep)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	col.add_child(_tabs)
	for t: String in TABS:
		var b := Button.new()
		b.name = "Tab_" + t
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			tab = t
			_sig = ""
			_rebuild())
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, 170)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)
	_foot = HBoxContainer.new()
	_foot.name = "Foot"
	_foot.alignment = BoxContainer.ALIGNMENT_END
	_foot.add_theme_constant_override("separation", 6)
	col.add_child(_foot)
	var map_b := Button.new()
	map_b.name = "MapButton"
	map_b.pressed.connect(func() -> void: map_requested.emit())
	_foot.add_child(map_b)
	var home_b := Button.new()
	home_b.name = "ReturnButton"
	home_b.theme_type_variation = &"PrimaryButton"
	home_b.pressed.connect(func() -> void:
		_give({"type": "return", "actor": actor})
		back_requested.emit())
	_foot.add_child(home_b)
	var back := Button.new()
	back.name = "BackButton"
	back.pressed.connect(func() -> void: back_requested.emit())
	_foot.add_child(back)


## A panel on the page kit's paper (its safe area as margins), or the theme's parchment without the kit.
static func page_panel(size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = size
	if PageKit.has("page_bg"):
		var v := PageKit.variant("page_bg")
		var st := PageKit.page_style(v)
		var m := PageKit.safe_margins(v)
		for side: String in ["left", "top", "right", "bottom"]:
			st.set("content_margin_" + side, float(m.get(side, 12)))
		panel.add_theme_stylebox_override("panel", st)
	else:
		panel.theme_type_variation = &"ParchmentPanel"
	return panel


func show_city(c: String, who: String) -> void:
	city = c
	actor = who
	_sig = ""
	open()


func _refresh() -> void:
	_bind()
	if sim == null and game != null:
		sim = game.get("sim") as Sim
	_rebuild()


func default_focus() -> Control:
	return _foot.get_node("BackButton") as Control


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		_rebuild()


func _give(o: Dictionary) -> void:
	if order_sink.is_valid():
		order_sink.call(o)
	elif game != null and game.has_method("give"):
		game.call("give", o)
	if OS.is_debug_build():
		print("[CityScreen] orden %s" % [o])
	_sig = ""


static func _tr(key: String) -> String:
	return SimQuery.t_(key)


func _fam() -> String:
	return str(sim.state.characters.get(actor, {}).get("family", "")) if sim != null else ""


## What the page shows now, as text: it is rebuilt only when it changes (prices, gold, the inventory, the board).
func _signature() -> String:
	var st := sim.state
	var fam := _fam()
	return "%s|%s|%s|%s|%d|%s|%s|%s|%s" % [city, actor, tab, Travel.in_city(st, actor), Money.gold(st, fam),
		JSON.stringify(st.characters.get(actor, {}).get("inventory", {})), JSON.stringify(Region.city(sim, city)),
		JSON.stringify(st.region.get("contracts", [])), JSON.stringify(st.region.get("treaties", []))]


func _rebuild() -> void:
	if sim == null or city == "":
		return
	var sig := _signature()
	if sig == _sig or UiFeel.hold_rebuild(self):
		return
	_sig = sig
	var s := Region.settlement(sim, city)
	var fam := _fam()
	var tex := VisualPaths.city_art(city)
	_art.texture = tex
	_art_label.text = _tr(str(s.get("name_key", city))) if VisualPaths.is_placeholder(tex) else ""
	_name.text = _tr(str(s.get("name_key", city)))
	MenuKit.clear(_facts)
	_fact(_tr("region.kind." + str(s.get("kind", ""))), null)
	_fact("%s: %s" % [_tr("ui.region.rulers"), _tr(str(s.get("rulers", "")))], null)
	_fact(_tr("ui.city.reputation") % Region.reputation(sim, city, fam), VisualPaths.region_icon("city_reputation"))
	var tar := Region.tariff(sim, city, fam)
	_fact(_tr("ui.city.tariff") % roundi(tar * 100.0) if tar > 0.0 else _tr("ui.city.tariff_none"),
		VisualPaths.region_icon("tariff"))
	_fact(_tr("ui.city.gold") % Money.gold(sim.state, fam), null)
	for line: String in SimQuery.city_feast_lines(sim, city):  # fiestas (4.25.6): its patron feast and its fair
		_fact(line, null)
	for b: Node in _tabs.get_children():
		var t := str(b.name).trim_prefix("Tab_")
		(b as Button).text = _tr("ui.city.tab." + t)
		(b as Button).set_pressed_no_signal(t == tab)
	var here := Travel.in_city(sim.state, actor) == city
	(_foot.get_node("MapButton") as Button).text = _tr("ui.city.map")
	var rb := _foot.get_node("ReturnButton") as Button
	rb.text = _tr("ui.region.return")
	var why := Travel.can_travel(sim, actor, Region.home(sim)) if here else "not_in_city"
	rb.disabled = why != ""
	rb.tooltip_text = SimQuery.reason_text(why) if why != "" else ""
	(_foot.get_node("BackButton") as Button).text = _tr("ui.city.close")
	MenuKit.clear(_body)
	match tab:
		"market":
			_build_market(here)
		"board":
			_build_board(here)
		"treaties":
			_build_treaties(here)


func _fact(text: String, icon: Texture2D) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if icon != null:
		var r := TextureRect.new()
		r.texture = icon
		r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(r)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PageInk"
	row.add_child(l)
	_facts.add_child(row)


func _row(cells: Array, widths: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i: int in cells.size():
		var c: Variant = cells[i]
		var n: Control
		if c is Control:
			n = c
		else:
			var l := Label.new()
			l.text = str(c)
			l.theme_type_variation = &"PageInk"
			l.clip_text = true
			n = l
		n.custom_minimum_size.x = float(widths[i]) if i < widths.size() else 0.0
		row.add_child(n)
	_body.add_child(row)
	return row


func _btn(text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = why != ""
	b.tooltip_text = SimQuery.reason_text(why) if why != "" else ""
	b.pressed.connect(action)
	return b


func _build_market(here: bool) -> void:
	var st := sim.state
	var fam := _fam()
	var inv: Dictionary = st.characters.get(actor, {}).get("inventory", {})
	var tar := Region.tariff(sim, city, fam)
	_row([_tr("ui.city.col_item"), _tr("ui.city.col_buy"), _tr("ui.city.col_sell"), _tr("ui.city.col_have"), "", ""],
		[200, 70, 90, 60, 90, 90])
	for item: String in Region.traded_items(sim):
		var buy := Region.price(sim, city, item, Inventory.NORMAL, "buy")
		var sell := Region.price(sim, city, item, Inventory.NORMAL, "sell")
		var net := sell - roundi(float(sell) * tar)
		var q := Treaties.quota_of(sim, city, fam, item)
		var sell_text := str(net)
		if not q.is_empty() and int(q["delivered"]) < int(q["qty"]):
			sell_text = _tr("ui.city.quota_price") % int(q["price"])
		var have := Inventory.count(inv, item, Inventory.NORMAL)
		var why_buy := "" if here else "not_in_city"
		if why_buy == "" and not Money.can_pay(st, fam, buy):
			why_buy = "not_enough_gold"
		elif why_buy == "" and not Inventory.can_add(inv, sim.catalog, item, Inventory.NORMAL, 1):
			why_buy = "too_heavy"
		var why_sell := "" if here else "not_in_city"
		if why_sell == "" and have <= 0:
			why_sell = "not_enough"
		var it := item
		var row := _row([SimQuery.item_name(sim.catalog, item), str(buy), sell_text, str(have),
			_btn(_tr("ui.city.buy"), why_buy, func() -> void:
				_give({"type": "city_buy", "actor": actor, "item": it, "qty": _qty(99)})),
			_btn(_tr("ui.city.sell"), why_sell, func() -> void:
				_give({"type": "city_sell", "actor": actor, "item": it, "quality": 0, "qty": _qty(have)}))],
			[200, 70, 90, 60, 90, 90])
		row.name = "Item_" + item
		var icon := UiIcons.item_rect(item)
		if icon != null:
			row.add_child(icon)
			row.move_child(icon, 0)


## One unit, or 5 with Shift held (never more than `max`).
func _qty(max: int) -> int:
	return mini(5 if Input.is_key_pressed(KEY_SHIFT) else 1, maxi(1, max))


func _build_board(here: bool) -> void:
	var st := sim.state
	var fam := _fam()
	var inv: Dictionary = st.characters.get(actor, {}).get("inventory", {})
	_section(_tr("ui.city.offers"))
	var board: Array = Region.city(sim, city).get("board", [])
	if board.is_empty():
		_row([_tr("ui.city.no_offers")], [600])
	for off: Dictionary in board:
		var id := str(off["id"])
		_row([_tr("ui.city.offer") % [SimQuery.item_name(sim.catalog, str(off["item"])), int(off["qty"]),
			int(off["reward"]), int(off["days"])], _btn(_tr("ui.city.accept"), "" if here else "not_in_city",
			func() -> void: _give({"type": "city_accept", "actor": actor, "contract": id}))], [480, 110])
	_section(_tr("ui.city.accepted"))
	var any := false
	for a: Dictionary in st.region.get("contracts", []):
		if str(a["family"]) != fam or str(a["city"]) != city:
			continue
		any = true
		var id := str(a["id"])
		var why := "" if here else "not_in_city"
		if why == "" and Inventory.count(inv, str(a["item"])) < int(a["qty"]):
			why = "not_enough"
		var left := maxi(0, int(a["due"]) - int(st.clock["minute"]))
		_row([_tr("ui.city.accepted_line") % [SimQuery.item_name(sim.catalog, str(a["item"])), int(a["qty"]),
			int(a["reward"]), ceili(float(left) / 60.0)], _btn(_tr("ui.city.deliver"), why,
			func() -> void: _give({"type": "city_deliver", "actor": actor, "contract": id}))], [480, 110])
	if not any:
		_row([_tr("ui.city.no_accepted")], [600])


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PageInkBold"
	_body.add_child(l)


func _build_treaties(here: bool) -> void:
	var fam := _fam()
	var kinds: Dictionary = sim.catalog.trade.get("treaties", {}).get("kinds", {})
	var dear := CityTrade.dear_items(sim, city)
	_item_pick = {}
	for kind: String in ["exemption", "exclusivity", "quota"]:
		var k: Dictionary = kinds.get(kind, {})
		var tname := _tr("treaty." + kind)
		_section("%s · %s" % [tname.left(1).to_upper() + tname.substr(1), _tr("ui.city.treaty_" + kind)])
		_row([_tr("ui.city.treaty_needs") % [SimQuery.title_name(str(k.get("title", ""))), int(k.get("reputation", 0)),
			int(k.get("fee", 0)), int(k.get("seasons", 0))]], [600])
		var signed: Array = []
		for t: Dictionary in Treaties.in_force(sim):
			if str(t["kind"]) == kind and str(t["city"]) == city and (str(t["family"]) == fam or (str(t["scope"]) == "town")):
				signed.append(t)
		for t: Dictionary in signed:
			var what := _tr("ui.city.treaty_signed") % SimQuery.t_("ui.city.scope_" + str(t["scope"]))
			if str(t.get("item", "")) != "":
				what += " · " + SimQuery.item_name(sim.catalog, str(t["item"]))
			if kind == "quota":
				what += " · " + _tr("ui.city.quota_left") % [int(t["delivered"]), int(t["qty"])]
			var tid := str(t["id"])
			var cancel := _btn(_tr("ui.city.cancel"), "" if str(t["family"]) == fam else "not_the_head", func() -> void:
				_give({"type": "cancel_treaty", "actor": actor, "treaty": tid}))
			_row([what, cancel], [480, 110])
		var cells: Array = []
		var pick: OptionButton = null
		if kind in ["exclusivity", "quota"]:
			pick = OptionButton.new()
			for it: String in dear:
				pick.add_item(SimQuery.item_name(sim.catalog, it))
				pick.set_item_metadata(pick.item_count - 1, it)
			_item_pick[kind] = pick
			cells.append(pick)
		var item0 := str(pick.get_item_metadata(0)) if pick != null and pick.item_count > 0 else ""
		var why := Treaties.can_sign(sim, fam, city, kind, item0) if here else "not_in_city"
		if why == "" and not Treaties._leads(sim, fam, actor):
			why = "not_the_head"
		var kk := kind
		var sign := _btn(_tr("ui.city.sign") % int(k.get("fee", 0)), why, func() -> void:
			var o := {"type": "sign_treaty", "actor": actor, "kind": kk}
			if _item_pick.has(kk):
				var p: OptionButton = _item_pick[kk]
				o["item"] = str(p.get_item_metadata(maxi(0, p.selected)))
			_give(o))
		sign.icon = VisualPaths.region_icon("treaty")
		cells.append(sign)
		_row(cells, [200, 200] if pick != null else [200])

