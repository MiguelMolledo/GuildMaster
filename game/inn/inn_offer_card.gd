class_name InnOfferCard
extends PageCard
## The card of the traveller's game (docs/gdd/04f_vida_y_fiestas.md §4.27.4; InnGames.make_offer): when a stranger
## proposes a game in a Taberna-Posada of the player's family (inn_game_offer), a PageCard «Carta» with who, which game
## and the stake: «Jugar» opens the games' screen (App.open_game with InnGames.offer_request); «Ahora no» leaves it open
## in the Mesa tab until the turn closes. It does not pause; event_card_seconds closes it. Listens to Events itself.

var shown: Array = []   # the offers shown: "<building>|<day>" (tests, smoke)
var building: String = ""
var game_sink: Callable = Callable()   # tests: what Jugar opens (default: App.open_game)


func _ready() -> void:
	super._ready()
	button_pressed.connect(_on_button)
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			var s := g.get("sim") as Sim
			for e: Dictionary in events:
				if str(e.get("type", "")) == "inn_game_offer" and str(e.get("family", "")) == SimQuery.player_family(s.state):
					show_for(s, str(e.get("building", ""))))


## The PageCard data of tonight's offer in `bld` ({} if none).
static func data_for(sim: Sim, bld: String) -> Dictionary:
	var o := InnGames.offer_of(sim, bld)
	if o.is_empty():
		return {}
	var pr: Dictionary = sim.catalog.games.get("presets", {}).get(str(o["preset"]), {})
	var who := SimQuery.t_(str(pr.get("name_key", o["preset"])))
	var game := SimQuery.t_("games.%s.name" % str(o["game"]))
	var blocks: Array = [{"type": "paragraph", "text": SimQuery.t_("ui.inn.offer.text") % [who, game, int(o["stake"])]}]
	if not Inn.licensed(sim, bld):
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.inn.games.no_license")})
	var fam := str(sim.state.buildings[bld].get("owner", ""))
	var cap := int(sim.catalog.games.get("cap", 50))
	return {"template": "card", "title": SimQuery.t_("ui.inn.offer.title"),
		"image": VisualPaths.illustration("events", "game_" + str(o["game"])), "blocks": blocks,
		"buttons": [{"id": "play", "text": SimQuery.t_("ui.inn.games.offer_play"), "primary": true,
			"disabled": not Money.can_pay(sim.state, fam, Games.max_loss(str(o["game"]), int(o["stake"]), cap))},
			{"id": "later", "text": SimQuery.t_("ui.inn.offer.later")}],
		"seconds": float(ViewConfig.value("event_card_seconds", 12.0)), "building": bld}


func show_for(sim: Sim, bld: String) -> void:
	var d := data_for(sim, bld)
	if d.is_empty():
		return
	building = bld
	shown.append("%s|%d" % [bld, int(Inn.state_of(sim, bld).get("night", {}).get("day", -1))])
	show_page(d)


func _on_button(id: String) -> void:
	if id != "play":
		return
	var g := get_node_or_null("/root/Game")
	if g == null or g.get("sim") == null:
		return
	var sim := g.get("sim") as Sim
	var fam := str(sim.state.buildings.get(building, {}).get("owner", ""))
	var req := InnGames.offer_request(sim, building, InnGames.player_for(sim, building, fam))
	if req.has("reason"):
		return
	ViewConfig.info("InnOfferCard", "juega la partida del forastero: %s" % [req])
	if game_sink.is_valid():
		game_sink.call(req)
		return
	var app := get_node_or_null("/root/App")
	if app != null and app.has_method("open_game"):
		app.call_deferred("open_game", req)
