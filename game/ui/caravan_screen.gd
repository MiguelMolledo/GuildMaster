class_name CaravanScreen
extends MenuScreen
## Caravans (docs/gdd/09b_region.md §9b.5, O-R4 c), opened from the region map: the family's carts (buy one: price and
## daily upkeep), the caravans on their way (where, what they sold) and a new one: the city, the building whose storage
## it loads, the carter (one of the family's employees at home), the cargo (each stack of that storage with how many
## and the minimum unit price: below it, it does not sell), up to three lines to buy there (item, how many, the
## maximum unit price) and the escort. «Enviar» says why not while it cannot (Caravans.can_send). Orders through
## `order_sink` (Game.give); the clock keeps running.

const PANEL_SIZE := Vector2(720, 436)
const BUY_LINES: int = 3

var game: Node = null
var sim: Sim = null
var actor: String = ""
var order_sink: Callable = Callable()
var _bound: bool = false
var _t: float = 0.0
var _sig: String = ""
var _city: OptionButton
var _building: OptionButton
var _driver: OptionButton
var _escort: CheckBox
var _cargo: Array = []    # [{item, quality, qty: SpinBox, min: SpinBox}]
var _buy: Array = []      # [{item: OptionButton, qty: SpinBox, max: SpinBox}]
var _col: VBoxContainer
var _carts: VBoxContainer
var _form: VBoxContainer
var _send: Button


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	if game == null and is_inside_tree():
		game = get_node_or_null("/root/Game")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := CityScreen.page_panel(PANEL_SIZE)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_col = VBoxContainer.new()
	_col.name = "Column"
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 4)
	scroll.add_child(_col)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"PageTitle"
	_col.add_child(title)
	_carts = VBoxContainer.new()
	_carts.name = "Carts"
	_col.add_child(_carts)
	var sep := HSeparator.new()
	sep.theme_type_variation = &"DividerSeparator"
	_col.add_child(sep)
	_form = VBoxContainer.new()
	_form.name = "Form"
	_form.add_theme_constant_override("separation", 3)
	_col.add_child(_form)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.alignment = BoxContainer.ALIGNMENT_END
	_col.add_child(foot)
	_send = Button.new()
	_send.name = "SendButton"
	_send.theme_type_variation = &"PrimaryButton"
	_send.pressed.connect(_on_send)
	foot.add_child(_send)
	var back := Button.new()
	back.name = "BackButton"
	back.pressed.connect(func() -> void: back_requested.emit())
	foot.add_child(back)


func _refresh() -> void:
	_bind()
	if sim == null and game != null:
		sim = game.get("sim") as Sim
	if sim != null and (actor == "" or not sim.state.characters.has(actor)):
		actor = Kin.head(sim.state, SimQuery.player_family(sim.state))
	_sig = ""
	_build_form()
	_rebuild()


func default_focus() -> Control:
	return _col.get_node("Foot/BackButton") as Control


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		_rebuild()
		_update_send()


static func _tr(key: String) -> String:
	return SimQuery.t_(key)


func _fam() -> String:
	return str(sim.state.characters.get(actor, {}).get("family", "")) if sim != null else ""


func _give(o: Dictionary) -> void:
	if order_sink.is_valid():
		order_sink.call(o)
	elif game != null and game.has_method("give"):
		game.call("give", o)
	if OS.is_debug_build():
		print("[CaravanScreen] orden %s" % [o])
	_sig = ""


