extends Node
## Scripted captures of the social panels (--smoke-script=social; through `grimoire heavy` with --always-on-top),
## one section per document of docs/ui/mecanicas/ (--social=ciudad,familia,...; all by default). Each step loads its
## scenario, puts the people and the camera where the mock-up has them, opens the panel through the HUD's own calls
## and saves docs/ui/maquetas/<doc>_hoy_<what>.png from reports/shots/ (the app's save_shot, 960×540 × the window's
## whole factor; the copy to docs/ is done by hand at 960×540). Quits when done, or after `timeout` seconds.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const BOARD_SERVICE: Vector2i = Vector2i(16, 21)

var app: Node = null
var timeout: float = 240.0
var _steps: Array = []   # [section, shot, setup: Callable, wait]
var _i: int = -1
var _t: float = 0.0
var _total: float = 0.0
var _armed: bool = false


func _ready() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
		elif a.begins_with("--social="):
			only = a.substr(9).split(",")
	for s: Array in _sections():
		if only.is_empty() or str(s[0]) in only:
			_steps.append(s)
	print("[SmokeSocial] start (%d shots, timeout=%.0f s)" % [_steps.size(), timeout])


func _sections() -> Array:
	return [
		["ciudad", "plaza", _ciudad_plaza, 1.0],
		["ciudad", "ficha", _ciudad_ficha, 0.8],
		["ciudad", "tablon", _ciudad_tablon, 0.8],
		["ciudad", "microevento", _ciudad_mev, 0.8],
		["familia", "arbol", _familia_arbol, 0.8],
		["familia", "sucesion", _familia_sucesion, 0.8],
		["familia", "tarjetas_vida", _familia_nacimiento, 0.8],
		["familia", "escuela", _familia_escuela, 0.8],
		["cortejo", "panel", _cortejo_panel, 0.8],
		["cortejo", "propuesta", _cortejo_propuesta, 0.8],
		["cortejo", "boda", _cortejo_boda, 0.8],
	]


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeSocial] TIMEOUT in step %d" % _i)
		app.save_shot("social_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			_next()
		return
	if _t >= float(_steps[_i][3]):
		var s: Array = _steps[_i]
		app.save_shot("%s_hoy_%s" % [_doc(str(s[0])), str(s[1])])
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeSocial] done")
		get_tree().quit(0)
		return
	app.hud().close_panels()
	var card := app.get_node_or_null("%SuccessionCard") as SuccessionCard
	if card != null and card.visible:
		card.finish()
	var wed := app.get_node_or_null("%WeddingCard") as WeddingCard
	if wed != null:
		wed.close()
	var dlg := get_tree().root.get_node_or_null("SocialConfirmLayer/Confirm") as ConfirmDialog
	if dlg != null:
		dlg.close()
	var s: Array = _steps[_i]
	print("[SmokeSocial] %s/%s" % [s[0], s[1]])
	(s[2] as Callable).call()


static func _doc(section: String) -> String:
	return {"ciudad": "ciudad_viva", "familia": "familia", "cortejo": "cortejo_y_boda", "titulos": "titulos_y_reputacion",
		"cargos": "cargos_y_elecciones", "tribunal": "tribunal", "rivales": "rivales"}.get(section, section)


# --- helpers --------------------------------------------------------------------------------------------------------

func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeSocial] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	Game.start(r["state"])
	Game.set_paused(true)
	app.world().select(HERO)
	return true


func _run_to(day: int, hh: int, mm: int) -> void:
	var n := day * Clock.MINUTES_PER_DAY + hh * 60 + mm - int(Game.sim.state.clock["minute"])
	if n > 0:
		Game.sim.run_minutes(n)


func _centre(tile: Vector2i) -> void:
	app.world().camera().center_on(Iso.tile_to_world(tile))


func _stand(who: String, tile: Vector2i) -> void:
	var ch: Dictionary = Game.sim.state.characters[who]
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["position"] = [tile.x, tile.y]


# --- ciudad viva ----------------------------------------------------------------------------------------------------

func _ciudad_plaza() -> void:
	if _load("plaza_dusk"):
		_run_to(1, 20, 10)
		var keeper := TownLife.stall_keeper(Game.sim.state, Game.sim.catalog, "food")
		Emotions.add(Game.sim, keeper, "angry", FAM)
		_centre(Vector2i(19, 20))


