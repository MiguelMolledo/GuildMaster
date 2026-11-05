class_name InnVisitCard
extends PageCard
## Another family's gaming table, from its door (docs/gdd/04f_vida_y_fiestas.md §4.27.4; InnGames.terms): a PageCard
## «Carta» with whose tavern it is, its least stake and the licence's warning, and a button per game (azar, mayor,
## envite) at that stake: it opens the games' screen (App.open_game with InnGames.request, opts.house = that tavern).
## When the owner does not let him play, it says so with only «Entendido». The HUD's «Jugar en la mesa» opens it.

var building: String = ""
var actor: String = ""
var game_sink: Callable = Callable()   # tests: what a game button opens (default: App.open_game)


func _ready() -> void:
	super._ready()
	button_pressed.connect(_on_button)


## The PageCard data for `who` at the table of `bld` ({} if it is no tavern with a table).
static func data_for(sim: Sim, bld: String, who: String) -> Dictionary:
	if not Inn.is_inn(sim, bld) or not InnGames.has_table(sim, bld):
		return {}
	var st := sim.state
	var owner := str(st.buildings[bld].get("owner", ""))
	var owner_name := str(st.families.get(owner, {}).get("name", ""))
	var blocks: Array = []
	var buttons: Array = []
	var why := InnGames.visitor_blocked(sim, bld, who)
	var t := InnGames.terms(sim, bld, who)
	if why != "":
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.inn.visit.why." + why) % owner_name
			if SimQuery.t_("ui.inn.visit.why." + why).contains("%s") else SimQuery.t_("ui.inn.visit.why." + why)})
	else:
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.inn.visit.text") % [owner_name, int(t["min_stake"])]})
		if not Inn.licensed(sim, bld):
			blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.inn.visit.no_license")})
		var fam := str(st.characters.get(who, {}).get("family", ""))
		var cap := int(sim.catalog.games.get("cap", 50))
		for g: String in InnGames.GAMES:
			buttons.append({"id": "play:" + g, "text": SimQuery.t_("ui.inn.visit.play") % [SimQuery.t_("games.%s.name" % g),
				int(t["min_stake"])], "primary": g == "azar",
				"disabled": not Money.can_pay(st, fam, Games.max_loss(g, int(t["min_stake"]), cap))})
	buttons.append({"id": "ok", "text": SimQuery.t_("ui.inn.offer.later") if why == "" else SimQuery.t_("ui.event_card.ok")})
	return {"template": "card", "title": SimQuery.t_("ui.inn.visit.title") % SimQuery.building_label(st, sim.catalog, bld),
		"image": VisualPaths.illustration("events", "game_azar"), "blocks": blocks, "buttons": buttons, "building": bld}


func show_for(sim: Sim, bld: String, who: String) -> bool:
	var d := data_for(sim, bld, who)
	if d.is_empty():
		return false
	building = bld
	actor = who
	show_page(d)
	return true


func _on_button(id: String) -> void:
	if not id.begins_with("play:"):
		return
	var g := get_node_or_null("/root/Game")
	if g == null or g.get("sim") == null:
		return
	var sim := g.get("sim") as Sim
	var t := InnGames.terms(sim, building, actor)
	var req := InnGames.request(sim, building, actor, id.substr(5), int(t.get("min_stake", 10)))
	if req.has("reason"):
		ViewConfig.info("InnVisitCard", "no se puede jugar: %s" % req["reason"])
		return
	ViewConfig.info("InnVisitCard", "juega en la mesa ajena: %s" % [req])
	if game_sink.is_valid():
		game_sink.call(req)
		return
	var app := get_node_or_null("/root/App")
	if app != null and app.has_method("open_game"):
		app.call_deferred("open_game", req)
