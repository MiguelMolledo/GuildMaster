class_name DuelScreen
extends Control
## The duel screen «a tres tiempos» (docs/ui/mecanicas/combate.md; rules: docs/gdd/04e_combate.md, sim/combat/).
## PROTOTYPE: not wired to the game. It opens over a paused game from --duel-test or --smoke-script=duel, builds the
## two fighters from the state (stats, equipment) and plays a Duel with the player on side 0; nothing is saved and no
## consequence is applied (the result card lists the proposed ones). When the design is approved the choices become the
## order `duel_move` (Orders.apply) and the Duel lives in the state; this screen would then only read it.
##
## What it shows: the two portraits (PortraitFrame) and sprites (DuelArena), touches and breath of each (DuelPips), the
## lance and who leads, the gesture of the rival with its reliability (or how well the rival reads you), the three
## actions with their breath cost (keys 1, 2, 3; disabled without breath), Rendirse (R, only in duels that allow it),
## Resolver sin jugar (A), the last lances, and the result on a PageCard. Esc closes it.

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

@onready var _header: Label = %Header
@onready var _sub: Label = %Sub
@onready var _arena: DuelArena = %Arena
@onready var _portraits: Array[PortraitFrame] = [%LeftPortrait, %RightPortrait]
@onready var _names: Array[Label] = [%LeftName, %RightName]
@onready var _touches: Array[DuelPips] = [%LeftTouches, %RightTouches]
@onready var _breath: Array[DuelPips] = [%LeftBreath, %RightBreath]
@onready var _breath_text: Array[Label] = [%LeftBreathText, %RightBreathText]
@onready var _weapons: Array[Label] = [%LeftWeapon, %RightWeapon]
@onready var _g_title: Label = %GestureTitle
@onready var _g_text: Label = %GestureText
@onready var _g_read: Label = %Reliability
@onready var _buttons: Dictionary = {"strike": %Strike, "parry": %Parry, "feint": %Feint}
@onready var _yield: Button = %Yield
@onready var _auto: Button = %Auto
@onready var _log: Label = %Log
@onready var _result: PageCard = %Result


func _ready() -> void:
	visible = false
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


## A fighter for the rules from a character of the state: its stats and kit (weapon: a weapons id that overrides the
## equipped one, "" = what it carries).
static func fighter_of(combat: Dictionary, state: WorldState, chr: String, weapon: String = "") -> Dictionary:
	var ch: Dictionary = state.characters.get(chr, {})
	var eq: Dictionary = ch.get("equipment", {}) if ch.get("equipment") is Dictionary else {}
	var w := weapon if weapon != "" else CombatRules.weapon_for(combat, eq)
	return CombatRules.fighter(chr, ch.get("stats", {}), w, CombatRules.armored(combat, eq))


## Opens a test duel between characters `a` (the player, challenger) and `b` of `state`.
func open_test(state: WorldState, combat: Dictionary, a: String, b: String, kind: String = "first_blood",
		weapon: String = "", seed: int = 1) -> void:
	_args = {"a": a, "b": b, "kind": kind, "weapon": weapon, "seed": seed}
	_state = state
	cfg = combat
	_chars.clear()
	_families.clear()
	for chr: String in [a, b]:
		var ch: Dictionary = (state.characters.get(chr, {}) as Dictionary).duplicate()
		ch["id"] = chr
		_chars.append(ch)
		_families.append(state.families.get(str(ch.get("family", "")), {}))
	duel = Duel.create(cfg, "duel_test_%d" % seed, seed, fighter_of(cfg, state, a, weapon),
		fighter_of(cfg, state, b, weapon), kind, player)
	_shown = 0
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
	_arena.setup(_chars, _families)
	visible = true
	UiAnim.panel_in(%Frame)
	if OS.is_debug_build():
		print("[DuelScreen] abre: %s contra %s, %s, arma %s, semilla %d" % [_full_name(0), _full_name(1), kind,
			weapon if weapon != "" else "la suya", seed])
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
	var r := duel.choose(player, action)
	if OS.is_debug_build():
		print("[DuelScreen] elige %s -> %s" % [action, "ok" if bool(r["ok"]) else str(r["reason"])])
	if not bool(r["ok"]):
		UiFeel.shake(_buttons.get(action, _yield) as Control)
		return
	_play_pending()


func _auto_finish() -> void:
	if busy or duel == null or duel.over():
		return
	duel.auto_finish()
	_play_pending(true)


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
	for e: String in (tr("combat.result.effects.%s" % key)).split("|"):
		effects.append({"text": e.replace("%s", _first(rival)), "sign": "+" if e.contains("+") else ("-" if e.contains("−") else "")})
	_result.show_page({"template": "card", "title": tr("combat.result.%s" % key), "sticky": true,
		"blocks": [
			{"type": "paragraph", "text": tr("combat.result.text") % [_first(player), int(t[player]), int(t[rival]),
				_first(rival), int(r["lances"])]},
			{"type": "figures", "items": [{"label": tr("combat.ui.touches"), "value": "%d–%d" % [int(t[player]), int(t[rival])]},
				{"label": tr("combat.ui.lances"), "value": str(int(r["lances"]))}]},
			{"type": "divider"},
			{"type": "paragraph", "text": tr("combat.result.proposal")},
			{"type": "effects", "items": effects}],
		"buttons": [{"id": "again", "text": tr("combat.ui.again"), "primary": true}, {"id": "close", "text": tr("combat.ui.close")}]})
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
		close()
	elif _result.visible:
		return
	elif KEYS.has(k):
		_choose(str(KEYS[k]))
	elif k == KEY_R and _yield.visible:
		_choose("yield")
	elif k == KEY_A:
		_auto_finish()
	else:
		return
	get_viewport().set_input_as_handled()