func _ciudad_ficha() -> void:
	if _load("plaza_dusk"):
		_run_to(1, 19, 50)
		var keeper := TownLife.stall_keeper(Game.sim.state, Game.sim.catalog, "food")
		Emotions.add(Game.sim, keeper, "angry", FAM)
		Emotions.change_relation(Game.sim, HERO, keeper, -30, "smoke")
		var p: Array = Game.sim.state.characters[keeper]["position"]
		_stand(HERO, Vector2i(int(p[0]), int(p[1]) + 1))
		_centre(Vector2i(int(p[0]) - 3, int(p[1])))
		app.hud().open_npc(keeper)


func _ciudad_tablon() -> void:
	if _load("town_e_start"):
		var now := int(Game.sim.state.clock["minute"])
		Game.sim.state.clock["minute"] = Clock.day(now) * Clock.MINUTES_PER_DAY + 10 * 60
		Contracts.post_scripted(Game.sim.state, Game.sim.catalog, Game.sim.catalog.starts()["artisan_blacksmith"]["contracts"])
		_stand(HERO, BOARD_SERVICE)
		var board: Array = Game.sim.state.contracts["board"]
		Orders.apply(Game.sim, {"type": "accept_contract", "actor": HERO, "contract": str(board[0]["id"])})
		Inventory.add(Game.sim.state.characters[HERO]["inventory"], Game.sim.catalog, "hammer", 0, 1)
		Contracts.post_random(Game.sim)
		Contracts.post_random(Game.sim)
		_centre(BOARD_SERVICE + Vector2i(-2, 0))
		app.hud().board_panel().open_for(Game.sim, HERO)


func _ciudad_mev() -> void:
	if _load("microevent_card"):
		var first: Dictionary = Game.sim.state.microevents["active"][0]
		var second := first.duplicate(true)
		second["id"] = str(first["id"]) + "_b"
		(Game.sim.state.microevents["active"] as Array).append(second)  # «+1 más»
		_centre(Vector2i(26, 20))


# --- familia --------------------------------------------------------------------------------------------------------

func _familia_arbol() -> void:
	if _load("founder_old"):
		app.hud().toggle_tree()
		var heir := Kin.heir(Game.sim, FAM)
		app.hud().tree_panel().pick(heir)


func _familia_sucesion() -> void:
	if _load("founder_old"):
		_centre(Vector2i(19, 20))
		Game.sim.events.clear()
		Lifecycle.die(Game.sim, HERO, "old_age")
		Events.publish(Game.sim.events.duplicate(true))   # the app shows the card, as after a step


func _familia_nacimiento() -> void:
	if _load("founder_old"):
		_centre(Vector2i(19, 20))
		var kid := str(Game.sim.state.characters[HERO]["children"][1])
		Events.publish([{"type": "child_born", "family": FAM, "character": kid}])


func _familia_escuela() -> void:
	if _load("founder_old"):
		_centre(Vector2i(19, 20))
		var kid := str(Game.sim.state.characters[HERO]["children"][1])
		Game.sim.state.characters[kid]["life"] = {"school": "pending"}


# --- cortejo --------------------------------------------------------------------------------------------------------

func _court_setup() -> String:
	var c: Dictionary = Courtship.candidates(Game.sim, HERO)[0]
	Courtship.relation(Game.sim.state, HERO, str(c["character"]))["affinity"] = 84
	var cands := Courtship.candidates(Game.sim, HERO)
	Emotions.add(Game.sim, str(cands[cands.size() - 1]["character"]), "angry", FAM)
	return str(c["character"])


func _cortejo_panel() -> void:
	if _load("courtship"):
		_court_setup()
		_centre(Vector2i(19, 20))
		app.hud().open_courtship(HERO)


func _cortejo_propuesta() -> void:
	if _load("courtship"):
		var who := _court_setup()
		var p: Array = Game.sim.state.characters[who].get("position", [19, 20])
		_centre(Vector2i(int(p[0]) - 3, int(p[1])))
		app.hud().open_npc(who)
		var n: NpcPanel = app.hud().npc_panel()
		n.refresh(true)
		n.call("_court_propose")


func _cortejo_boda() -> void:
	if _load("courtship"):
		var who := _court_setup()
		_centre(Vector2i(19, 20))
		Game.sim.events.clear()
		Courtship.marry(Game.sim, HERO, who)
		Events.publish(Game.sim.events.duplicate(true))
