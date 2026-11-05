class_name InnPanel
extends PanelContainer
## The Taberna-Posada's panel (docs/gdd/04f_vida_y_fiestas.md §4.27; the wide zone of its interior), four tabs:
##  Clientela: each group of data/inn/clientele.json, how many are expected tonight, how many came, were served and
##    left last night, and, when a group does not come, why (the reasons of InnClientele: «fama 1 de 3», «no hay vino
##    bueno»...), as in Wartales' Clientele.
##  Carta: every dish, on the menu or not (the slots), its stock, its price (− / +, 0.5× to 2×), the special of the
##    house and the dishes of the season; the bed's price.
##  Habitaciones: each bed and its state; a dirty one can be made by whoever of the family is inside.
##  Turno: the last night's summary and the history of the nights.
##  Mesa: the gaming table (InnGames): dice and cards with the regulars at a stake, the traveller's offer of tonight,
##    the games played tonight; without the licence, the warning of the constable. A game opens the games' screen
##    (App.open_game, or game_sink in the tests).
## The licence of the gaming house in the footer. Reads the state, gives orders (inn_*) through order_sink.

signal closed

const TABS: Array[String] = ["clientele", "menu", "rooms", "turn", "games"]

var order_sink: Callable = Callable()
var game_sink: Callable = Callable()   # opens a game's screen with a request (default: App.open_game)
var stake: int = 10
var sim: Sim = null
var building: String = ""
var actor_id: String = ""
var tab: String = "clientele"
var _minute: int = -1
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	for t: String in TABS:
		var b := get_node("%Tab" + t.to_pascal_case()) as Button
		b.pressed.connect(show_tab.bind(t))
	(%LicenseButton as Button).pressed.connect(func() -> void:
		_give({"type": "inn_buy_license", "actor": actor_id, "building": building}))


func setup(s: Sim, bld: String, who: String) -> void:
	_bind()
	sim = s
	building = bld
	actor_id = _manager(who)
	(%Title as Label).text = SimQuery.building_label(s.state, s.catalog, bld)
	for t: String in TABS:
		(get_node("%Tab" + t.to_pascal_case()) as Button).text = SimQuery.t_("ui.inn.tab." + t)
	refresh()


func set_actor(who: String) -> void:
	actor_id = _manager(who)


## Who gives the management orders: `who` if it is of the owner family, else the owner family's head.
func _manager(who: String) -> String:
	if sim == null:
		return who
	if who != "" and Buildings.owns(sim.state, who, building):
		return who
	var fam := str(sim.state.buildings.get(building, {}).get("owner", ""))
	return str(sim.state.families.get(fam, {}).get("head", who))


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_tab(t: String) -> void:
	tab = t
	ViewConfig.info("InnPanel", "tab %s (building=%s)" % [t, building])
	refresh()


func _process(_d: float) -> void:
	if visible and sim != null and int(sim.state.clock["minute"]) != _minute:
		_minute = int(sim.state.clock["minute"])
		if _minute % 5 == 0:
			refresh()


func refresh() -> void:
	if sim == null or not sim.state.buildings.has(building):
		return
	for t: String in TABS:
		(get_node("%Tab" + t.to_pascal_case()) as Button).set_pressed_no_signal(t == tab)
	(%Figures as Label).text = figures_line()
	var body := %Body as VBoxContainer
	for c: Node in body.get_children():
		body.remove_child(c)
		c.queue_free()
	match tab:
		"clientele":
			_build_clientele(body)
		"menu":
			_build_menu(body)
		"rooms":
			_build_rooms(body)
		"turn":
			_build_turn(body)
		"games":
			_build_games(body)
	var lic := %LicenseButton as Button
	var lc: Dictionary = Inn.rules(sim).get("license", {})
	if Inn.licensed(sim, building):
		lic.text = SimQuery.t_("ui.inn.license_until") % (int(Inn.state_of(sim, building).get("license_until", 0)) + 1)
		lic.disabled = true
	else:
		lic.text = SimQuery.t_("ui.inn.license_buy") % int(lc.get("cost", 60))
		lic.disabled = not Money.can_pay(sim.state, str(sim.state.buildings[building].get("owner", "")), int(lc.get("cost", 60)))
	lic.tooltip_text = SimQuery.t_("ui.inn.license_tip")
	(%Hint as Label).text = SimQuery.t_("ui.inn.hint." + tab)


