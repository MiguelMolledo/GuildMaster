class_name RegionScreen
extends MenuScreen
## «Mapa de la región» (docs/gdd/09b_region.md §9b.7): the illustrated parchment of the region with its settlements,
## the routes between them (cut ones in red while a world event in force cuts them, data/world/region.json cut_by) and
## their names; hovering or clicking a settlement shows its card (PageCard «card»: kind, size, distance from home,
## specialty, who rules, what is cheap and what pays well, its routes). The distance counts only the routes open now.
## Viajes (09b.5): the card's buttons travel (with or without escort: Travel.can_travel says why not), come back
## home, open the page of the city where the active person is (city_requested) or let the Mayor propose a town
## treaty; «Caravanas» opens the caravans panel (caravans_requested). The family's travellers (its emblem) and carts
## move along their routes while the clock runs; when the active person arrives, city_requested.
## Opened from the pause menu or with R in the HUD (the app); while open the game is paused as it was before on
## closing, unless someone of the family is on the road (then it runs, to watch them). Reads the state and gives the
## orders through `order_sink` (Game.give); saves nothing. Esc closes the card, then the screen (back_requested).

signal city_requested(city: String)
signal caravans_requested

const PAGE_CARD: PackedScene = preload("res://game/ui/page_card.tscn")
const INK := Color("#2a1f14")
const ROAD := Color("#4a2a12")
const CUT := Color("#c85050")
const WAX := Color("#8a2a1e")
const GOLD := Color("#c8a84e")
const PAPER := Color("#d4b896")
const RADIUS := {"capital": 9.0, "villa": 7.0}  # the rest 6
const CARD_GAP: float = 14.0
const IDENTITY_SHADER: Shader = preload("res://game/visuals/characters/identity_swap.gdshader")
const TOKEN_VARIANT: String = "banner"   # the family's token on the map (VisualPaths.region_token: banner | shield)
const CARAVAN_VARIANT: String = "ox"     # the caravan on the map (VisualPaths.region_caravan: ox | cart)
const BOTTOM: float = 46.0          # the card stays above the Back button

var game: Node = null
var sim: Sim = null                 # tests set it; else Game.sim on opening
var actor: String = ""              # who travels (the app sets the HUD's active person; else the family head)
var order_sink: Callable = Callable()  # where the orders go (Game.give; tests: a list)
var home: String = ""
var hours: Dictionary = {}          # settlement -> game hours from home
var cut: Dictionary = {}            # route id -> [event ids in force that cut it]
var selected: String = ""           # the settlement whose card is shown ("" = none)
var pinned: bool = false            # the card was clicked open (it stays when the mouse leaves)
var markers: Dictionary = {}        # settlement -> Button
var _was_paused: bool = false
var _open: bool = false
var _bound: bool = false
var _card: PageCard = null
var _strip: Label = null   # the orders that wait for the clock (PausedOrders)
var _said_left: float = 0.0   # seconds the strip keeps saying what came of them (the council's vote)
var _was_on_road: bool = false      # the actor was on the road at the last frame (arrival -> city_requested)

var _map: TextureRect = null
var _layer: Control = null


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	_map = get_node("%Map") as TextureRect
	_layer = get_node("%Layer") as Control
	if game == null and is_inside_tree():
		game = get_node_or_null("/root/Game")
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())
	_layer.draw.connect(_draw_layer)
	_card = PAGE_CARD.instantiate() as PageCard
	_card.name = "SettlementCard"
	_card.visible = false
	add_child(_card)
	_card.closed.connect(func() -> void:
		selected = ""
		pinned = false
		_layer.queue_redraw())
	_card.button_pressed.connect(_on_card_button)
	(%CaravansButton as Button).pressed.connect(func() -> void: caravans_requested.emit())
	_strip = Label.new()   # verificación E1: the orders given here in pause, until the clock runs
	_strip.name = "PendingStrip"
	_strip.theme_type_variation = &"PageSmall"
	_strip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.position = Vector2(60, 522)   # under the buttons row: the settlement card never reaches it (BOTTOM)
	_strip.size = Vector2(840, 16)
	_strip.visible = false
	add_child(_strip)
	var ev := get_node_or_null("/root/Events") if is_inside_tree() else null
	if ev != null:   # the council's vote on a town treaty given here: said on the map (its card waits under it)
		ev.connect("step_done", func(events: Array) -> void:
			for e: Dictionary in events:
				if str(e.get("type", "")) == "council_voted" and visible and sim != null \
						and str(sim.state.characters.get(str(e.get("actor", "")), {}).get("family", "")) \
						== SimQuery.player_family(sim.state):
					say_council(e))


