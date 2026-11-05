extends Node
## Scripted capture of the interiors (--smoke-script=interiores; through `grimoire heavy` with --always-on-top): for
## each artisan trade (blacksmith, carpenter, mason, tailor) a new game, its workshop in management mode without
## upgrades and with every upgrade of its tree done (capture only: the state is edited directly), then the town's
## armory. Shots reports/shots/interiores_<what>.png, the reference of docs/arte/interiores.md (before and after).
## Prints "[SmokeInteriores] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"

var app: Node = null
var timeout: float = 90.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []  # [shot name, prepare: Callable]
var _delay: float = 0.0       # extra (or less) time before this step's shot
var _later: Callable = Callable()
var _later_at: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	for p: String in ["blacksmith", "carpenter", "mason", "tailor"]:
		_steps.append([p, func() -> void: _start(p)])
		_steps.append([p + "_mejoras", func() -> void: _all_upgrades()])
		if p == "blacksmith":
			# 04g 4.6.5.3-4.6.5.5: Hugo walks to the anvil and works there, a customer at the counter, upstairs
			_steps.append([p + "_andando", func() -> void: _hugo_to("anvil", 0.35)])
			_steps.append([p + "_trabajando", func() -> void: _wait()])
			_steps.append([p + "_cliente", func() -> void: _customer()])
			_steps.append([p + "_arriba", func() -> void: _upstairs()])
	_steps.append(["armory", func() -> void: _armory()])
	_steps.append(["house", func() -> void: _house()])
	_steps.append(["house_arriba", func() -> void: _upstairs()])
	print("[SmokeInteriores] start (%d shots)" % _steps.size())


func _start(p: String) -> void:
	var r := NewGame.from_start(Game.sim.catalog, "artisan_" + p, "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "artisan_%s starts" % p)
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	app.open_interior(BLD, true)


func _all_upgrades() -> void:
	var b: Dictionary = Game.sim.state.buildings[BLD]
	for u: Variant in Game.sim.catalog.upgrade_tree(str(b["type"])):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		Upgrades.complete(Game.sim, BLD, id)
	app.close_interior()
	app.open_interior(BLD, true)
	_check((b["upgrades"] as Array).size() > 0, "%s: upgrades done" % str(b["type"]))


## Hugo (the protagonist) inside, selected, sent to `zone`; the shot is taken `after` seconds later (mid-walk).
func _hugo_to(zone: String, after: float) -> void:
	var hugo := "chr_0001"
	var ch: Dictionary = Game.sim.state.characters[hugo]
	ch["location"] = BLD
	ch["station"] = ""
	app.close_interior()
	app.world().select(hugo)
	app.open_interior(BLD, false)
	Game.set_paused(false)   # an order in pause waits for the resume
	_later = func() -> void: Game.give({"type": "go_to_station", "actor": hugo, "zone": zone})
	_later_at = 0.5          # after the fade into the interior
	_delay = 1.2 - (_later_at + after)


func _wait() -> void:
	_delay = -1.5   # a longer look: he arrives and works


## A townsperson as the counter's customer, inside, and two swords for sale on the display (capture only).
func _customer() -> void:
	Game.set_paused(true)   # the town would walk it away at once: it was put inside by hand
	var st := Game.sim.state
	Inventory.add(st.buildings[BLD]["inventory"], Game.sim.catalog, "sword", 1, 2)
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: Variant in ids:
		var c: Dictionary = st.characters[id]
		if TownLife.is_townsperson(st, str(id)) and c.get("town") is Dictionary and str(c.get("location", "")) != BLD:
			c["town"]["customer"] = BLD
			c["town"]["customer_since"] = int(st.clock["minute"]) - 20
			c["location"] = BLD
			_check(true, "a customer inside: %s" % id)
			_later = func() -> void: _check(Counter.is_customer_of(st, str(id), BLD) and str(st.characters[id].get(
				"location", "")) == BLD, "%s still the counter's customer inside" % id)
			_later_at = 1.0
			break


func _upstairs() -> void:
	var stage := app.get("_interior").get_node_or_null("InteriorStage") as InteriorStage
	_check(stage != null, "the interior has its stage")
	if stage != null:
		stage.show_level(1)


func _armory() -> void:
	app.close_interior()
	var found := ""
	var ids: Array = Game.sim.state.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		if str(Game.sim.state.buildings[id].get("type", "")) == "armory":
			found = str(id)
			break
	_check(found != "", "an armory in town")
	if found != "":
		app.open_interior(found, true)


## The family's house (data/interiors/house.json): the first building of type house.
func _house() -> void:
	app.close_interior()
	var found := ""
	var ids: Array = Game.sim.state.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		if str(Game.sim.state.buildings[id].get("type", "")) == "house":
			found = str(id)
			break
	_check(found != "", "a house in town")
	if found != "":
		app.open_interior(found, true)


func _check(cond: bool, what: String) -> void:
	print("[SmokeInteriores] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeInteriores] TIMEOUT at %d" % _i)
		get_tree().quit(1)
		return
	if _later.is_valid() and _t >= _later_at:
		_later.call()
		_later = Callable()
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < 1.2 - _delay:
		return
	else:
		_delay = 0.0
		app.save_shot("interiores_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeInteriores] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