## «Fama 2,4 (★★☆☆☆) · Ambiente 3 · 12 plazas · 8 camas · Abierta: 9 dentro» (or when it opens).
func figures_line() -> String:
	var f := Inn.fame(sim, building)
	var stars := ""
	for i: int in 5:
		stars += "★" if i < Inn.fame_level(sim, building) else "☆"
	var open := SimQuery.t_("ui.inn.open_now") % Inn.guests(sim, building).size() if Inn.is_open(sim, building) \
		else SimQuery.t_("ui.inn.closed_now") % _hhmm(int(Inn.turn_window(sim, int(sim.state.clock["minute"]))[0]))
	return SimQuery.t_("ui.inn.figures") % [SimQuery._num(snappedf(f, 0.1)), stars, Inn.ambience(sim, building),
		Inn.seats(sim, building), Inn.bed_count(sim, building), open]


static func _hhmm(minute: int) -> String:
	return "%02d:%02d" % [Clock.hour(minute), Clock.minute_of_day(minute) % 60]


func _label(text: String, variation: StringName = &"", color: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	if variation != &"":
		l.theme_type_variation = variation
	if color != "":
		l.add_theme_color_override("font_color", Color.html(color))
	return l


# --- Clientela ------------------------------------------------------------------------------------------------------

## The rows of the Clientela tab: [{group, name, expected, came, served, left, reasons: [text]}] (tests read it).
func clientele_rows() -> Array:
	var inn := Inn.state_of(sim, building)
	var night: Dictionary = inn.get("night", {})
	var outlook: Dictionary = night.get("outlook", {}) if not night.is_empty() else InnClientele.outlook(sim, building)
	var last: Dictionary = inn.get("last_turn", {}).get("by_group", {})
	var now_groups: Dictionary = night.get("stats", {}).get("by_group", {}) if not night.is_empty() else {}
	var rows: Array = []
	for g: Variant in sim.catalog.inn.get("clientele", {}).get("order", []):
		var o: Dictionary = outlook.get(g, {})
		var src: Dictionary = now_groups.get(g, last.get(g, {}))
		var reasons: Array = []
		for r: Dictionary in o.get("reasons", []):
			if str(r.get("key", "")) == "nobody_in_town" and int(src.get("came", 0)) > 0:
				continue  # the outlook is the opening's: one arrived later (a visitor that found a bed)
			reasons.append(reason_text(r))
		rows.append({"group": str(g), "name": SimQuery.t_("inn.group." + str(g)), "expected": float(o.get("expected", 0.0)),
			"came": int(src.get("came", 0)), "served": int(src.get("served", 0)), "left": int(src.get("left", 0)),
			"reasons": reasons})
	return rows


## A reason of InnClientele as text: ui.inn.why.<key> with its args (dish ids as names).
func reason_text(r: Dictionary) -> String:
	var key := "ui.inn.why." + str(r.get("key", ""))
	var args: Array = (r.get("args", []) as Array).duplicate()
	for i: int in args.size():
		if args[i] is String and not Inn.dish(sim, str(args[i])).is_empty():
			args[i] = SimQuery.t_("item." + str(Inn.dish(sim, str(args[i])).get("item", args[i])))
	var t := SimQuery.t_(key)
	return t % args if not args.is_empty() and t.count("%") >= args.size() else t


func _build_clientele(body: VBoxContainer) -> void:
	var night_on := Inn.is_open(sim, building)
	body.add_child(_label(SimQuery.t_("ui.inn.clientele_now" if night_on else "ui.inn.clientele_last"), &"DimLabel"))
	for r: Dictionary in clientele_rows():
		var line := SimQuery.t_("ui.inn.group_line") % [str(r["name"]), int(r["came"]), int(r["served"]), int(r["left"])]
		var ok := (r["reasons"] as Array).is_empty()
		if ok:
			line += "  ·  " + SimQuery.t_("ui.inn.expected") % SimQuery._num(snappedf(float(r["expected"]), 0.5))
		body.add_child(_label(line, &"BoldLabel", "" if ok else "#c87a4a"))
		if not ok:
			body.add_child(_label("    " + SimQuery.t_("ui.inn.why_not") % ", ".join(PackedStringArray(r["reasons"])),
				&"SmallLabel", "#e0a070"))


# --- Carta ----------------------------------------------------------------------------------------------------------

func _build_menu(body: VBoxContainer) -> void:
	var inn := Inn.state_of(sim, building)
	var menu: Array = inn.get("menu", [])
	body.add_child(_label(SimQuery.t_("ui.inn.menu_slots") % [menu.size(), Inn.menu_slots(sim, building)], &"DimLabel"))
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	for d: String in Inn.dishes(sim):
		var def := Inn.dish(sim, d)
		var row := HBoxContainer.new()
		row.name = "Dish_" + d
		var on := CheckBox.new()
		on.button_pressed = d in menu
		on.focus_mode = Control.FOCUS_NONE
		on.toggled.connect(func(v: bool) -> void: _toggle_dish(d, v))
		row.add_child(on)
		var ic := TextureRect.new()
		ic.texture = VisualPaths.inn_dish_icon(d, bool(def.get("cellar", false)) and Inn.wine_quality(sim, building) > 0)
		if ic.texture == null:
			ic.texture = VisualPaths.icon_small(str(def.get("item", d)))
		ic.custom_minimum_size = Vector2(16, 16)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(ic)
		var dname := SimQuery.t_("item." + str(def.get("item", d)))
		if str(def.get("season", "")) != "":
			dname += " · " + SimQuery.t_("ui.inn.season." + str(def["season"])) + ("!" if str(def["season"]) == season else "")
		if str(inn.get("special", "")) == d:
			dname = "★ " + dname
		var l := _label(SimQuery.t_("ui.inn.dish_line") % [dname, Inn.stock(sim, building, d), Inn.dish_price(sim, building, d, 0)])
		l.custom_minimum_size = Vector2(170, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_price_button("−", d, -0.1))
		var m := Label.new()
		m.text = "×" + SimQuery._num(Inn.price_mult(sim, building, d))
		row.add_child(m)
		row.add_child(_price_button("+", d, 0.1))
		var sp := Button.new()
		sp.text = "★"
		sp.tooltip_text = SimQuery.t_("ui.inn.special_tip")
		sp.focus_mode = Control.FOCUS_NONE
		sp.disabled = not d in menu
		sp.pressed.connect(func() -> void:
			_give({"type": "inn_set_special", "actor": actor_id, "building": building,
				"dish": "" if str(inn.get("special", "")) == d else d}))
		row.add_child(sp)
		body.add_child(row)
	var bed := HBoxContainer.new()
	var bl := _label(SimQuery.t_("ui.inn.bed_price") % [Inn.bed_price(sim, building, false)])
	bl.custom_minimum_size = Vector2(196, 0)
	bed.add_child(bl)
	bed.add_child(_price_button("−", "bed", -0.1))
	var bm := Label.new()
	bm.text = "×" + SimQuery._num(float(inn.get("bed_price", 1.0)))
	bed.add_child(bm)
	bed.add_child(_price_button("+", "bed", 0.1))
	body.add_child(bed)


func _price_button(text: String, d: String, step: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		var cur := float(Inn.state_of(sim, building).get("bed_price", 1.0)) if d == "bed" else Inn.price_mult(sim, building, d)
		var rng: Array = sim.catalog.services.get("price_range", [0.5, 2.0])
		var m := clampf(snappedf(cur + step, 0.05), float(rng[0]), float(rng[1]))
		_give({"type": "inn_set_price", "actor": actor_id, "building": building, "dish": d, "mult": m}))
	return b


func _toggle_dish(d: String, on: bool) -> void:
	var menu: Array = (Inn.state_of(sim, building).get("menu", []) as Array).duplicate()
	if on and not d in menu:
		menu.append(d)
	elif not on:
		menu.erase(d)
	_give({"type": "inn_set_menu", "actor": actor_id, "building": building, "dishes": menu})


# --- Habitaciones ---------------------------------------------------------------------------------------------------

func _build_rooms(body: VBoxContainer) -> void:
	var beds: Array = Inn.state_of(sim, building).get("beds", [])
	var good := Upgrades.flag(sim, building, "inn_good_room")
	body.add_child(_label(SimQuery.t_("ui.inn.rooms_line") % [Inn.beds_free(sim, building), beds.size(),
		Inn.bed_price(sim, building, false)], &"DimLabel"))
	for i: int in beds.size():
		var b: Dictionary = beds[i]
		var row := HBoxContainer.new()
		var bname := SimQuery.t_("ui.inn.bed_good" if good and i == 0 else "ui.inn.bed_n") % (i + 1)
		var l := _label("%s · %s" % [bname, SimQuery.t_("ui.inn.bed_state." + str(b.get("state", "made")))])
		l.custom_minimum_size = Vector2(250, 0)
		row.add_child(l)
		if str(b.get("state", "")) == "dirty":
			var mk := Button.new()
			mk.text = SimQuery.t_("ui.inn.make_bed")
			mk.focus_mode = Control.FOCUS_NONE
			mk.pressed.connect(func() -> void:
				var who := _inside_person()
				if who != "":
					_give({"type": "inn_make_bed", "actor": who, "building": building, "bed": i}))
			mk.disabled = _inside_person() == ""
			row.add_child(mk)
		body.add_child(row)


func _inside_person() -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: Variant in ids:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("controlled_by", "")) == "human" and str(ch.get("location", "")) == building:
			return str(id)
	return ""