## Pauses (remembering the pause it found) and shows the map.
func open() -> void:
	_bind()
	if not _open:
		_open = true
		_was_paused = bool(game.get("paused")) if game != null else false
		if sim == null and game != null:
			sim = game.get("sim") as Sim
		if game != null and game.has_method("set_paused") and not _family_on_road():
			game.call("set_paused", true)
	super()


## Hides the map and puts the pause back as it was.
func close() -> void:
	if OS.is_debug_build() and visible:
		print("[RegionScreen] close from: %s" % [get_stack().slice(1, 4).map(func(f: Dictionary) -> String: return "%s:%d" % [f["source"].get_file(), f["line"]])])
	super()
	if _card != null:
		_card.close()
	if _open:
		_open = false
		if game != null and game.has_method("set_paused"):
			game.call("set_paused", _was_paused)


func is_open() -> bool:
	return _open


func _refresh() -> void:
	_bind()
	if sim == null and game != null:
		sim = game.get("sim") as Sim
	var reg := RegionView.data()
	home = RegionView.home_of(sim.state.map_id if sim != null else "")
	if sim != null and (actor == "" or not sim.state.characters.has(actor)):
		actor = Kin.head(sim.state, SimQuery.player_family(sim.state))
	_was_on_road = _on_road(actor)
	cut = RegionView.cut_routes(sim)
	hours = RegionView.hours_from(home, cut.keys())   # over the routes open now
	_map.texture = VisualPaths.region_map(str(reg.get("id", "")))
	(%Title as Label).text = "%s · %s" % [SimQuery.t_("ui.region.title"), SimQuery.t_(str(reg.get("name_key", "")))]
	(%Hint as Label).text = status_text()
	(%CaravansButton as Button).text = SimQuery.t_("ui.region.caravans")
	(%CaravansButton as Button).icon = VisualPaths.region_icon("caravan")
	(%BackButton as Button).text = SimQuery.t_("ui.region.back")
	MenuKit.add_hint(%BackButton as Button, SimQuery.t_("ui.key.esc"))
	_build_markers()
	_layer.queue_redraw()
	if OS.is_debug_build():
		print("[RegionScreen] abre: casa=%s, %d asentamientos, %d rutas, cortadas=%s, horas=%s" % [home,
			RegionView.settlements().size(), RegionView.routes().size(), cut, hours])


## The council's vote on the strip for a few seconds («Exención con Vilablat · 4 a favor · 1 en contra · Firmado…»).
func say_council(e: Dictionary) -> void:
	var city := _city_name(str(e.get("city", "")))
	_strip.text = "%s · %s" % [SimQuery.t_("ui.council.votes") % [city, int(e.get("yes", 0)), int(e.get("no", 0))],
		SimQuery.t_("ui.council.passed") % city if bool(e.get("passed", false)) else SimQuery.t_("ui.council.failed")]
	_strip.visible = true
	_said_left = 8.0
	if selected != "" and _card.visible:
		show_card(selected, pinned)   # the card's button is no longer «Firmando…»
	if OS.is_debug_build():
		print("[RegionScreen] el concejo vota: %s" % _strip.text)


## One line under the title: where the active person is (on the road, in a city) or the hint.
func status_text() -> String:
	if sim == null or actor == "":
		return SimQuery.t_("ui.region.hint")
	var name := str(sim.state.characters.get(actor, {}).get("name", ""))
	var p := Travel.progress(sim, actor)
	if p.is_empty():
		return SimQuery.t_("ui.region.hint")
	if str(p["state"]) == "city":
		return SimQuery.t_("ui.region.status_city") % [name, _city_name(str(p["at"]))]
	return SimQuery.t_("ui.region.status_road") % [name, _city_name(str(p["to"])), ceili(float(p["minutes_left"]) / 60.0)]


func _city_name(id: String) -> String:
	return SimQuery.t_(str(RegionView.settlement(id).get("name_key", id)))


func _on_road(who: String) -> bool:
	return sim != null and str(Travel.trip(sim.state, who).get("state", "")) == "road"


