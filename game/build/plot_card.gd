class_name PlotCard
extends PageCard
## H6 · a plot in the building mode (docs/gdd/04_diseno_de_juego.md §4.9, §4.9.1; Plots): a PageCard «Carta» with
## what the plot is (a free lot, a ruin, a business: its zone, size, side and situation) and what the person can do
## there, each with its price and days or why not: build or restore a building of the types that fit, pull down or
## convert the family's own, buy another family's business. The buttons give the orders (build, demolish,
## convert_building, buy_building) through the order sink (default: /root/Game.give). The building mode opens it on a
## click on a plot; the HUD's «Comprar» on another family's business too.

var plot: String = ""
var actor: String = ""
var order_sink: Callable = Callable()   # tests: where the orders go (default: /root/Game.give)


func _ready() -> void:
	super._ready()
	button_pressed.connect(_on_button)


## The PageCard data of plot `plot_id` for `who` ({} if there is no such plot).
static func data_for(sim: Sim, plot_id: String, who: String) -> Dictionary:
	var p := Plots.get_plot(sim, plot_id)
	if p.is_empty():
		return {}
	var st := sim.state
	var fam := str(st.characters.get(who, {}).get("family", ""))
	var blocks: Array = []
	var buttons: Array = []
	var kind := str(p["kind"])
	var bld := str(p["building"])
	var size: Array = p.get("size", [0, 0])
	blocks.append({"type": "figures", "items": [
		{"label": SimQuery.t_("ui.plots.zone." + str(p["zone"])), "value": "%d×%d" % [int(size[0]), int(size[1])]},
		{"label": SimQuery.t_("ui.plots.side." + str(p.get("side", "inside"))), "value": SimQuery.t_("ui.plots.location_is")
			% location_label(float(p.get("location", 0.5)))}]})
	var title := ""
	if kind in ["lot", "ruin"]:
		title = SimQuery.t_("ui.plots.title." + kind)
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.text." + kind)})
		var types := Plots.types_for(sim, p)
		if types.is_empty():
			blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.nothing_fits." + str(p["zone"]))})
		for t: String in types:
			var r := Plots.can_build(sim, who, plot_id, t)
			var q := Plots.quote(sim, p, t)
			buttons.append({"id": "build:" + t, "text": SimQuery.t_("ui.plots." + str(q["kind"])) % [
				SimQuery.t_("building." + t), int(q["price"]), days_label(float(q["days"]))],
				"primary": r["ok"] and t == _best(sim, fam, types), "disabled": not r["ok"],
				"tip": "" if r["ok"] else why_text(sim, str(r["reason"]), fam, int(q["price"]))})
	else:
		var b: Dictionary = st.buildings[bld]
		var owner := str(b.get("owner", ""))
		title = SimQuery.building_label(st, sim.catalog, bld)
		if str(b.get("state", "")) == "construction":
			var w: Dictionary = SimQuery.construction_works(sim, bld)
			blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.works") % SimQuery.minutes_left_label(
				int(w.get("minutes_left", 0)))})
		if owner == fam and fam != "":
			blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.text.own")})
			var d := Plots.can_demolish(sim, who, bld)
			buttons.append({"id": "demolish", "text": SimQuery.t_("ui.plots.demolish") % int(d.get("refund", roundi(float(
				Plots.build_cost(sim, str(b["type"]))) * float(Plots.rules(sim).get("demolish_refund", 0.4))))),
				"disabled": not d["ok"], "tip": "" if d["ok"] else why_text(sim, str(d["reason"]), fam, 0)})
			for t: String in Plots.types_for(sim, p):
				if t == str(b["type"]):
					continue
				var c := Plots.can_convert(sim, who, bld, t)
				buttons.append({"id": "convert:" + t, "text": SimQuery.t_("ui.plots.convert") % [SimQuery.t_("building." + t),
					int(c.get("price", 0))], "disabled": not c["ok"],
					"tip": "" if c["ok"] else why_text(sim, str(c["reason"]), fam, int(c.get("price", 0)))})
		elif bool(b.get("for_sale", false)) and owner == "":
			blocks.append({"type": "paragraph", "text": SimQuery.t_("hud.building_for_sale") % Inn.sale_price(sim, bld)})
			var ok := Plots.room_for(sim, fam, str(b["type"])) and Money.can_pay(st, fam, Inn.sale_price(sim, bld))
			buttons.append({"id": "buy", "text": SimQuery.t_("hud.buy_building") % Inn.sale_price(sim, bld), "primary": ok,
				"disabled": not ok, "tip": "" if ok else why_text(sim, "title_limit" if not Plots.room_for(sim, fam,
				str(b["type"])) else "not_enough_gold", fam, Inn.sale_price(sim, bld))})
		else:
			var seller := str(st.families.get(owner, {}).get("name", ""))
			var r := Plots.can_buy_from(sim, who, bld)
			if str(r["reason"]) == "not_for_sale":
				blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.text.not_for_sale") % seller})
			else:
				var price := int(r.get("price", Plots.npc_price(sim, bld, Emotions.relation(st, Kin.head(st, owner), who))))
				blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.plots.text.business") % [seller, price]})
				buttons.append({"id": "buy", "text": SimQuery.t_("hud.buy_building") % price, "primary": r["ok"],
					"disabled": not r["ok"], "tip": "" if r["ok"] else why_text(sim, str(r["reason"]), fam, price)})
	buttons.append({"id": "ok", "text": SimQuery.t_("ui.plots.close")})
	# with many choices the card would grow off the screen: they matter more than the picture
	var image: Texture2D = VisualPaths.illustration_or_greybox("events", "plot_" + kind) if buttons.size() <= 3 else null
	return {"template": "card", "title": title, "image": image, "blocks": blocks, "buttons": buttons, "plot": plot_id,
		"modal": true, "wrap_buttons": true}


