class_name EventCard
extends PageCard
## The card of a global event (H13; docs/ui/04_kit_de_pagina.md §4): when an event starts (world_event_started, from
## the roll or declared by the mayor), a PageCard «Carta» with its illustration, name, effects and how long it lasts.
## It does not pause; «Entendido», a click on the button or view.json event_card_seconds close it. One at a time: if
## another starts while one is shown, it waits (docs/ui/mecanicas/_social.md). The notice of zone 7 still shows and
## stays in the book. Listens to Events itself (like WeddingCard); reads only, gives no orders.
## Fiestas (04f 4.25.3): the same card shows the festival's crier (festival_eve), its start (festival_started) and the
## player's wedding offer (FestivalPage); their buttons (sponsor a part, pay the banquet) are the only orders it gives
## (order_sink, Game.give by default).

var shown: Array = []      # the event ids shown (tests, smoke)
var order_sink: Callable = Callable()
var _queue: Array = []


func _ready() -> void:
	super._ready()
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			for e: Dictionary in events:
				if str(e.get("type", "")) == "world_event_started":
					show_for(g.get("sim") as Sim, e)
				elif str(e.get("type", "")) in ["festival_eve", "festival_started", "festival_wedding_offer",
						"festival_gift_offers", "festival_gift_chosen", "festival_contest", "festival_audience"]:
					show_festival(g.get("sim") as Sim, e))
	button_pressed.connect(_on_button)


## Fiestas (4.25.3): the feast's card opened again by the player (the clock's button, a notice of the feast): shown
## now (over another card it waits its turn), never twice if it is the one on screen.
func reopen_festival(sim: Sim, e: Dictionary) -> void:
	var d := FestivalPage.data_for(sim, e, SimQuery.player_family(sim.state))
	if d.is_empty():
		return
	d["event"] = "festival:" + str(d.get("festival", ""))
	if visible and str(data.get("instance", "")) == str(d.get("instance", "")):
		return
	d["seconds"] = 0.0  # opened on purpose: it stays until closed
	if visible:
		_queue.append(d)
		return
	show_page(d)


## Fiestas: the card of a festival event for the player's family (or queues it). The wedding offer only for its family.
func show_festival(sim: Sim, e: Dictionary) -> void:
	var fam := SimQuery.player_family(sim.state)
	if str(e.get("type", "")) == "festival_wedding_offer" and str(e.get("family", "")) != fam:
		return
	if str(e.get("type", "")) == "festival_audience" and str(e.get("family", "")) != fam:
		return  # only the player's own audience
	if str(e.get("type", "")) == "festival_gift_offers" and \
			str(sim.state.characters.get(str(e.get("mayor", "")), {}).get("family", "")) != fam:
		return  # only for the mayor
	var d := FestivalPage.data_for(sim, e, fam)
	if d.is_empty():
		return
	d["event"] = "festival:" + str(d.get("festival", ""))
	if visible:
		_queue.append(d)
		return
	shown.append(str(d["event"]))
	show_page(d)


func _on_button(id: String) -> void:
	var g := get_node_or_null("/root/Game")
	if g == null or g.get("sim") == null:
		return
	var sim: Sim = g.get("sim")
	if id == "gifts_menu":  # fiestas: the Christmas gifts, the families on a second card
		var gm := FestivalPage.gifts_menu(sim, data)
		(func() -> void: show_page(gm)).call_deferred()
		return
	if id == "corro_menu":  # fiestas: the corro in the plaza, its games on a second card
		var cm := FestivalPage.corro_menu(sim, data)
		(func() -> void: show_page(cm)).call_deferred()
		return
	var app0 := get_node_or_null("/root/App")
	if id.begins_with("corro:") and app0 != null and app0.has_method("open_game"):
		app0.call("open_game", FestivalPage.corro_request(sim, id, data,
			SimQuery.family_actor(sim.state, SimQuery.player_family(sim.state))))
		return
	if id == "audience_menu":  # the privileges on a second card (after this one closes)
		var menu := FestivalPage.audience_menu(sim, data)
		(func() -> void: show_page(menu)).call_deferred()
		return
	var actor := SimQuery.family_actor(sim.state, SimQuery.player_family(sim.state))
	if id.begins_with("choose:"):  # the mayor's choice: the order is the mayor's
		actor = FestivalCourt.mayor(sim)
	var app := get_node_or_null("/root/App")
	if id.begins_with("bet:") and app != null and app.has_method("open_game"):  # juegos: the bookmaker of the feast
		app.call("open_game", {"game": str(FestivalGames.spectacle_cfg(sim, id.substr(4)).get("game", "")), "actor": actor,
			"festival": str(data.get("instance", "")), "spectacle": id.substr(4)})
		return
	var o := FestivalPage.order_for(id, data, actor)
	if o.is_empty():
		return
	if OS.is_debug_build():
		print("[EventCard] orden de la carta de fiesta: %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	else:
		g.call("give", o)


## Shows the card of world_event_started event `e` (or queues it behind the one on screen).
func show_for(sim: Sim, e: Dictionary) -> void:
	var d := EventPage.data_for(sim, e)
	if d.is_empty():
		return
	if visible:
		_queue.append(d)
		return
	shown.append(str(d.get("event", "")))
	show_page(d)


func close() -> void:
	var was := visible
	super.close()
	if was:
		_next()


func _next() -> void:
	if _queue.is_empty():
		return
	var d: Dictionary = _queue.pop_front()
	shown.append(str(d.get("event", "")))
	show_page(d)
