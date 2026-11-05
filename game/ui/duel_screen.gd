class_name DuelScreen
extends Control
## The duel screen «a tres tiempos» (docs/ui/mecanicas/combate.md; rules: docs/gdd/04e_combate.md, sim/combat/).
## In the game (open_game, from DuelDirector when a duel of the player's family starts): it reads the duel kept in the
## state (Duels, state.duels.open[id].duel) and gives the orders duel_move / duel_auto through `give` (Game.step_now:
## one lance = one game minute, applied at once while the game is paused); the result card lists the consequences the
## sim applied. The prototype (open_test, --duel-test): a Duel of its own, nothing saved, the proposed consequences.
##
## What it shows: the two portraits (PortraitFrame) and sprites (DuelArena), touches and breath of each (DuelPips), the
## lance and who leads, the gesture of the rival with its reliability (or how well the rival reads you), the three
## actions with their breath cost (keys 1, 2, 3; disabled without breath), Rendirse (R, only in duels that allow it),
## Resolver sin jugar (A), the last lances, and the result on a PageCard. Esc: in the game, Resolver sin jugar (a duel
## is not left half fought); in the prototype, it closes. Icons and the card's illustration from VisualPaths when the
## art exists (duel_icon, duel_illustration).

signal closed
signal lance_done(index: int)   # a lance's animation ended (the smoke script takes its capture)
signal finished(result: Dictionary)

const KEYS: Dictionary = {KEY_1: "strike", KEY_2: "parry", KEY_3: "feint"}

var duel: Duel = null
var player: int = 0
var cfg: Dictionary = {}
var busy: bool = false
var _state: WorldState = null
var _chars: Array = []
var _families: Array = []
var _shown: int = 0
var _args: Dictionary = {}
var game_mode: bool = false
var duel_id: String = ""
var _give: Callable = Callable()       # Game.step_now: the order now, its step's events back
var _sim: Sim = null
var _effects: Array = []               # what the sim applied when it closed (reputation, relation, affinity events)

var _header: Label = null
var _sub: Label = null
var _arena: DuelArena = null
var _portraits: Array[PortraitFrame] = []
var _names: Array[Label] = []
var _touches: Array[DuelPips] = []
var _breath: Array[DuelPips] = []
var _breath_text: Array[Label] = []
var _weapons: Array[Label] = []
var _g_title: Label = null
var _g_text: Label = null
var _g_read: Label = null
var _buttons: Dictionary = {}
var _yield: Button = null
var _auto: Button = null
var _log: Label = null
var _result: PageCard = null
var _bound: bool = false
var _wired: bool = false


## The nodes of the scene (also outside the tree: the tests).
func _bind() -> void:
	if _bound:
		return
	_bound = true
	_header = get_node("%Header") as Label
	_sub = get_node("%Sub") as Label
	_arena = get_node("%Arena") as DuelArena
	_portraits = [get_node("%LeftPortrait") as PortraitFrame, get_node("%RightPortrait") as PortraitFrame]
	_names = [get_node("%LeftName") as Label, get_node("%RightName") as Label]
	_touches = [get_node("%LeftTouches") as DuelPips, get_node("%RightTouches") as DuelPips]
	_breath = [get_node("%LeftBreath") as DuelPips, get_node("%RightBreath") as DuelPips]
	_breath_text = [get_node("%LeftBreathText") as Label, get_node("%RightBreathText") as Label]
	_weapons = [get_node("%LeftWeapon") as Label, get_node("%RightWeapon") as Label]
	_g_title = get_node("%GestureTitle") as Label
	_g_text = get_node("%GestureText") as Label
	_g_read = get_node("%Reliability") as Label
	_buttons = {"strike": get_node("%Strike"), "parry": get_node("%Parry"), "feint": get_node("%Feint")}
	_yield = get_node("%Yield") as Button
	_auto = get_node("%Auto") as Button
	_log = get_node("%Log") as Label
	_result = get_node("%Result") as PageCard


func _ready() -> void:
	visible = false
	_wire()


func _wire() -> void:
	if _wired:
		return
	_wired = true
	_bind()
	MenuKit.add_hint(_buttons["strike"], "1")
	MenuKit.add_hint(_buttons["parry"], "2")
	MenuKit.add_hint(_buttons["feint"], "3")
	MenuKit.add_hint(_yield, "R")
	MenuKit.add_hint(_auto, "A")
	for a: String in _buttons:
		(_buttons[a] as Button).pressed.connect(_choose.bind(a))
	_yield.pressed.connect(_choose.bind("yield"))
	_auto.pressed.connect(_auto_finish)
	_arena.lance_shown.connect(_on_lance_shown)
	_result.button_pressed.connect(_on_result_button)