## Someone of the player's family on the road, or one of its caravans out: the clock keeps running on the map.
func _family_on_road() -> bool:
	if sim == null or sim.state.region.is_empty():
		return false
	var fam := SimQuery.player_family(sim.state)
	for t: Dictionary in (sim.state.region.get("trips", {}) as Dictionary).values():
		if str(t.get("family", "")) == fam and str(t.get("state", "")) == "road":
			return true
	for c: Dictionary in sim.state.region.get("caravans", []):
		if str(c.get("family", "")) == fam:
			return true
	return false


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	if _said_left > 0.0:
		_said_left -= delta
	else:
		PausedOrders.fill_strip(_strip, game, sim, SimQuery.player_family(sim.state))
	if _family_on_road():
		_layer.queue_redraw()
		(%Hint as Label).text = status_text()
	var road := _on_road(actor)
	if _was_on_road and not road:
		var c := Travel.in_city(sim.state, actor)
		_was_on_road = false
		(%Hint as Label).text = status_text()
		if c != "":
			if OS.is_debug_build():
				print("[RegionScreen] %s llega a %s: abre su página" % [actor, c])
			city_requested.emit(c)
	_was_on_road = road


func default_focus() -> Control:
	return %BackButton as Control


## One flat button per settlement on its pos (hover shows the card, a click pins it) and its name under it.
func _build_markers() -> void:
	for c: Node in _layer.get_children():
		_layer.remove_child(c)
		c.queue_free()
	markers = {}
	for s: Dictionary in RegionView.settlements():
		var id := str(s["id"])
		var p := Vector2(s["pos"][0], s["pos"][1])
		var r := _radius(s)
		var b := Button.new()
		b.name = "Marker_" + id
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.position = p - Vector2(r + 3, r + 3)
		b.size = Vector2(r + 3, r + 3) * 2.0
		b.tooltip_text = ""
		b.mouse_entered.connect(func() -> void:
			if not pinned:
				show_card(id, false))
		b.mouse_exited.connect(func() -> void:
			if not pinned and selected == id:
				_card.close())
		b.focus_entered.connect(func() -> void:
			if not pinned:
				show_card(id, false))
		b.pressed.connect(func() -> void: show_card(id, true))
		_layer.add_child(b)
		markers[id] = b
		var l := Label.new()
		l.name = "Name_" + id
		l.text = SimQuery.t_(str(s.get("name_key", id)))
		l.theme_type_variation = &"InkTitleLabel" if str(s.get("kind", "")) == "capital" else &"InkLabel"
		l.add_theme_color_override("font_outline_color", PAPER)
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(l)
		l.reset_size()
		l.position = (p + Vector2(-l.size.x / 2.0, r + 2)).round()
		var feast := SimQuery.city_feast_soon(sim, id, 1) if sim != null else ""  # fiestas (4.25.6): announced on the map
		if feast != "":
			var fl := Label.new()
			fl.name = "Feast_" + id
			fl.text = _t("ui.region.feast_soon") % feast
			fl.theme_type_variation = &"InkLabel"
			fl.add_theme_color_override("font_color", Color("#8a2a1e"))
			fl.add_theme_color_override("font_outline_color", PAPER)
			fl.add_theme_constant_override("outline_size", 4)
			fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_layer.add_child(fl)
			fl.reset_size()
			fl.position = (p + Vector2(-fl.size.x / 2.0, r + 2 + l.size.y)).round()


func _radius(s: Dictionary) -> float:
	return float(RADIUS.get(str(s.get("kind", "")), 6.0))


## The routes (dashed ink; red with a cross in the middle while cut) and the settlements (a wax seal; gold for home,
## a gold ring round the one whose card is open).
func _draw_layer() -> void:
	for r: Dictionary in RegionView.routes():
		var pts := RegionView.route_points(r)
		var is_cut := cut.has(str(r["id"]))
		var col := CUT if is_cut else ROAD
		for i: int in pts.size() - 1:   # a pale underlay so the ink reads on fields and forest
			_layer.draw_line(pts[i], pts[i + 1], Color(PAPER, 0.45), 4.0)
		for i: int in pts.size() - 1:
			_layer.draw_dashed_line(pts[i], pts[i + 1], col, 2.0, 5.0)
		if is_cut:
			var m := _middle(pts)
			_layer.draw_line(m + Vector2(-5, -5), m + Vector2(5, 5), CUT, 3.0)
			_layer.draw_line(m + Vector2(-5, 5), m + Vector2(5, -5), CUT, 3.0)
	for s: Dictionary in RegionView.settlements():
		var p := Vector2(s["pos"][0], s["pos"][1])
		var r := _radius(s)
		var id := str(s["id"])
		if id == selected:
			_layer.draw_circle(p, r + 4.0, GOLD)
		_layer.draw_circle(p, r + 1.5, INK)
		_layer.draw_circle(p, r, GOLD if id == home else WAX)
		_layer.draw_circle(p, r * 0.45, INK if id == home else Color(WAX.lightened(0.25)))
	_draw_travellers()


