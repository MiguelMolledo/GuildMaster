class_name InnTurnCard
extends PageCard
## The card of the turn summary (docs/gdd/04f_vida_y_fiestas.md §4.27.4): when a Taberna-Posada of the player's family
## closes its night (inn_turn_closed, 02:00), a PageCard «Carta» with InnTurnPage's data. It does not pause; the button,
## a click or event_card_seconds close it. Listens to Events itself (like EventCard); reads only.

var shown: Array = []   # the days shown (tests, smoke)


func _ready() -> void:
	super._ready()
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			var s := g.get("sim") as Sim
			for e: Dictionary in events:
				if str(e.get("type", "")) == "inn_turn_closed" and str(e.get("family", "")) == SimQuery.player_family(s.state):
					show_for(s, str(e.get("building", ""))))


func show_for(sim: Sim, bld: String) -> void:
	var d := InnTurnPage.data_for(sim, bld)
	if d.is_empty():
		return
	shown.append(int(Inn.state_of(sim, bld).get("last_turn", {}).get("day", -1)))
	show_page(d)