## Opens a test duel between characters `a` (the player, challenger) and `b` of `state` (the prototype).
func open_test(state: WorldState, combat: Dictionary, a: String, b: String, kind: String = "first_blood",
		weapon: String = "", seed: int = 1) -> void:
	_args = {"a": a, "b": b, "kind": kind, "weapon": weapon, "seed": seed}
	game_mode = false
	cfg = combat
	player = 0
	var fa := CombatRules.fighter(a, state.characters.get(a, {}).get("stats", {}),
		weapon if weapon != "" else CombatRules.weapon_for(cfg, state.characters.get(a, {}).get("equipment", {})))
	var fb := CombatRules.fighter(b, state.characters.get(b, {}).get("stats", {}),
		weapon if weapon != "" else CombatRules.weapon_for(cfg, state.characters.get(b, {}).get("equipment", {})))
	duel = Duel.create(cfg, "duel_test_%d" % seed, seed, fa, fb, kind, player)
	_wire()
	_setup(state, a, b)
	if OS.is_debug_build():
		print("[DuelScreen] abre (prueba): %s contra %s, %s, arma %s, semilla %d" % [_full_name(0), _full_name(1), kind,
			weapon if weapon != "" else "la suya", seed])


## Opens the duel `id` of the game, fought now by the player's side; `give` applies an order at once (Game.step_now).
func open_game(sim: Sim, id: String, give: Callable) -> void:
	var rec := Duels.duel_of(sim.state, id)
	if rec.is_empty() or (rec.get("duel", {}) as Dictionary).is_empty():
		return
	game_mode = true
	duel_id = id
	_sim = sim
	_give = give
	cfg = sim.catalog.combat
	duel = Duel.wrap(cfg, rec["duel"])
	player = maxi(0, int(rec["player_side"]))
	_effects.clear()
	_wire()
	_setup(sim.state, str(rec["challenger"]), str(rec["challenged"]))
	if OS.is_debug_build():
		print("[DuelScreen] abre (partida): %s, %s contra %s, jugador en el lado %d" % [id, _full_name(0), _full_name(1),
			player])


func _setup(state: WorldState, a: String, b: String) -> void:
	_state = state
	_chars.clear()
	_families.clear()
	for chr: String in [a, b]:
		var ch: Dictionary = (state.characters.get(chr, {}) as Dictionary).duplicate()
		ch["id"] = chr
		_chars.append(ch)
		_families.append(state.families.get(str(ch.get("family", "")), {}))
	_shown = duel.lances_log().size() if game_mode else 0
	busy = false
	_result.visible = false
	for i: int in 2:
		_portraits[i].big = true
		_portraits[i].show_character(state, [a, b][i], {"gold": i == player})
		_names[i].text = _full_name(i)
		_touches[i].max_value = int(duel.kind().get("touches", 3))
		_breath[i].max_value = CombatRules.breath_max(cfg, duel.fighter(i))
		_weapons[i].text = tr("combat.weapon.%s" % str(duel.fighter(i)["weapon"])) + \
			(" · " + tr("combat.ui.armor") if bool(duel.fighter(i)["armor"]) else "")
	for act: String in _buttons:
		(_buttons[act] as Button).icon = VisualPaths.duel_icon(act, true)
	_yield.icon = VisualPaths.duel_icon("yield", true)
	_auto.icon = VisualPaths.duel_icon("auto", true)
	for i: int in 2:
		_touches[i].icon = VisualPaths.duel_icon("touch", true)
		_breath[i].icon = VisualPaths.duel_icon("breath", true)
	_arena.setup(_chars, _families)
	visible = true
	UiAnim.panel_in(get_node("%Frame") as Control)
	_refresh()


func _full_name(i: int) -> String:
	var ch: Dictionary = _chars[i]
	var fam := str((_families[i] as Dictionary).get("name", ""))
	return "%s %s" % [str(ch.get("name", "?")), fam] if fam != "" else str(ch.get("name", "?"))


func _first(i: int) -> String:
	return str((_chars[i] as Dictionary).get("name", "?"))