## The family's people on the road and its caravans, on their route: the token (the banner, its cloth in the family's
## colours through identity_swap.gdshader, feet on the road) and the caravan (facing where it goes), as nodes over the
## layer; without their art, a seal of the family's colour and a box drawn on the layer.
func _draw_travellers() -> void:
	if sim == null or sim.state.region.is_empty():
		_sync_tokens({})
		return
	var fam := SimQuery.player_family(sim.state)
	var colors: Dictionary = sim.state.families.get(fam, {}).get("colors", {})
	var tint := Color(str(colors.get("primary", "#8a2a1e")))
	var token := VisualPaths.region_token(TOKEN_VARIANT)
	var cart := VisualPaths.region_caravan(CARAVAN_VARIANT)
	var want := {}   # node name -> {tex, at (feet), flip, tint}
	for chr: String in (sim.state.region.get("trips", {}) as Dictionary):
		var t: Dictionary = sim.state.region["trips"][chr]
		if str(t.get("family", "")) != fam:
			continue
		var p := Travel.progress(sim, chr)
		var at := _position_of(p)
		if VisualPaths.is_placeholder(token):
			_layer.draw_circle(at, 9.0, INK)
			_layer.draw_circle(at, 8.0, tint)
			_layer.draw_arc(at, 6.0, 0.0, TAU, 16, GOLD, 2.0)
		else:
			want["Token_" + chr] = {"tex": token, "at": at + Vector2(0, 4), "flip": false, "family": true}
	for c: Dictionary in sim.state.region.get("caravans", []):
		if str(c.get("family", "")) != fam:
			continue
		var p := Caravans.progress(sim, c)
		# on the road, just under its route; stopped in a town, beside its seal (clear of the token and the name)
		var at := _position_of(p) + (Vector2(0, 4) if str(p.get("state", "")) == "road" else Vector2(30, 14))
		if VisualPaths.is_placeholder(cart):
			_layer.draw_texture(cart, at - Vector2(cart.get_size()) / 2.0)
		else:
			want["Caravan_" + str(c["id"])] = {"tex": cart, "at": at,   # wheels on the road
				"flip": _heading_west(p), "family": false}
	_sync_tokens(want)


## Whether a caravan on the road goes west (its sprite faces east: mirrored).
func _heading_west(p: Dictionary) -> bool:
	if str(p.get("state", "")) != "road":
		return false
	var a := _position_of(p)
	var q := p.duplicate()
	q["progress"] = minf(1.0, float(p["progress"]) + 0.05)
	return _position_of(q).x < a.x - 0.01


## Keeps one TextureRect per token and caravan in `want` (created, moved, freed), feet at its point.
func _sync_tokens(want: Dictionary) -> void:
	var box := get_node_or_null("Tokens") as Control
	if box == null:
		box = Control.new()
		box.name = "Tokens"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		move_child(box, _layer.get_index() + 1)
	for c: Node in box.get_children():
		if not want.has(str(c.name)):
			box.remove_child(c)
			c.queue_free()
	var fam := SimQuery.player_family(sim.state) if sim != null else ""
	var colors: Dictionary = sim.state.families.get(fam, {}).get("colors", {}) if sim != null else {}
	for n: String in want:
		var w: Dictionary = want[n]
		var r := box.get_node_or_null(n) as TextureRect
		if r == null:
			r = TextureRect.new()
			r.name = n
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if bool(w["family"]):
				var mat := ShaderMaterial.new()
				mat.shader = IDENTITY_SHADER
				mat.set_shader_parameter("primary", Color(str(colors.get("primary", "#8a2a1e"))))
				mat.set_shader_parameter("secondary", Color(str(colors.get("secondary", "#c8a84e"))))
				r.material = mat
			box.add_child(r)
		var tex: Texture2D = w["tex"]
		r.texture = tex
		r.size = tex.get_size()
		r.flip_h = bool(w["flip"])
		r.position = (Vector2(w["at"]) - Vector2(tex.get_width() / 2.0, tex.get_height())).round()


