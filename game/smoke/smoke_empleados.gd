extends Node
## Scripted capture of H4 (--smoke-script=empleados; run it through `grimoire heavy` with --dev-time and the engine's
## --always-on-top). Scenario two_employees: Joan and Agnès walking from their house to the forge at dawn (h4_mapa),
## the forge in management mode with both at their stations and the cycle bars (h4_forja_empleados), the production
## panel with the queue after adding an entry from it (h4_cola), the staff panel (h4_plantilla) and its hiring tab
## (h4_contratar); two_employees again with its queue emptied: the idle icon over the forge (h4_ocioso). Then
## apprentice_promotion:
## at dawn the promotion is offered; the notices log (h4_avisos) and the click on the notice, which opens the staff
## panel with Accept / Refuse (h4_ascenso). Orders only through the UI paths. Quits when done, or after `timeout`
## seconds with a shot of whatever is on screen.

const BLD := "bld_0001"
const JOAN := "chr_0007"
const AGNES := "chr_0008"

var app: Node = null
var timeout: float = 150.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeEmpleados] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeEmpleados] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _load(scenario: String) -> bool:
	var r := NewGame.from_scenario(scenario)
	if not bool(r.get("ok", false)):
		print("[SmokeEmpleados] scenario %s failed: %s" % [scenario, r.get("error", "")])
		get_tree().quit(1)
		return false
	Game.start(r["state"])
	Game.set_paused(false)
	return true


func _ch(id: String) -> Dictionary:
	return Game.sim.state.characters.get(id, {})


func _centre_on(id: String) -> void:
	var ch := _ch(id)
	var p: Array = ch.get("position", [0, 0])
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(p[0]), int(p[1]))))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeEmpleados] TIMEOUT in step %s" % _step)
		app.save_shot("h4_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("two_employees"):
				Game.set_speed(1)
				_go("walking")
		"walking":
			var both := Routines.state_of(Game.sim, JOAN) not in ["home", "at_work", ""] \
				and Routines.state_of(Game.sim, AGNES) not in ["home", "at_work", ""]
			if both and str(_ch(JOAN).get("location", "")) == "":
				var p: Array = _ch(JOAN).get("path", [])
				if p.size() <= 4:   # nearly there: both on the open street by the forge
					_centre_on(JOAN)
					Game.set_paused(true)
					_go("shot_map")
		"shot_map":
			if _t > 0.4:
				app.save_shot("h4_mapa")
				Game.set_paused(false)
				_go("stations")
		"stations":
			if str(_ch(JOAN).get("station", "")) == "anvil" and str(_ch(AGNES).get("station", "")) == "furnace":
				app.open_interior(BLD, true)
				_go("inside")
		"inside":
			var job := Production.job_view(Game.sim, BLD, "anvil")
			if app.interior_building == BLD and _t > 0.8 and float(job.get("progress", 0.0)) > 0.15:
				app.save_shot("h4_forja_empleados")
				app.interior().show_production(true)
				app.interior().production_panel().select_recipe("forge_ingot")
				app.interior().production_panel().add("forge_ingot", 5)
				_go("queue")
		"queue":
			if _t > 0.6 and (SimQuery.queue_view(Game.sim, BLD)["entries"] as Array).size() >= 2:
				app.save_shot("h4_cola")
				app.interior().show_staff(true, "staff")
				_go("staff")
		"staff":
			if _t > 0.5:
				app.save_shot("h4_plantilla")
				app.interior().staff_panel().show_tab("hire")
				_go("hire")
		"hire":
			if _t > 0.5:
				app.save_shot("h4_contratar")
				if _load("two_employees"):
					Game.give({"type": "queue_remove", "actor": "chr_0001", "building": BLD, "entry": "qen_0001"})
					_go("idle")
		"idle":
			if not SimQuery.idle_employees(Game.sim, BLD).is_empty():
				var d: Array = Game.sim.state.buildings[BLD]["door"]
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(d[0]), int(d[1]))))
				Game.set_paused(true)
				_go("shot_idle")
		"shot_idle":
			if _t > 0.4:
				app.save_shot("h4_ocioso")
				if _load("apprentice_promotion"):
					_go("promotion")
		"promotion":
			if bool((_ch(AGNES).get("job", {}) as Dictionary).get("promotion_offered", false)) and _t > 0.3:
				Game.set_paused(true)
				app.hud().open_ledger("notices")
				_go("notices")
		"notices":
			if _t > 0.5:
				app.save_shot("h4_avisos")
				app.hud().close_panels()
				var n: Array = Notices.list(Game.sim, "fam_0001")
				for x: Dictionary in n:
					if str(x.get("key", "")) == "notice.promotion_offered":
						app.hud().notice_action(x)   # the same call a click on the notice makes
						break
				_go("ascenso")
		"ascenso":
			if _t > 0.8 and app.interior_building == BLD:
				app.save_shot("h4_ascenso")
				_go("done")
				get_tree().quit()