func _refresh() -> void:
	if duel == null:
		return
	var v := duel.view(player)
	var rival := 1 - player
	# while a lance is animated, the figures are the ones before it (the lance shown, its touches and breath)
	var lances := duel.lances_log()
	var shown := mini(_shown, lances.size())
	var lance := shown if busy else int(v["lance"])
	_header.text = tr("combat.ui.title") % tr("combat.kind.%s" % str(duel.d["kind"]))
	_sub.text = tr("combat.ui.lance") % [mini(lance + 1, int(duel.kind().get("lances", 9))),
		int(duel.kind().get("lances", 9)), int(duel.kind().get("touches", 3))]
	for i: int in 2:
		var t := duel.touches(i)
		var br := duel.breath(i)
		if busy or shown < lances.size():
			t = 0 if shown == 0 else int((lances[shown - 1] as Dictionary)["touches"][i])
			br = _breath[i].max_value if shown == 0 else int((lances[shown - 1] as Dictionary)["breath"][i])
		_touches[i].value = t
		_breath[i].value = br
		_breath_text[i].text = tr("combat.ui.breath") % [br, _breath[i].max_value]
	_log.text = _log_text()
	if busy:  # the gesture of the lance being shown stays until it ends
		for a: String in _buttons:
			(_buttons[a] as Button).disabled = true
		_yield.disabled = true
		_auto.disabled = true
		for b: Button in [_yield, _auto]:
			b.tooltip_text = tr("ui.why.busy_lance")
		return
	match "over" if duel.over() else str(v["role"]):
		"over":
			_g_title.text = tr("combat.ui.over")
			_g_text.text = ""
			_g_read.text = ""
		"read":
			_g_title.text = tr("combat.ui.rival_leads") % _first(rival)
			_g_text.text = tr("combat.cue.%s" % str(v["cue"]))
			_g_read.text = tr("combat.ui.reliable") % roundi(float(v["read"]) * 10.0)
		"lead":
			_g_title.text = tr("combat.ui.you_lead")
			_g_text.text = tr("combat.ui.you_lead_text") % _first(rival)
			_g_read.text = tr("combat.ui.read_by") % [_first(rival), roundi(float(v["read_by"]) * 10.0)]
		_:
			_g_title.text = tr("combat.ui.blind")
			_g_text.text = tr("combat.ui.blind_text")
			_g_read.text = ""
	var allowed: Array = v["allowed"]
	for a: String in _buttons:
		var b := _buttons[a] as Button
		var c := CombatRules.cost(cfg, a)
		b.text = "%s  %s" % [tr("combat.action.%s" % a), ("+%d" % -c) if c < 0 else ("−%d" % c)]
		b.disabled = busy or duel.over() or not a in allowed
		b.tooltip_text = tr("combat.action.%s.hint" % a) if a in allowed else tr("reason.no_breath")
	_yield.visible = bool(v["can_yield"])
	_yield.disabled = busy or duel.over()
	_auto.disabled = busy or duel.over()
	var off := tr("ui.why.over") if duel.over() else tr("ui.why.busy_lance")   # verificación A7: every off button says why
	for b: Button in [_yield, _auto]:
		if b.disabled:
			b.tooltip_text = off
	for c: Node in _auto.get_parent().get_children():
		if c is Button and (c as Button).disabled and (c as Button).tooltip_text == "":
			(c as Button).tooltip_text = off


func _log_text() -> String:
	var lines: Array[String] = []
	var lances := duel.lances_log()
	for i: int in range(maxi(0, mini(_shown, lances.size()) - 3), mini(_shown, lances.size())):
		var r: Dictionary = lances[i]
		var acts: Array = r["actions"]
		var w := int(r["winner"])
		var who := tr("combat.ui.nobody") if w < 0 else _first(w)
		lines.append(tr("combat.ui.log_line") % [int(r["lance"]) + 1, tr("combat.action.%s" % str(acts[0])),
			tr("combat.action.%s" % str(acts[1])), tr("combat.how.%s" % str(r["how"])), who])
	return "\n".join(lines)


func _choose(action: String) -> void:
	if busy or duel == null or duel.over():
		return
	var r := {"ok": true, "reason": ""}
	if game_mode:
		r = _order({"type": "duel_move", "actor": _me(), "duel": duel_id, "action": action})
	else:
		r = duel.choose(player, action)
	if OS.is_debug_build():
		print("[DuelScreen] elige %s -> %s" % [action, "ok" if bool(r["ok"]) else str(r["reason"])])
	if not bool(r["ok"]):
		UiFeel.shake(_buttons.get(action, _yield) as Control)
		return
	_play_pending()


func _auto_finish() -> void:
	if busy or duel == null or duel.over():
		return
	if game_mode:
		_order({"type": "duel_auto", "actor": _me(), "duel": duel_id})
	else:
		duel.auto_finish()
	_play_pending(true)


## The player's duellist.
func _me() -> String:
	return str((_chars[player] as Dictionary).get("id", ""))