## Where a trip or a caravan is on the map: on its route's polyline at its progress (from -> next), or on the seal
## of the settlement where it stays.
func _position_of(p: Dictionary) -> Vector2:
	if str(p.get("state", "")) != "road":
		var s := RegionView.settlement(str(p.get("at", "")))
		return Vector2(s["pos"][0], s["pos"][1]) + Vector2(0, -14) if not s.is_empty() else Vector2.ZERO
	var r := {}
	for x: Dictionary in RegionView.routes():
		if str(x["id"]) == str(p["route"]):
			r = x
	var pts := RegionView.route_points(r)
	if str(r.get("a", "")) != str(p["from"]):
		pts.reverse()
	return _along(pts, float(p["progress"]))


## The point at fraction `f` (0..1) of a polyline's length.
static func _along(pts: PackedVector2Array, f: float) -> Vector2:
	var total := 0.0
	for i: int in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var left := total * clampf(f, 0.0, 1.0)
	for i: int in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if left <= d and d > 0.0:
			return pts[i].lerp(pts[i + 1], left / d)
		left -= d
	return pts[pts.size() - 1]


## The point halfway along a polyline.
static func _middle(pts: PackedVector2Array) -> Vector2:
	var total := 0.0
	for i: int in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var left := total / 2.0
	for i: int in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if left <= d and d > 0.0:
			return pts[i].lerp(pts[i + 1], left / d)
		left -= d
	return pts[pts.size() - 1]


## Shows the card of settlement `id` beside its seal (pinned: it stays when the mouse leaves).
func show_card(id: String, pin: bool) -> void:
	var s := RegionView.settlement(id)
	if s.is_empty():
		return
	selected = id
	pinned = pin
	_card.build(card_data(id))
	_card.visible = true
	_card.layout_now()
	var p := Vector2(s["pos"][0], s["pos"][1])
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(960, 540)
	var x := p.x + CARD_GAP if p.x + CARD_GAP + _card.size.x < view.x - 8 else p.x - CARD_GAP - _card.size.x
	var y := clampf(p.y - _card.size.y / 2.0, 8.0 + _card.ribbon_overhang, view.y - BOTTOM - _card.size.y)
	_card.position = Vector2(x, y).round()
	_layer.queue_redraw()
	if OS.is_debug_build():
		print("[RegionScreen] ficha %s (fijada=%s, en %s, %s)" % [id, pin, _card.position, _card.size])


## The PageCard data of a settlement's card.
func card_data(id: String) -> Dictionary:
	var s := RegionView.settlement(id)
	var dist := _t("ui.region.here")
	if id != home:
		dist = _t("ui.region.unreachable") if not hours.has(id) else _t("ui.region.distance_value") % [
			int(round(float(hours[id]))), _t(str(RegionView.settlement(home).get("name_key", "")))]
	var blocks: Array = [
		{"type": "paragraph", "text": _t("region.kind." + str(s.get("kind", "")))},
		{"type": "figures", "items": [
			{"label": _t("ui.region.size"), "value": _t("ui.region.size_value") % [int(s.get("households", 0)),
				int(s.get("souls", 0))]},
			{"label": _t("ui.region.distance"), "value": dist}]},
		{"type": "paragraph", "text": "%s: %s" % [_t("ui.region.specialty"), _t(str(s.get("specialty", "")))]},
		{"type": "paragraph", "text": "%s: %s" % [_t("ui.region.rulers"), _t(str(s.get("rulers", "")))]},
	]
	if sim != null:  # fiestas (4.25.6): its patron feast and its fair
		for line: String in SimQuery.city_feast_lines(sim, id):
			blocks.append({"type": "paragraph", "text": line})
	var goods: Array = []
	if not (s.get("cheap", {}) as Dictionary).is_empty():
		goods.append({"text": "%s: %s" % [_t("ui.region.cheap"), _mults(s["cheap"])], "sign": ""})
	if not (s.get("dear", {}) as Dictionary).is_empty():
		goods.append({"text": "%s: %s" % [_t("ui.region.dear"), _mults(s["dear"])], "sign": "+"})
	if not goods.is_empty():
		blocks.append({"type": "effects", "items": goods})
	var lines: Array = []
	for r: Dictionary in RegionView.routes_of(id):
		var other := str(r["b"]) if str(r["a"]) == id else str(r["a"])
		var text := "%s · %s" % [_t(str(RegionView.settlement(other).get("name_key", ""))),
			_t("ui.region.route") % [_t("region.terrain." + str(r.get("terrain", ""))), int(r.get("hours", 0)),
			int(r.get("risk", 0))]]
		var by: Array = cut.get(str(r["id"]), [])
		if not by.is_empty():
			text += " · " + _t("ui.region.route_cut") % ", ".join(by.map(func(e: String) -> String:
				return SimQuery.event_name(sim.catalog, e)))
		lines.append({"text": text, "sign": "-" if not by.is_empty() else ""})
	blocks.append({"type": "divider"})
	blocks.append({"type": "effects", "items": lines})
	return {"template": "card", "title": _t(str(s.get("name_key", id))), "sticky": true, "blocks": blocks,
		"buttons": card_buttons(id)}


