class_name IncidentCard
extends PageCard
## The card of an incident of the player's family (docs/gdd/04f_vida_y_fiestas.md §4.24.5): a sticky «Carta» of the
## page kit when an incident asks for a decision (event incident_card): what happens and one button per choice.
## A choice gives resolve_incident (a management order: it applies at once, also in pause); «Más tarde» folds it until
## the next one (the notice stays in the book and the default comes at the timeout). When the incident ends the card
## closes. Listens to Events itself; reads Incidents and gives orders through the Game autoload.

var shown: Array = []       # the incident ids shown (tests, smoke)
var incident_id: String = ""
var _later: Dictionary = {}  # incident id -> true: folded by the player
var _sim: Sim = null


func _ready() -> void:
	super._ready()
	button_pressed.connect(_on_button)
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			follow(g.get("sim") as Sim, events))


## After each step: a new card for the player's family shows; the shown one closes when its incident ends or is
## answered; a card left unanswered (a negotiation) shows again.
func follow(sim: Sim, events: Array) -> void:
	_sim = sim
	var fam := SimQuery.player_family(sim.state)
	for e: Dictionary in events:
		if str(e.get("type", "")) == "incident_card" and str(e.get("family", "")) == fam:
			_later.erase(str(e.get("incident", "")))
	var cards := Incidents.cards_for(sim.state, fam)
	if visible and incident_id != "" and not cards.any(func(i: Dictionary) -> bool: return str(i["id"]) == incident_id):
		incident_id = ""
		close()
	if visible:
		return
	for i: Dictionary in cards:
		if not _later.has(str(i["id"])):
			show_for(sim, str(i["id"]))
			return


func show_for(sim: Sim, id: String) -> void:
	_sim = sim
	var inc := Incidents.find(sim.state, id)
	if inc.is_empty():
		return
	var actor := SimQuery.family_actor(sim.state, SimQuery.player_family(sim.state), "")
	incident_id = id
	shown.append(id)
	show_page(IncidentPage.data_for(sim, inc, actor))


func _on_button(id: String) -> void:
	var inc_id := incident_id
	incident_id = ""
	if id == "later" or _sim == null:
		_later[inc_id] = true
		return
	var g := get_node_or_null("/root/Game")
	var actor := SimQuery.family_actor(_sim.state, SimQuery.player_family(_sim.state), "")
	# juegos (docs/contratos/juegos.md §5): the rescue is played on the game screen (it gives resolve_incident with the
	# moves) and «Apostar» opens the bookmaker of the brawl
	var app := get_node_or_null("/root/App")
	if id in ["rescue", "bet"] and app != null and app.has_method("open_game"):
		app.call("open_game", {"game": "rescue" if id == "rescue" else "brawl", "actor": actor, "incident": inc_id,
			"helpers": 2})
		if id == "bet":
			_later[inc_id] = true  # the card comes back for its own choices
		return
	var order := {"type": "resolve_incident", "actor": actor, "incident": inc_id, "choice": id, "helpers": 2}
	ViewConfig.info("IncidentCard", "order %s" % [order])
	if g != null:
		g.call("give", order)