# --- Turno ----------------------------------------------------------------------------------------------------------

func _build_turn(body: VBoxContainer) -> void:
	var inn := Inn.state_of(sim, building)
	var last: Dictionary = inn.get("last_turn", {})
	if last.is_empty():
		body.add_child(_label(SimQuery.t_("ui.inn.no_turn_yet"), &"DimLabel"))
	else:
		for line: String in InnTurnPage.lines(sim, last):
			body.add_child(_label(line))
	var hist: Array = inn.get("history", [])
	if not hist.is_empty():
		body.add_child(_label(SimQuery.t_("ui.inn.history"), &"BoldLabel"))
		for i: int in range(hist.size() - 1, maxi(-1, hist.size() - 9), -1):
			var h: Dictionary = hist[i]
			body.add_child(_label(SimQuery.t_("ui.inn.history_line") % [int(h["day"]) + 1, int(h["guests"]),
				int(h["income"]) + int(h["tips"]), int(h["beds"]), SimQuery._num(snappedf(float(h["fame"]), 0.1))], &"SmallLabel"))


# --- Mesa -----------------------------------------------------------------------------------------------------------

## The name of a player reference (a character of the town or a preset of data/games.json).
func player_name(ref: String) -> String:
	if ref.begins_with("preset:"):
		var pid := ref.trim_prefix("preset:").get_slice("#", 0)
		return SimQuery.t_(str(sim.catalog.games.get("presets", {}).get(pid, {}).get("name_key", pid)))
	return str(sim.state.characters.get(ref, {}).get("name", ref))