## The carts and the caravans on their way (rebuilt when they change).
func _rebuild() -> void:
	if sim == null:
		return
	var fam := _fam()
	var mine: Array = (sim.state.region.get("caravans", []) as Array).filter(func(c: Dictionary) -> bool:
		return str(c["family"]) == fam)
	var sig := "%d|%d|%s" % [Caravans.carts(sim, fam), Money.gold(sim.state, fam), JSON.stringify(mine.map(
		func(c: Dictionary) -> String: return "%s|%s|%s|%d" % [c["id"], c["state"], c["at"], int(c["leg"])]))]
	if sig == _sig:
		return
	_sig = sig
	(_col.get_node("Title") as Label).text = _tr("ui.caravan.title")
	MenuKit.clear(_carts)
	var cfg: Dictionary = sim.catalog.trade.get("caravans", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = VisualPaths.region_icon("caravan")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	row.add_child(_label(_tr("ui.caravan.carts") % [Caravans.carts(sim, fam), Caravans.carts(sim, fam)
		- Caravans.busy_carts(sim, fam), int(cfg.get("cart_upkeep", 2))]))
	var buy := Button.new()
	buy.name = "BuyCartButton"
	buy.text = _tr("ui.caravan.buy_cart") % int(cfg.get("cart_price", 120))
	var why := ""
	if Caravans.carts(sim, fam) >= int(cfg.get("max_carts", 2)):
		why = "too_many_carts"
	elif Travel.unlock_reason(sim, fam) != "":
		why = Travel.unlock_reason(sim, fam)
	elif not Money.can_pay(sim.state, fam, int(cfg.get("cart_price", 120))):
		why = "not_enough_gold"
	buy.disabled = why != ""
	buy.tooltip_text = SimQuery.reason_text(why) if why != "" else ""
	buy.pressed.connect(func() -> void: _give({"type": "buy_cart", "actor": actor}))
	row.add_child(buy)
	_carts.add_child(row)
	for c: Dictionary in mine:
		var p := Caravans.progress(sim, c)
		var where := ""
		match str(p["state"]):
			"road":
				where = _tr("ui.caravan.on_road") % [_city_name(str(p["next"])), roundi(float(p["progress"]) * 100.0)]
			"city":
				where = _tr("ui.caravan.in_city") % _city_name(str(c["city"]))
			"waiting":
				where = _tr("ui.caravan.waiting")
			_:
				where = _tr("ui.caravan.unloading")
		_carts.add_child(_label("· %s → %s · %s · %s" % [_tr("ui.caravan.dir_" + str(c["dir"])), _city_name(str(c["city"])),
			where, _tr("ui.caravan.sold") % int(c.get("sold", 0))]))


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PageInk"
	return l


func _city_name(id: String) -> String:
	return _tr(str(Region.settlement(sim, id).get("name_key", id)))


func _spin(max_value: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = max_value
	s.value = value
	s.custom_minimum_size.x = 70
	s.value_changed.connect(func(_v: float) -> void: _update_send())
	return s


## The form of a new caravan (built on opening and when the building changes).
func _build_form() -> void:
	MenuKit.clear(_form)
	_cargo = []
	_buy = []
	if sim == null:
		return
	var st := sim.state
	var fam := _fam()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	_form.add_child(top)
	top.add_child(_label(_tr("ui.caravan.to")))
	_city = OptionButton.new()
	_city.name = "City"
	for c: String in Region._sorted_keys(Region.ensure(sim)["cities"]):
		_city.add_item(_city_name(c))
		_city.set_item_metadata(_city.item_count - 1, c)
	_city.item_selected.connect(func(_i: int) -> void: _update_send())
	top.add_child(_city)
	top.add_child(_label(_tr("ui.caravan.from")))
	var keep := str(_building.get_item_metadata(_building.selected)) if _building != null and _building.item_count > 0 \
		and _building.selected >= 0 else ""
	_building = OptionButton.new()
	_building.name = "Building"
	for b: String in Region._sorted_keys(st.buildings):
		var bd: Dictionary = st.buildings[b]
		if str(bd.get("owner", "")) == fam and bd.get("inventory") is Dictionary and str(bd.get("type", "")) != "house":
			_building.add_item(SimQuery.building_label(st, sim.catalog, b))
			_building.set_item_metadata(_building.item_count - 1, b)
			if b == keep:
				_building.select(_building.item_count - 1)
	_building.item_selected.connect(func(_i: int) -> void: _build_form())
	top.add_child(_building)
	top.add_child(_label(_tr("ui.caravan.driver")))
	_driver = OptionButton.new()
	_driver.name = "Driver"
	for c: String in Region._sorted_keys(st.characters):
		var job: Variant = st.characters[c].get("job")
		if job is Dictionary and str(st.buildings.get(str(job.get("building", "")), {}).get("owner", "")) == fam \
				and Kin.alive(st, c) and not Region.is_away(st, c):
			_driver.add_item(str(st.characters[c].get("name", c)))
			_driver.set_item_metadata(_driver.item_count - 1, c)
	_driver.item_selected.connect(func(_i: int) -> void: _update_send())
	top.add_child(_driver)
	_form.add_child(_section(_tr("ui.caravan.cargo")))
	var bld := str(_building.get_item_metadata(_building.selected)) if _building.item_count > 0 else ""
	var inv: Dictionary = st.buildings.get(bld, {}).get("inventory", {})
	for s: Dictionary in inv.get("stacks", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name := SimQuery.item_label(sim.catalog, str(s["item"]), int(s["quality"]))
		var nl := _label(name)
		nl.custom_minimum_size.x = 200
		row.add_child(nl)
		var q := _spin(int(s["qty"]), 0)
		row.add_child(q)
		row.add_child(_label(_tr("ui.caravan.min_price")))
		var m := _spin(999, Market.price(sim, str(s["item"]), int(s["quality"]), "sell"))
		row.add_child(m)
		_form.add_child(row)
		_cargo.append({"item": str(s["item"]), "quality": int(s["quality"]), "qty": q, "min": m})
	if _cargo.is_empty():
		_form.add_child(_label(_tr("ui.caravan.nothing")))
	_form.add_child(_section(_tr("ui.caravan.shopping")))
	var items := Region.traded_items(sim)
	for i: int in BUY_LINES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pick := OptionButton.new()
		pick.add_item("—")
		pick.set_item_metadata(0, "")
		for it: String in items:
			pick.add_item(SimQuery.item_name(sim.catalog, it))
			pick.set_item_metadata(pick.item_count - 1, it)
		pick.custom_minimum_size.x = 200
		pick.item_selected.connect(func(_i: int) -> void: _update_send())
		row.add_child(pick)
		var q := _spin(20, 0)
		row.add_child(q)
		row.add_child(_label(_tr("ui.caravan.max_price")))
		var m := _spin(999, 0)
		row.add_child(m)
		_form.add_child(row)
		_buy.append({"item": pick, "qty": q, "max": m})
	_escort = CheckBox.new()
	_escort.name = "Escort"
	_escort.text = _tr("ui.caravan.escort") % int(sim.catalog.trade.get("travel", {}).get("escort_cost", 20))
	_escort.toggled.connect(func(_b: bool) -> void: _update_send())
	_form.add_child(_escort)
	(_col.get_node("Foot/BackButton") as Button).text = _tr("ui.menu.back")
	_update_send()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PageInkBold"
	return l


## The caravan_send order the form describes now.
func order() -> Dictionary:
	var o := {"type": "caravan_send", "actor": actor, "cargo": [], "buy": [], "escort": _escort.button_pressed}
	o["city"] = str(_city.get_item_metadata(_city.selected)) if _city.item_count > 0 and _city.selected >= 0 else ""
	o["building"] = str(_building.get_item_metadata(_building.selected)) if _building.item_count > 0 \
		and _building.selected >= 0 else ""
	o["driver"] = str(_driver.get_item_metadata(_driver.selected)) if _driver.item_count > 0 and _driver.selected >= 0 \
		else ""
	for l: Dictionary in _cargo:
		if int((l["qty"] as SpinBox).value) > 0:
			(o["cargo"] as Array).append({"item": l["item"], "quality": l["quality"], "qty": int((l["qty"] as SpinBox).value),
				"min_price": int((l["min"] as SpinBox).value)})
	for l: Dictionary in _buy:
		var p: OptionButton = l["item"]
		var it := str(p.get_item_metadata(maxi(0, p.selected)))
		if it != "" and int((l["qty"] as SpinBox).value) > 0:
			(o["buy"] as Array).append({"item": it, "qty": int((l["qty"] as SpinBox).value),
				"max_price": int((l["max"] as SpinBox).value)})
	return o


func _update_send() -> void:
	if sim == null or _city == null:
		return
	var why := Caravans.can_send(sim, order())
	_send.text = _tr("ui.caravan.send")
	_send.disabled = why != ""
	_send.tooltip_text = SimQuery.reason_text(why) if why != "" else ""


func _on_send() -> void:
	var o := order()
	_give(o)
	if OS.is_debug_build():
		print("[CaravanScreen] envía %s" % [o])
	_build_form.call_deferred()