## The card's buttons for settlement `id` and the active person: travel (with or without escort: off with the reason
## while it cannot), back home, see the city (the one where the person is), and the Mayor's town treaty.
func card_buttons(id: String) -> Array:
	var out: Array = []
	if sim == null or actor == "":
		return out
	var here := Travel.in_city(sim.state, actor)
	var road := _on_road(actor)
	if id == here:
		out.append({"id": "city", "text": _t("ui.region.see_city"), "primary": true})
	if id == home and here != "":
		out.append(_travel_button("return", _t("ui.region.return"), home, false))
	elif id != home and id != here and not road:
		out.append(_travel_button("travel", _t("ui.region.travel"), id, false))
		out.append(_travel_button("travel_escort", _t("ui.region.travel_escort") % int(
			sim.catalog.trade.get("travel", {}).get("escort_cost", 20)), id, true))
	if id != home and here == "" and not road and actor in Offices.holders(sim, "mayor"):
		var fam := str(sim.state.characters[actor].get("family", ""))
		var why := Treaties.can_sign(sim, fam, id, "exemption", "", "town")
		if PausedOrders.waiting(game, "propose_town_treaty", {"actor": actor, "city": id}):   # given in pause
			out.append({"id": "town_treaty", "text": _t("ui.region.town_treaty_waiting"), "disabled": true,
				"tip": _t("ui.paused_orders.tip")})
		else:
			out.append({"id": "town_treaty", "text": _t("ui.region.town_treaty"), "disabled": why != "",
				"tip": SimQuery.reason_text(why) if why != "" else _t("ui.region.town_treaty_tip")})
	return out


func _travel_button(bid: String, text: String, to: String, escort: bool) -> Dictionary:
	var why := Travel.can_travel(sim, actor, to, escort)
	var tip := SimQuery.reason_text(why) if why != "" else _t("ui.region.travel_tip_on")
	return {"id": bid, "text": text, "disabled": why != "", "tip": tip, "primary": bid == "travel"}


## A button of the card: its order to the sim (or the city page).
func _on_card_button(bid: String) -> void:
	var to := selected
	if OS.is_debug_build():
		print("[RegionScreen] botón %s en la ficha de %s (actor %s)" % [bid, to, actor])
	match bid:
		"travel", "travel_escort":
			_give({"type": "travel", "actor": actor, "to": to, "escort": bid == "travel_escort"})
			_run_clock()
		"return":
			_give({"type": "return", "actor": actor})
			_run_clock()
		"city":
			city_requested.emit(Travel.in_city(sim.state, actor))
		"town_treaty":
			_give({"type": "propose_town_treaty", "actor": actor, "city": to, "kind": "exemption"})
			(func() -> void: show_card(to, true)).call_deferred()   # the card stays, its button says it waits


func _give(o: Dictionary) -> void:
	if order_sink.is_valid():
		order_sink.call(o)
	elif game != null and game.has_method("give"):
		game.call("give", o)


## After setting out, the clock runs while the map is open (to watch the trip); closing it leaves it running.
func _run_clock() -> void:
	_was_paused = false
	if game != null and game.has_method("set_paused"):
		game.call("set_paused", false)
	_was_on_road = true


static func _t(key: String) -> String:
	return SimQuery.t_(key)


## «hierro ×0,6, carbón ×0,7»: items by their name, goods groups by theirs (goods.<group>).
func _mults(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in m:
		var name := ""
		if sim != null and sim.catalog.items().has(k):
			name = SimQuery.item_name(sim.catalog, k).to_lower()
		else:
			name = SimQuery.t_("goods." + k).to_lower()
		parts.append("%s ×%s" % [name, _num(float(m[k]))])
	return ", ".join(parts)


static func _num(x: float) -> String:
	var s := ("%.2f" % x).rstrip("0").rstrip(".")
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("es") else s


func _unhandled_input(event: InputEvent) -> void:
	if visible and _card != null and _card.visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		_card.close()
		get_viewport().set_input_as_handled()
		return
	super(event)


## A click on the parchment (not on a seal or the card) closes a pinned card.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _card.visible:
		_card.close()