## Who of the family sits at the table (InnGames.player_for).
func table_player() -> String:
	return InnGames.player_for(sim, building, str(sim.state.buildings[building].get("owner", "")))


func _build_games(body: VBoxContainer) -> void:
	var why := InnGames.blocked(sim, building)
	var actor := table_player()
	var fam := str(sim.state.buildings[building].get("owner", ""))
	if why != "":
		body.add_child(_label(SimQuery.t_("ui.inn.games.why." + why), &"DimLabel"))
	else:
		body.add_child(_label(SimQuery.t_("ui.inn.games.sits") % player_name(actor), &"DimLabel"))
	if not Inn.licensed(sim, building) and InnGames.has_table(sim, building):
		body.add_child(_label(SimQuery.t_("ui.inn.games.no_license"), &"SmallLabel", "#e0a070"))
	var stakes := HBoxContainer.new()
	stakes.add_child(_label(SimQuery.t_("ui.inn.games.stake")))
	(stakes.get_child(0) as Label).custom_minimum_size = Vector2(90, 0)
	for v: Variant in sim.catalog.games.get("stakes", [5, 10, 25, 50]):
		var sb := Button.new()
		sb.text = str(v)
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.set_pressed_no_signal(int(v) == stake)
		sb.pressed.connect(func() -> void:
			stake = int(v)
			refresh())
		stakes.add_child(sb)
	body.add_child(stakes)
	var cap := int(sim.catalog.games.get("cap", 50))
	for g: String in InnGames.GAMES:
		var req := InnGames.request(sim, building, actor, g, stake) if why == "" else {}
		var who: PackedStringArray = []
		for ref: Variant in req.get("opponents", []):
			who.append(player_name(str(ref)))
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = SimQuery.t_("ui.inn.games.play") % [SimQuery.t_("games.%s.name" % g),
			", ".join(who) if not who.is_empty() else "—"]
		b.disabled = why != "" or actor == "" or not Money.can_pay(sim.state, fam, Games.max_loss(g, stake, cap))
		b.tooltip_text = SimQuery.t_("games.%s.rules" % g)
		b.pressed.connect(func() -> void: _open_game(InnGames.request(sim, building, table_player(), g, stake)))
		body.add_child(b)
	var offer := InnGames.offer_of(sim, building)
	if not offer.is_empty():
		body.add_child(_label(SimQuery.t_("ui.inn.games.offer") % [player_name("preset:" + str(offer["preset"])),
			SimQuery.t_("games.%s.name" % str(offer["game"])), int(offer["stake"])], &"BoldLabel"))
		var ob := Button.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.text = SimQuery.t_("ui.inn.games.offer_play")
		ob.disabled = actor == "" or not Money.can_pay(sim.state, fam,
			Games.max_loss(str(offer["game"]), int(offer["stake"]), cap))
		ob.pressed.connect(func() -> void: _open_game(InnGames.offer_request(sim, building, table_player())))
		body.add_child(ob)
	var played: Array = Inn.state_of(sim, building).get("night", {}).get("stats", {}).get("games", [])
	if not played.is_empty():
		body.add_child(_label(SimQuery.t_("ui.inn.games.tonight"), &"BoldLabel"))
		for p: Dictionary in played:
			body.add_child(_label(InnTurnPage.game_line(sim, p), &"SmallLabel"))


func _open_game(req: Dictionary) -> void:
	if req.has("reason"):
		ViewConfig.info("InnPanel", "mesa: no se puede jugar (%s)" % req["reason"])
		return
	ViewConfig.info("InnPanel", "mesa: abre %s" % [req])
	if game_sink.is_valid():
		game_sink.call(req)
		return
	var app := get_node_or_null("/root/App")
	if app != null and app.has_method("open_game"):
		app.call("open_game", req)


func _give(o: Dictionary) -> void:
	ViewConfig.info("InnPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	call_deferred("refresh")