## The type the family would build first: its own trade's, else the first that fits.
static func _best(sim: Sim, fam: String, types: Array) -> String:
	for b: String in sim.state.buildings:
		var t := str(sim.state.buildings[b].get("type", ""))
		if str(sim.state.buildings[b].get("owner", "")) == fam and t in types:
			return t
	return str(types[0]) if not types.is_empty() else ""


## How long the works last: «12 h» under a day, «1 d», «1,5 d» from there.
static func days_label(days: float) -> String:
	if days < 1.0:
		return SimQuery.hours_label(days * 24.0)
	return "%s d" % SimQuery._num(days)


## «Muy buena» … «Apartada»: the plot's situation in words (location 0-1).
static func location_label(loc: float) -> String:
	var band := "poor"
	if loc >= 0.7:
		band = "best"
	elif loc >= 0.5:
		band = "good"
	elif loc >= 0.3:
		band = "fair"
	return SimQuery.t_("ui.plots.location." + band)


## Why a button is off, in words: the title it needs for the limit, the gold it lacks, or the reason's text.
static func why_text(sim: Sim, reason: String, fam: String, price: int) -> String:
	match reason:
		"title_limit":
			var cap := Titles.max_buildings(sim, fam)
			return SimQuery.t_("ui.plots.why.title_limit") % [cap, Plots.counted(sim, fam)]
		"not_enough_gold":
			return SimQuery.t_("ui.why.bet_gold") % [price, Money.gold(sim.state, fam)]
	return SimQuery.reason_text(reason)


func show_for(sim: Sim, plot_id: String, who: String) -> bool:
	var d := data_for(sim, plot_id, who)
	if d.is_empty():
		return false
	plot = plot_id
	actor = who
	show_page(d)
	_recenter.call_deferred()   # its wrapped buttons know their height a frame later
	ViewConfig.info("PlotCard", "parcela %s para %s" % [plot_id, who])
	return true


func _recenter() -> void:
	if not is_inside_tree() or not visible or docked:
		return
	reset_size()
	var whole := size + Vector2(0, ribbon_overhang)
	position = ((get_viewport_rect().size - whole) / 2.0 + Vector2(0, ribbon_overhang)).round()


func _on_button(id: String) -> void:
	var g := get_node_or_null("/root/Game")
	var sim: Sim = g.get("sim") as Sim if g != null and g.get("sim") != null else null
	var o := order_of(sim, id)
	if o.is_empty():
		return
	ViewConfig.info("PlotCard", "orden %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	elif g != null and g.has_method("give"):
		g.call("give", o)


## The order of button `id` on this card's plot ({} for «Cerrar»).
func order_of(sim: Sim, id: String) -> Dictionary:
	if id.begins_with("build:"):
		return {"type": "build", "actor": actor, "plot": plot, "building_type": id.substr(6)}
	var bld := str(Plots.get_plot(sim, plot).get("building", "")) if sim != null else ""
	if id == "demolish":
		return {"type": "demolish", "actor": actor, "building": bld}
	if id.begins_with("convert:"):
		return {"type": "convert_building", "actor": actor, "building": bld, "building_type": id.substr(8)}
	if id == "buy":
		return {"type": "buy_building", "actor": actor, "building": bld}
	return {}
