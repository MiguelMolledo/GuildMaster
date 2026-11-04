class_name DuelDirector
extends Node
## The duel in the game for the player's family (docs/ui/mecanicas/combate.md §2, §4; rules: sim/combat/duels.gd).
## Owns, in the app's CardsLayer (the tutorial finds them there): the challenge card DuelCard (a PageCard: the cause,
## the odds, what is at stake, one button per cause, «Pelear aquí sin reto» when it can, Cancel), the answer and
## no-show cards (the same PageCard), and the DuelScreen. Listens to the sim's events: duel_answered (the rival
## accepts or refuses), duel_started with the player's side (pauses the game and opens the screen: one lance = one
## order through Game.step_now), duel_finished by no-show or cancelled (its card). The notices (the call at dawn, the
## result) are the sim's (Notices). Gives orders only through `give` (Game.give) and Game.step_now.

const SCREEN: String = "res://game/ui/duel_screen.tscn"
const CARD: String = "res://game/ui/page_card.tscn"

var give: Callable = Callable()
var game: Node = null           # the Game autoload (looked up: the tests run without autoloads)
var screen: DuelScreen = null
var card: PageCard = null
var _layer: Node = null
var _pending: Dictionary = {}   # the card's choice: {actor, target, causes}
var _was_paused: bool = false


## `layer`: where the card and the screen go (the app's CardsLayer).
func setup(layer: Node, order_sink: Callable) -> void:
	_layer = layer
	give = order_sink
	game = get_node_or_null("/root/Game")
	add_to_group("duel_director")
	card = (load(CARD) as PackedScene).instantiate() as PageCard
	card.name = "DuelCard"
	card.visible = false
	layer.add_child(card)
	card.button_pressed.connect(_on_card_button)
	screen = (load(SCREEN) as PackedScene).instantiate() as DuelScreen
	screen.name = "DuelScreen"
	layer.add_child(screen)
	screen.closed.connect(_on_screen_closed)
	var events := get_node_or_null("/root/Events")
	if events != null:
		events.connect("sim_event", _on_sim_event)


func _sim() -> Sim:
	return game.get("sim") as Sim if game != null else null


func _fam() -> String:
	return SimQuery.player_family(_sim().state) if _sim() != null else ""


func _name(chr: String) -> String:
	return str(_sim().state.characters.get(chr, {}).get("name", chr))


## The challenge card of `actor` against `target` (from the townsperson's sheet).
func show_challenge(actor: String, target: String) -> void:
	var sim: Sim = _sim()
	if sim == null:
		return
	var causes := Duels.causes(sim, actor, target)
	var why := Duels.challenge_status(sim, actor, target, "", "first_blood", false)
	var c: Dictionary = sim.catalog.combat.get("consequences", {})
	var p := Duels.win_chance(sim, actor, target, "ui|%s|%s|%d" % [actor, target, Clock.day(int(sim.state.clock["minute"]))])
	var seen := Duels.witnesses(sim, actor, int(Duels.cfg(sim).get("witness_tiles", 8))).size()
	var band := "good" if p >= 0.55 else ("even" if p >= 0.4 else "bad")
	var blocks: Array = [
		{"type": "paragraph", "text": tr("combat.card.when") % _name(target)},
		{"type": "figures", "items": [{"label": tr("combat.card.odds"), "value": tr("combat.card.band_" + band) % roundi(p * 100.0)},
			{"label": tr("combat.card.witnesses"), "value": str(seen)}]},
		{"type": "effects", "items": [
			{"text": tr("combat.card.if_win") % SocialKit.signed(int(c.get("win", {}).get("reputation", 5))), "sign": "+"},
			{"text": tr("combat.card.if_lose") % SocialKit.signed(int(c.get("lose", {}).get("reputation", -2))), "sign": "-"},
			{"text": tr("combat.card.if_refuse") % [_name(target), SocialKit.signed(int(c.get("refuse", {}).get("reputation", -10)))]
				if seen > 0 else tr("combat.card.if_refuse_unseen") % _name(target), "sign": ""}]},
		{"type": "paragraph", "text": tr("combat.card.no_show")}]
	var buttons: Array = []
	if why in ["", "too_far"]:
		for x: Dictionary in causes:
			var txt := tr("combat.card.for.%s" % str(x["cause"]))
			if str(x["cause"]) == "courtship":
				txt = txt % _name(str(x["about"]))
			buttons.append({"id": "cause:" + str(x["cause"]), "text": txt, "primary": true})
	else:
		blocks.append({"type": "paragraph", "text": SimQuery.reason_text(why)})
	if Duels.brawl_status(sim, actor, target) == "":
		buttons.append({"id": "brawl", "text": tr("combat.card.brawl")})
	buttons.append({"id": "cancel", "text": tr("combat.ui.close")})
	_pending = {"actor": actor, "target": target}
	var page := {"template": "card", "title": tr("combat.card.title") % _name(target), "sticky": true, "blocks": blocks,
		"buttons": buttons}
	var ill := VisualPaths.duel_illustration("challenge")
	if ill != null:
		page["image"] = ill
	card.show_page(page)
	ViewConfig.info("DuelDirector", "carta de reto: %s -> %s (causas %s, %s, p=%.2f, testigos %d)" % [actor, target,
		causes.map(func(x: Dictionary) -> String: return str(x["cause"])), why if why != "" else "puede", p, seen])


