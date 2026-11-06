class_name UnlockCard
extends PageCard
## The card «Nuevo: …» of an unlock (docs/gdd/03b_diversion_y_ritmo.md §3b.4, data/unlocks.json): when Unlocks opens
## something for the player's family (event unlocked), a PageCard «Carta» with its illustration (events/unlock_<id>,
## from the art branch; without it the card goes without), what it is, the goal it brings and, when the tutorial
## hints are on and it has one, «Ver capítulo» (its tutorial chapter). It does not pause; closing it gives
## unlock_seen {what: card}. One at a time: the next waits, and so do they while the Forja viva is open. Listens to Events itself (like EventCard); gives only the
## unlock_seen order, through Game.give.

signal chapter_requested(chapter: String)

var shown: Array = []       # unlock ids shown (tests, smoke)
var current: String = ""
var _queue: Array = []
var _chapter: String = ""


func _ready() -> void:
	super._ready()
	button_pressed.connect(_on_button)
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			for e: Dictionary in events:
				if str(e.get("type", "")) == "unlocked":
					show_for(g.get("sim") as Sim, str(e.get("family", "")), str(e.get("unlock", ""))))


## Shows the card of unlock `id` of `fam` (only the player's family, only unlocks with a card), or queues it.
func show_for(sim: Sim, fam: String, id: String) -> void:
	if fam != SimQuery.player_family(sim.state):
		return
	var d := data_for(sim, id)
	if d.is_empty():
		return
	if visible or suspended or _blocked():
		_queue.append(d)
		return
	_show(d)


## A screen that should not be covered is open (the Forja viva while a piece is forged): the cards wait.
func _blocked() -> bool:
	return is_inside_tree() and get_tree().get_nodes_in_group(LiveForgeScreen.BLOCKS_CARDS).any(
		func(n: Node) -> bool: return (n as CanvasItem).visible)


func _process(delta: float) -> void:
	super._process(delta)
	if not visible and not suspended and not _queue.is_empty() and not _blocked():
		_show(_queue.pop_front())


func _show(d: Dictionary) -> void:
	current = str(d.get("unlock", ""))
	_chapter = str(d.get("chapter", ""))
	shown.append(current)
	show_page(d)
	ViewConfig.info("UnlockCard", "show %s (chapter=%s)" % [current, _chapter])


## The card's data: {} for an unlock without card (card: false) or unknown.
static func data_for(sim: Sim, id: String) -> Dictionary:
	var u := Unlocks.def(sim, id)
	if u.is_empty() or not bool(u.get("card", true)):
		return {}
	var blocks: Array = [{"type": "paragraph", "text": SimQuery.t_(str(u.get("desc_key", "")))}]
	var goal := str(u.get("goal", ""))
	if goal != "" and sim.catalog.objectives().has(goal):
		blocks.append({"type": "effects", "items": [{"text": SimQuery.t_("unlock.goal") % SimQuery.t_(str(
			sim.catalog.objectives()[goal].get("name_key", ""))), "sign": "+"}]})
	var buttons: Array = []
	var chapter := str(u.get("chapter", ""))
	if chapter != "" and bool(Settings.value("game/tutorial_hints")):
		buttons.append({"id": "chapter", "text": SimQuery.t_("unlock.chapter")})
	buttons.append({"id": "ok", "text": SimQuery.t_("unlock.ok"), "primary": true})
	return {"template": "card", "unlock": id, "chapter": chapter, "title": SimQuery.t_("unlock.new") % SimQuery.t_(str(
		u.get("name_key", ""))), "image": VisualPaths.illustration("events", "unlock_" + id), "blocks": blocks,
		"seal": {"text": "N"}, "buttons": buttons, "sticky": true}


func _on_button(id: String) -> void:
	if id == "chapter" and _chapter != "":
		chapter_requested.emit(_chapter)


func close() -> void:
	var was := visible
	var id := current
	super.close()
	if not was:
		return
	var g := get_node_or_null("/root/Game")
	if g != null and g.get("sim") != null and id != "":
		var sim: Sim = g.get("sim")
		var head := str(sim.state.families.get(SimQuery.player_family(sim.state), {}).get("head", ""))
		if head != "":
			g.call("give", {"type": "unlock_seen", "actor": head, "unlock": id, "what": "card"})
	current = ""
	if not _queue.is_empty():
		_show(_queue.pop_front())