## Gives `o` now (Game.step_now) and keeps what the duel left for the player's family: {ok, reason}.
func _order(o: Dictionary) -> Dictionary:
	if not _give.is_valid():
		return {"ok": false, "reason": "no_game"}
	var events: Array = _give.call(o)
	var fam := str((_chars[player] as Dictionary).get("family", ""))
	for e: Dictionary in events:
		var t := str(e.get("type", ""))
		if t == "order_refused" and str(e.get("order", "")) == str(o["type"]):
			return {"ok": false, "reason": str(e.get("reason", ""))}
		if t == "reputation_changed" and str(e.get("family", "")) == fam and str(e.get("reason", "")).begins_with("duel_"):
			_effects.append({"text": tr("combat.result.rep") % SocialKit.signed(int(e["amount"])),
				"sign": "+" if int(e["amount"]) > 0 else "-"})
		elif t == "relation_changed" and str(e.get("reason", "")).begins_with("duel_") and _me() in [str(e["actor"]),
				str(e["target"])]:
			_effects.append({"text": tr("combat.result.relation") % [_first(1 - player), SocialKit.signed(int(e["amount"]))],
				"sign": "+" if int(e["amount"]) > 0 else "-"})
		elif t == "affinity_changed" and str(e.get("actor", "")) == _me() and str(e.get("reason", "")).begins_with("duel_"):
			_effects.append({"text": tr("combat.result.affinity") % [str(_state.characters.get(str(e["target"]), {}).get(
				"name", "")), SocialKit.signed(int(e["amount"]))], "sign": "+" if int(e["amount"]) > 0 else "-"})
	return {"ok": true, "reason": ""}


## Animates the lances not shown yet, one after the other, then the result if the duel is over.
func _play_pending(fast: bool = false) -> void:
	var lances := duel.lances_log()
	if _shown >= lances.size():
		busy = false
		_refresh()
		if duel.over():
			_show_result()
		return
	busy = true
	_refresh()
	_arena.set_meta("fast", fast)
	_arena.play(lances[_shown], fast)


func _on_lance_shown() -> void:
	_shown += 1
	lance_done.emit(_shown - 1)
	_play_pending(bool(_arena.get_meta("fast", false)))


func _show_result() -> void:
	var r := duel.result()
	var w := int(r["winner"])
	var rival := 1 - player
	var key := "draw" if w < 0 else ("win" if w == player else "lose")
	if int(r["yielded"]) >= 0:
		key = "yielded_you" if int(r["yielded"]) == player else "yielded_rival"
	var t: Array = r["touches"]
	var effects: Array = []
	var intro := tr("combat.result.proposal")
	if game_mode:
		effects = _effects.duplicate()
		intro = tr("combat.result.applied")
		if effects.is_empty():
			effects.append({"text": tr("combat.result.nothing"), "sign": ""})
	else:
		for e: String in (tr("combat.result.effects.%s" % key)).split("|"):
			effects.append({"text": e.replace("%s", _first(rival)), "sign": "+" if e.contains("+") else ("-" if e.contains("−") else "")})
	var buttons: Array = [{"id": "close", "text": tr("combat.ui.close"), "primary": true}]
	if not game_mode:
		buttons = [{"id": "again", "text": tr("combat.ui.again"), "primary": true}, {"id": "close", "text": tr("combat.ui.close")}]
	var page := {"template": "card", "title": tr("combat.result.%s" % key), "sticky": true,
		"blocks": [
			{"type": "paragraph", "text": tr("combat.result.text") % [_first(player), int(t[player]), int(t[rival]),
				_first(rival), int(r["lances"])]},
			{"type": "figures", "items": [{"label": tr("combat.ui.touches"), "value": "%d–%d" % [int(t[player]), int(t[rival])]},
				{"label": tr("combat.ui.lances"), "value": str(int(r["lances"]))}]},
			{"type": "divider"},
			{"type": "paragraph", "text": intro},
			{"type": "effects", "items": effects}],
		"buttons": buttons}
	var ill := VisualPaths.duel_illustration("won" if key in ["win", "yielded_rival"] else ("draw" if key == "draw" else "lost"))
	if ill != null:
		page["image"] = ill
	_result.show_page(page)
	if OS.is_debug_build():
		print("[DuelScreen] resultado: %s (%s), toques %s, lances %d" % [key, r["end"], t, int(r["lances"])])
	finished.emit(r)


func _on_result_button(id: String) -> void:
	if id == "again":
		open_test(_state, cfg, str(_args["a"]), str(_args["b"]), str(_args["kind"]), str(_args["weapon"]),
			int(_args["seed"]) + 1)
	else:
		close()


func close() -> void:
	visible = false
	_result.visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		if game_mode and not duel.over():
			_auto_finish()
		elif not busy:
			close()
	elif _result.visible:
		pass
	elif KEYS.has(k):
		_choose(str(KEYS[k]))
	elif k == KEY_R and _yield.visible:
		_choose("yield")
	elif k == KEY_A:
		_auto_finish()
	# Modal: no key reaches the HUD while the duel is open (R would open the region map, 1-3 pick a group).
	get_viewport().set_input_as_handled()