func _on_card_button(id: String) -> void:
	var sim: Sim = _sim()
	if sim == null or _pending.is_empty():
		return
	var actor := str(_pending.get("actor", ""))
	var target := str(_pending.get("target", ""))
	if id.begins_with("cause:"):
		_reach({"type": "duel_challenge", "actor": actor, "target": target, "cause": id.substr(6), "kind": "first_blood"})
	elif id == "brawl":
		_reach({"type": "duel_brawl", "actor": actor, "target": target})
	_pending = {}


## The order at once in range, else walking to the target first with the order queued behind (like the NPC sheet).
func _reach(o: Dictionary) -> void:
	var sim: Sim = _sim()
	var actor := str(o["actor"])
	var orders: Array = []
	if NpcActions.in_range(sim, actor, str(o["target"])):
		orders.append(o)
	else:
		var spot := Courtship.spot(sim.state, str(o["target"]))
		if str(sim.state.characters[actor].get("location", "")) != "":
			orders.append({"type": "exit_building", "actor": actor})
			orders.append({"type": "move_to", "actor": actor, "tile": spot, "queued": true})
		else:
			orders.append({"type": "move_to", "actor": actor, "tile": spot})
		var q := o.duplicate()
		q["queued"] = true
		orders.append(q)
	for x: Dictionary in orders:
		ViewConfig.info("DuelDirector", "orden %s" % [x])
		if give.is_valid():
			give.call(x)


func _on_sim_event(e: Dictionary) -> void:
	var fam := _fam()
	if fam == "":
		return
	match str(e.get("type", "")):
		"duel_answered":
			if str(e.get("family", "")) == fam:
				_answer_card(e)
		"duel_started":
			if str(e.get("family", "")) == fam and int(e.get("player_side", -1)) >= 0:
				_open_screen(str(e["duel"]))
		"duel_finished":
			var mine := str(e.get("family", "")) == fam or str(e.get("target_family", "")) == fam
			if mine and str(e.get("outcome", "")) == "no_show":
				_no_show_card(e)


func _answer_card(e: Dictionary) -> void:
	var rec := Duels.duel_of(_sim().state, str(e["duel"]))
	var rival := _name(str(e.get("actor", "")))
	var accept := str(e.get("answer", "")) == "accept"
	var blocks: Array = []
	if accept:
		var at := int(rec.get("at", 0))
		blocks.append({"type": "paragraph", "text": tr("combat.card.accepted") % [Clock.day(at) + 1, Clock.hour(at)]})
		blocks.append({"type": "paragraph", "text": tr("combat.card.accepted_go") % int(Duels.cfg(_sim()).get("call_before", 30))})
	else:
		blocks.append({"type": "paragraph", "text": tr("combat.card.refused") % rival})
	card.show_page({"template": "notice", "title": tr("combat.card.answer_yes" if accept else "combat.card.answer_no") % rival,
		"blocks": blocks, "buttons": [{"id": "ok", "text": tr("combat.ui.close"), "primary": true}]})


func _no_show_card(e: Dictionary) -> void:
	var fam := _fam()
	var absent := str(e.get("absent", ""))
	var mine := absent != "" and str(_sim().state.characters.get(absent, {}).get("family", "")) == fam
	var key := "combat.card.no_show_you" if mine else ("combat.card.no_show_rival" if absent != "" else "combat.card.cancelled")
	card.show_page({"template": "notice", "title": tr("combat.card.no_show_title"), "blocks": [
		{"type": "paragraph", "text": tr(key)}], "buttons": [{"id": "ok", "text": tr("combat.ui.close"), "primary": true}]})


func _open_screen(id: String) -> void:
	_was_paused = bool(game.get("paused"))
	game.call("set_paused", true)
	card.close()
	screen.open_game(_sim(), id, Callable(game, "step_now"))
	ViewConfig.info("DuelDirector", "duelo %s: pantalla abierta, partida en pausa" % id)


func _on_screen_closed() -> void:
	if screen.game_mode:
		game.call("set_paused", _was_paused)
		ViewConfig.info("DuelDirector", "duelo cerrado: la partida vuelve (pausa=%s)" % _was_paused)
