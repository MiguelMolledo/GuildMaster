extends Node
## Plays the flows of data/flows/<id>.json through the interface (docs/gdd/07_testing.md §7.6): --flow=<id> or
## --flows=all|a,b. Each step is one action of a person (a click on a control, on the town or in a room, a key, a
## wait) followed by its checks (expressions over FlowQuery `q`), a capture (with a window) and the visual checks
## (VisualAudit). Writes reports/verifica/<date>/<flow>/result.json (+ NN_<step>.png and the marked crops in vis/)
## and quits with 0 if every flow passed. Without a window it plays the same steps and skips captures and contrast.
## Options: --verifica-out=<dir> (default reports/verifica/<today>), --flow-seed=<n>, --flow-timeout=<s> (a whole
## flow, 600 by default).
## A step: {"id", "say", one action, "until", "timeout", "fast", "wait", "expect": [...], "soft", "when", "shot"}.
## Actions: "click" / "right_click" / "double_click": a control (UiDriver.find spec); "key": "L" | "@ledger" (+
## "shift"); "world": {"tile"|"building"|"own"|"person"|"service"|"npc"} (+ "button", "double", "shift");
## "station": zone (+ "button"); "door": true; "type": text; "wheel": {"up", "times"}; "pan": [dx, dy] (a middle
## drag); "hold": key + "frames"; "release_focus": true.
## "until": an expression to wait for (real seconds "timeout", 20 by default; "fast": Engine.time_scale meanwhile,
## a harness speed-up that is logged, never an order). "when": the step runs only if it is true (else "omitido").

var app: Node = null
var drv: UiDriver
var q: FlowQuery
var audit: VisualAudit
var out_root: String = ""
var windowed: bool = false
var results: Array = []
var flow_timeout: float = 600.0
var _flow_t0: int = 0
var _seed: int = 3
var keys_mode: bool = false   # --flow-input=keys: every click on a control is done with Tab + Enter (verificación C13)


func _ready() -> void:
	drv = UiDriver.new(get_tree())
	q = FlowQuery.new(app, drv)
	audit = VisualAudit.new()
	windowed = DisplayServer.get_name() != "headless"
	if not windowed:
		get_tree().root.size = Vector2i(1920, 1080)   # no window: the layout of the real 960×540 ×2
	var ids: Array = []
	var date := Time.get_date_string_from_system()
	out_root = ProjectSettings.globalize_path("res://reports/verifica/" + date)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--flow="):
			ids.append(a.substr(7))
		elif a.begins_with("--flows="):
			ids.append_array(_expand(a.substr(8)))
		elif a.begins_with("--verifica-out="):
			out_root = a.substr(15)
		elif a.begins_with("--flow-seed="):
			_seed = a.substr(12).to_int()
		elif a.begins_with("--flow-timeout="):
			flow_timeout = a.substr(15).to_float()
		elif a == "--flow-input=keys":
			keys_mode = true
	Game.order_given.connect(_on_order)
	Events.sim_event.connect(func(e: Dictionary) -> void: q.step_events.append(e))
	print("[Flow] start (flows=%s, window=%s, out=%s)" % [ids, windowed, out_root])
	_run.call_deferred(ids)


static func flow_ids() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at("res://data/flows"):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f.get_basename())
	out.sort()
	return out


func _expand(list: String) -> Array:
	if list == "all":
		return flow_ids()
	if list == "quick":
		var out: Array = []
		for id: String in flow_ids():
			if bool(_load(id).get("quick", false)):
				out.append(id)
		return out
	return Array(list.split(",", false))


func _load(id: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/flows/%s.json" % id))
	return d if d is Dictionary else {}


func _on_order(o: Dictionary) -> void:
	var rec := {"type": str(o.get("type", "")), "via": drv.last_input if drv.last_input != "" else "?"}
	q.step_orders.append(rec)
	q.flow_orders.append(rec)


func _run(ids: Array) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var failed := 0
	for id: String in ids:
		var r := await _run_flow(str(id))
		results.append(r)
		if not bool(r["ok"]):
			failed += 1
	Engine.time_scale = 1.0
	print("[Flow] done: %d flows, %d fail" % [ids.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


# --- one flow -------------------------------------------------------------------------------------------------------

func _run_flow(id: String) -> Dictionary:
	var flow := _load(id)
	var dir := out_root.path_join(id + ("__teclado" if keys_mode else ""))
	DirAccess.make_dir_recursive_absolute(dir.path_join("vis"))
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			DirAccess.remove_absolute(dir.path_join(f))
	for f: String in DirAccess.get_files_at(dir.path_join("vis")):
		DirAccess.remove_absolute(dir.path_join("vis").path_join(f))
	var res := {"id": id + ("__teclado" if keys_mode else ""), "input": "keys" if keys_mode else "mouse",
		"title": str(flow.get("title", id)) + (" (teclado)" if keys_mode else ""), "about": str(flow.get("about", "")),
		"window": windowed, "date": Time.get_datetime_string_from_system(), "ok": true, "steps": [], "orders": [],
		"visual": [], "error": "", "seconds": 0.0, "start": flow.get("start", {}), "covers": flow.get("covers", [])}
	if flow.is_empty():
		res["ok"] = false
		res["error"] = "no existe data/flows/%s.json o no es JSON" % id
		_write(dir, res)
		return res
	print("[Flow] === %s: %s" % [id, res["title"]])
	_flow_t0 = Time.get_ticks_msec()
	q.flow_orders = []
	var seen: Dictionary = {}
	var err := await _start(flow.get("start", {}))
	if err != "":
		res["ok"] = false
		res["error"] = "no arranca: " + err
	var steps: Array = flow.get("steps", [])
	var stop := err != ""
	for i: int in steps.size():
		var step: Dictionary = steps[i]
		var rec := {"n": i + 1, "id": str(step.get("id", "paso_%d" % (i + 1))), "say": str(step.get("say", "")),
			"action": _action_text(step), "ok": true, "error": "", "checks": [], "orders": [], "events": [],
			"shot": "", "screen": "", "visual": [], "seconds": 0.0, "status": "ok", "input": []}
		if stop:
			rec["status"] = "no se corrió"
			rec["ok"] = false
			res["steps"].append(rec)
			continue
		if (Time.get_ticks_msec() - _flow_t0) / 1000.0 > flow_timeout:
			rec["status"] = "no se corrió"
			rec["ok"] = false
			rec["error"] = "el flujo pasó de %d s" % flow_timeout
			res["steps"].append(rec)
			stop = true
			continue
		if step.has("when") and not _truthy(_eval(str(step["when"]))):
			rec["status"] = "omitido"
			rec["error"] = "no se cumple: %s" % step["when"]
			res["steps"].append(rec)
			continue
		await _run_step(step, rec, dir, seen)
		res["steps"].append(rec)
		_write(dir, res)   # as it goes: a run that is cut still leaves what it did
		if not bool(rec["ok"]):
			if bool(step.get("soft", false)):
				rec["status"] = "falla (sigue)"
			else:
				rec["status"] = "falla"
				stop = true
			res["ok"] = false
	res["orders"] = q.flow_orders.duplicate(true)
	res["keys"] = key_effects.duplicate(true)
	key_effects = []
	for k: String in seen:
		res["visual"].append(seen[k])
	res["seconds"] = snappedf((Time.get_ticks_msec() - _flow_t0) / 1000.0, 0.1)
	Engine.time_scale = 1.0
	_write(dir, res)
	print("[Flow] === %s %s (%.1f s, %d visual findings)" % [id, "OK" if res["ok"] else "FALLA", res["seconds"],
		(res["visual"] as Array).size()])
	return res


func _write(dir: String, res: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join("result.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()


## Where the flow starts: {"scenario": id} (a saved game, playing), {"title": true} (the title screen),
## {"new_game": true} (the new game screen); "seed", "speed", "at": "HH:MM", "paused".
func _start(s: Dictionary) -> String:
	Engine.time_scale = 1.0
	Game.set_speed(1)   # the session's speed survives a new state: every flow starts at ×1
	var seed_value := int(s.get("seed", _seed))
	if bool(s.get("title", false)):
		app.show_title()
	elif bool(s.get("new_game", false)):
		app.show_title()
		app.show_new_game()
	else:
		var sc := str(s.get("scenario", Game.DEFAULT_SCENARIO))
		var r := NewGame.from_scenario(sc, seed_value)
		if not bool(r.get("ok", false)):
			return "escenario %s: %s" % [sc, r.get("error", "")]
		var state: WorldState = r["state"]
		if s.has("at"):
			var hm := str(s["at"]).split(":")
			Game.set_time_of_day(state, hm[0].to_int() * 60 + hm[1].to_int())
		Game.start(state, Game.sim.catalog)
		for screen: Variant in [app.region_screen(), app.city_screen(), app.caravan_screen()]:
			(screen as Control).call("close")
		app.call("_enter_game")
		app.hud().close_panels()
		var toast := drv.node("ToastLabel") as CanvasItem
		if toast != null:
			toast.visible = false   # a toast of the step before must not count for the next one
		var v: Node2D = app.world().view_of(str(app.world().selected_id))
		if v != null:   # a fresh game starts with the camera on its person (the session's camera would stay elsewhere)
			app.world().camera().center_on(v.position)
	await get_tree().create_timer(0.6).timeout
	if bool(s.get("paused", false)):
		Game.set_paused(true)
	return ""


func _action_text(step: Dictionary) -> String:
	if step.has("key_audit"):
		return "tecla %s (%s)" % [step["key_audit"], step.get("context", "")]
	if step.has("context_setup"):
		return "preparar %s" % JSON.stringify(step["context_setup"].get("start", {}))
	for k: String in ["click", "right_click", "double_click", "popup", "spin", "restart", "harness_game", "key", "world", "station", "door", "type", "wheel",
			"pan", "hold"]:
		if step.has(k):
			return "%s %s" % [k, JSON.stringify(step[k])]
	if step.has("until"):
		return "esperar a %s" % step["until"]
	if step.has("wait"):
		return "esperar %s s" % step["wait"]
	return "mirar"


func _run_step(step: Dictionary, rec: Dictionary, dir: String, seen: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var exprs: Array = step.get("expect", [])
	q.snapshot(exprs + ([step["until"]] if step.has("until") else []))
	q.step_orders = []
	q.step_events = []
	drv.history = []
	interruptions = []
	notes = []
	drv.notes = []
	print("[Flow] step %d %s: %s" % [rec["n"], rec["id"], rec["action"]])
	var err := await _act(step.duplicate(true))
	if err == "" and step.has("until"):
		err = await _wait_until(str(step["until"]), float(step.get("timeout", 20.0)), float(step.get("fast", 1.0)))
	if step.has("wait"):
		await get_tree().create_timer(float(step["wait"]), true, false, true).timeout
	await get_tree().create_timer(0.25, true, false, true).timeout   # panels finish their 0.12 s entrance
	for e: Variant in exprs:
		var v: Variant = _eval(str(e))
		var ok := _truthy(v)
		rec["checks"].append({"expr": str(e), "ok": ok, "value": str(v).left(80)})
		if not ok and err == "":
			err = "no se cumple: %s (da %s)" % [e, str(v).left(60)]
	if err != "" and q.refused() != "":
		err += " · rechazos: " + q.refused()
	rec["error"] = err
	rec["ok"] = err == ""
	rec["orders"] = q.step_orders.duplicate(true)
	var evs: Dictionary = {}
	for e: Dictionary in q.step_events:
		evs[str(e.get("type", ""))] = int(evs.get(str(e.get("type", "")), 0)) + 1
	rec["events"] = evs
	rec["input"] = drv.history.duplicate(true)
	rec["interruptions"] = interruptions.duplicate()
	rec["notes"] = notes.duplicate() + drv.notes.duplicate()
	rec["screen"] = _top_screen()
	rec["clock"] = "día %d %02d:%02d" % [q.day(), q.hour(), q.minute() % 60] if Game.sim != null else ""
	var img: Image = null
	if windowed:
		img = get_viewport().get_texture().get_image()
		var name := "%02d_%s" % [rec["n"], rec["id"]]
		img.save_png(dir.path_join(name + ".png"))
		rec["shot"] = name + ".png"
	for f: Dictionary in audit.scan(get_tree().root, img):
		var key := "%s|%s|%s" % [f["kind"], f["node"], f["text"]]
		if seen.has(key):
			seen[key]["count"] = int(seen[key]["count"]) + 1
			continue
		f["count"] = 1
		f["step"] = rec["n"]
		f["shot"] = rec["shot"]
		if img != null:
			var crop := "vis/%02d_%d.png" % [rec["n"], seen.size()]
			VisualAudit.mark(img, f["rect"], dir.path_join(crop))
			f["crop"] = crop
		seen[key] = f
		rec["visual"].append(key)
	rec["seconds"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.01)
	if err != "":
		print("[Flow] step %d %s FALLA: %s" % [rec["n"], rec["id"], err])
	else:
		print("[Flow] step %d ok (%.1f s, %s)" % [rec["n"], rec["seconds"], rec["clock"]])


## The screen on top now: a menu screen, a big modal, the open management panel, the interior or the town.
func _top_screen() -> String:
	var games := app.get_node_or_null("GamesLayer")
	if games != null and games.get_child_count() > 0 and (games.get_child(0) as Control).visible:
		return "game_screen"
	var screens := app.get_node_or_null("ScreensLayer")
	if screens != null:
		var top := ""
		for c: Node in screens.get_children():
			if (c as Control).visible:
				top = VisualAudit.screen_of(c)
		if top != "":
			return top
	for n: String in ["TrialPanel", "OfficesPanel", "FamilyTreePanel", "HelpPanel", "ConfirmModal"]:
		if q.visible(n):
			return VisualAudit.screen_of(drv.node(n))
	var p: Control = app.hud().open_manage_panel()
	if p != null and p.is_visible_in_tree():
		return VisualAudit.screen_of(p)
	if app.interior_building != "":
		return "interior_view"
	return "hud"


func _eval(src: String) -> Variant:
	var e := Expression.new()
	if e.parse(src, ["q"]) != OK:
		return "error: %s" % e.get_error_text()
	var v: Variant = e.execute([q], null, false)
	if e.has_execute_failed():
		return "error: %s" % e.get_error_text()
	return v


static func _truthy(v: Variant) -> bool:
	if v is String:
		return not (v as String).begins_with("error:") and v != ""
	return bool(v) if v != null else false


func _wait_until(src: String, timeout: float, fast: float) -> String:
	var t0 := Time.get_ticks_msec()
	if fast > 1.0:
		Engine.time_scale = fast
		print("[Flow] time_scale x%.0f while waiting for %s" % [fast, src])
	var ok := false
	while (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		if _truthy(_eval(src)):
			ok = true
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	if ok:
		return ""
	var v: Variant = _eval(src)
	return "no llegó en %.0f s: %s (da %s)" % [timeout, src, str(v).left(60)]


# --- actions --------------------------------------------------------------------------------------------------------

## A spec with "=expr" strings: each one is evaluated now (a contract id, the name of a row...).
func _resolve(v: Variant) -> Variant:
	if v is String and (v as String).begins_with("="):
		return _eval((v as String).substr(1))
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _resolve(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _resolve(x))
	return v


## A card that popped up over what the step wanted (a global event, a festival...): a person reads it and closes it
## with its «Entendido» / ok button. Only cards with an ok button are closed this way (a card that asks a decision is
## the step's business). Returns what was closed ("" if nothing).
func _dismiss_over(err: String) -> String:
	var at := err.find("lo tapa ")
	if at < 0:
		return ""
	var h := drv.hovered()
	var n: Node = h
	while n != null and not n is PageCard:
		n = n.get_parent()
	if n == null:
		return ""
	var pick := ""
	for b: String in ["Button_ok", "Button_later", "Button_close"]:   # «Entendido», «Más tarde»: no decision taken
		var ok := (n as Node).find_child(b, true, false) as Button
		if ok != null and ok.is_visible_in_tree() and not ok.disabled:
			pick = b
			break
	if pick == "":
		return ""
	var what := "%s «%s» (%s)" % [n.name, UiDriver.text_of(VisualAudit._first_text(n)).left(40), pick.substr(7)]
	var e := await drv.click({"via": str(n.name), "node": pick})
	return what if e == "" else ""


var interruptions: Array = []
var notes: Array = []   # UX findings of the step that did not stop it (a lost click that a second one fixed)


func _act(raw: Dictionary) -> String:
	var step: Dictionary = _resolve(raw)
	var err := await _act_once(step)
	if err.contains("REHECHO") or err.ends_with("no recibió el clic"):
		notes.append(err.replace("REHECHO: ", "") + " · se pulsó otra vez")
		print("[Flow] lost click, again: %s" % err)
		await get_tree().create_timer(0.2).timeout
		err = await _act_once(step)
	for i: int in 4:   # cards wait in a queue: one closes and the next shows
		if not err.contains("lo tapa ") or bool(step.get("no_dismiss", false)):
			break
		var closed := await _dismiss_over(err)
		if closed == "":
			break
		interruptions.append(closed)
		print("[Flow] interruption closed: %s" % closed)
		await get_tree().create_timer(0.3).timeout
		err = await _act_once(step)
	return err


## What the screen and the session look like now (for the key audit): the shown panels and screens, speed, pause,
## the selection, the interior, the camera and the tutorial.
func signature() -> Dictionary:
	var shown: Array = []
	for c: Control in drv.all_controls():
		if c.is_visible_in_tree() and c.scene_file_path != "" and not c.scene_file_path.ends_with("/app.tscn") \
				and c.get_global_rect().get_area() > 400.0:
			var n := c.scene_file_path.get_file().get_basename()
			if not n in ["item_slot", "portrait_frame", "manage_slot", "family_tree_node", "hud", "page_card", "family_card"] \
					and not shown.has(n):
				shown.append(n)
	shown.sort()
	var cam := Vector2.ZERO
	if app.interior_building == "":
		cam = (app.world().camera() as Node2D).position
	else:
		cam = app.interior().camera().position
	return {"shown": shown, "speed": Game.speed, "paused": Game.paused, "selected": q.selected(),
		"interior": app.interior_building, "camera": cam.round(),
		"town_camera": (app.world().camera() as Node2D).position.round(), "zoom": app.world().camera().current_zoom(),
		"tutorial": q.tutorial_step(), "fullscreen": Settings.value("display/fullscreen"),
		"toast": q.text("ToastText") if q.visible("ToastLabel") else ""}


## The difference between two signatures as short phrases ([] = nothing changed).
static func sig_diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for n: String in b["shown"]:
		if not (a["shown"] as Array).has(n):
			out.append("abre " + n)
	for n: String in a["shown"]:
		if not (b["shown"] as Array).has(n):
			out.append("cierra " + n)
	if str(b.get("toast", "")) != "" and str(a.get("toast", "")) != str(b.get("toast", "")):
		out.append("avisa «%s»" % str(b["toast"]).left(50))
	for k: String in ["speed", "paused", "selected", "interior", "zoom", "tutorial", "fullscreen"]:
		if str(a[k]) != str(b[k]):
			out.append("%s %s→%s" % [k, a[k], b[k]])
	if (a["camera"] as Vector2).distance_to(b["camera"]) > 4.0:
		out.append("mueve la cámara")
	elif str(a["interior"]) != "" and (a["town_camera"] as Vector2).distance_to(b["town_camera"]) > 4.0:
		out.append("mueve la cámara de la ciudad (detrás del interior)")
	return out


var key_effects: Array = []   # [{context, key, effects, ok}] of the key audit (coverage)


## The key audit: presses `key` (a name or @action) in the flow's start context, reads what changed and puts the
## context back (the flow's start again). A key that does nothing, or does two unrelated things, is noted.
func _key_audit(step: Dictionary) -> String:
	var key := str(step["key_audit"])
	var context := str(step.get("context", "ciudad"))
	await get_tree().create_timer(0.2).timeout
	if _restore_check != "" and not _truthy(_eval(_restore_check)):
		var e0 := await _setup_context()
		if e0 != "":
			return "no se pudo preparar el contexto %s: %s" % [context, e0]
	var before := signature()
	var err := await drv.key(key, bool(step.get("shift", false)), int(step.get("frames", 1)))
	if err != "":
		return err
	await get_tree().create_timer(float(step.get("settle", 0.4))).timeout
	var effects := sig_diff(before, signature())
	var camera_key := bool(step.get("camera", false))
	var other: Array = effects.filter(func(e: String) -> bool:
		return not e.begins_with("mueve la cámara") and not e.begins_with("paused") and not e.begins_with("avisa"))
	var opened: Array = effects.filter(func(e: String) -> bool: return e.begins_with("abre"))
	var moved := effects.any(func(e: String) -> bool: return e.begins_with("mueve la cámara"))
	# a camera key that also does something else, or another key that opens two things or opens and changes more
	# (opening a panel may move the camera so the person is not under it: docs/ui/01 §4.6, by design)
	var clash := (camera_key and not other.is_empty()) or (not camera_key and (opened.size() > 1 or \
		(opened.size() == 1 and other.size() > 1)) or (not camera_key and moved and opened.is_empty() and not other.is_empty()))
	var rec := {"context": context, "key": key, "effects": effects, "expected": str(step.get("does", "")),
		"clash": clash and not bool(step.get("both", false))}
	key_effects.append(rec)
	print("[Flow] key %s in %s: %s" % [key, context, effects])
	if bool(step.get("restore", true)) and not effects.is_empty():
		var e := await _setup_context()
		if e != "":
			print("[Flow] the context could not be set up again: %s" % e)
	if effects.is_empty() and not bool(step.get("may_do_nothing", false)):
		return "la tecla %s no hace nada en %s" % [key, context]
	if rec["clash"]:
		return "la tecla %s hace dos cosas a la vez en %s: %s" % [key, context, ", ".join(effects)]
	return ""


var _restore_to: Dictionary = {}
var _restore_steps: Array = []
var _restore_check: String = ""


## The key audit's context again: the start, its steps (closing the cards that pop up) and its check.
func _setup_context() -> String:
	var e := await _start(_restore_to)
	for s: Dictionary in _restore_steps:
		e = await _act(s)
		await get_tree().create_timer(0.3).timeout
		if e != "":
			return e
	if _restore_check != "" and not _truthy(_eval(_restore_check)):
		return "no se cumple %s" % _restore_check
	return e


func _act_once(step: Dictionary) -> String:
	if step.has("context_setup"):   # where the key audit puts things back: a start + the steps that set it up
		_restore_to = step["context_setup"].get("start", {})
		_restore_steps = step["context_setup"].get("steps", [])
		_restore_check = str(step["context_setup"].get("check", ""))
		return await _setup_context()
	if step.has("key_audit"):
		return await _key_audit(step)
	if step.has("restart"):
		return await _start(step["restart"])
	if step.has("harness_game"):   # no way in through the interface yet: the harness opens the game (noted as a gap)
		notes.append("abierto por el arnés (App.open_games_test): no hay entrada a «%s» por la interfaz" % step["harness_game"])
		app.call("open_games_test", str(step["harness_game"]))
		await get_tree().create_timer(0.4).timeout
		return ""
	if step.has("click") and keys_mode and not bool(step.get("mouse_only", false)):
		return await drv.key_click(step["click"])
	if step.has("click"):
		return await drv.click(step["click"], "left", false)
	if step.has("right_click"):
		return await drv.click(step["right_click"], "right", false)
	if step.has("double_click"):
		return await drv.click(step["double_click"], "left", true)
	if step.has("spin"):
		if keys_mode:
			return await drv.key_spin(step["spin"], int(step.get("times", 1)), bool(step.get("up", true)))
		return await drv.spin(step["spin"], int(step.get("times", 1)), bool(step.get("up", true)))
	if step.has("popup"):
		if keys_mode:
			return await drv.key_popup_item(step["popup"], int(step.get("item", 0)))
		return await drv.click_popup_item(step["popup"], int(step.get("item", 0)))

	if step.has("key"):
		return await drv.key(str(step["key"]), bool(step.get("shift", false)))
	if step.has("hold"):
		return await drv.key(str(step["hold"]), bool(step.get("shift", false)), int(step.get("frames", 20)))
	if step.has("type"):
		await drv.type_text(str(step["type"]))
		return ""
	if step.has("world"):
		return await _click_world(step["world"], str(step.get("button", "left")), bool(step.get("double", false)),
			bool(step.get("shift", false)))
	if step.has("station"):
		return await _click_station(str(step["station"]), str(step.get("button", "left")))
	if step.has("door"):
		return await _click_door()
	if step.has("wheel"):
		var w: Dictionary = step["wheel"]
		await drv.wheel_at(Vector2(480, 300), bool(w.get("up", true)), int(w.get("times", 1)))
		return ""
	if step.has("pan"):
		var p: Array = step["pan"]
		await drv.drag(Vector2(480, 300), Vector2(480, 300) + Vector2(float(p[0]), float(p[1])), "middle")
		return ""
	if step.has("release_focus"):
		var f := get_viewport().gui_get_focus_owner()
		if f != null:
			f.release_focus()
		return ""
	return ""


## The free part of the screen for the town (between the HUD's zones): where a click reaches the world.
func _free_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var z := HudLayout.zones(vp)
	var r := Rect2(Vector2((z["column"] as Rect2).end.x + 4.0, (z["status"] as Rect2).end.y + 8.0), Vector2.ZERO)
	r = r.expand(Vector2(vp.x - 8.0, (z["selection"] as Rect2).position.y - 8.0))
	var open: Control = app.hud().open_manage_panel()
	if open != null and open.is_visible_in_tree():
		r.end.x = minf(r.end.x, open.get_global_rect().position.x - 4.0)
	for c: Variant in PageCard.stack():   # the side stack of cards covers its strip of the town
		r.end.x = minf(r.end.x, (c as Control).get_global_rect().position.x - 4.0)
	return r


## Brings `world_pos` into the free part of the screen with middle drags of the camera (as a person would).
func _bring_into_view(world_pos: Vector2) -> void:
	var cam: WorldCamera = app.world().camera()
	for i: int in 6:
		var at := cam.world_to_screen(world_pos)
		var free := _free_rect()
		if free.grow(-48).has_point(at):
			return
		var want := free.get_center()
		var d := (at - want).limit_length(220.0)
		await drv.drag(Vector2(480, 280), Vector2(480, 280) - d, "middle")
		await get_tree().process_frame


## A click on the town: a tile, a building (by id, or "own": type of the player's), a person ("who", "spouse" or an
## id; "npc": an id or an occupation), a service (stall / board id or kind). The point is checked with the view's own
## pickers before the click (what is under the pointer), the effect is checked by the step.
func _click_world(t: Dictionary, button: String, double: bool, shift: bool) -> String:
	if app.interior_building != "":
		return "estoy dentro de %s, no en la ciudad" % app.interior_building
	var w: WorldView = app.world()
	var st := Game.sim.state
	var world_pos := Vector2.INF
	var check := Callable()
	if t.has("tile"):
		var tl := Vector2i(int(t["tile"][0]), int(t["tile"][1]))
		world_pos = Iso.tile_to_world(tl)
		check = func(p: Vector2) -> bool: return w.screen_to_tile(p) == tl
	elif t.has("building") or t.has("own"):
		var b := str(t.get("building", ""))
		if t.has("own"):
			b = q.own(str(t["own"]))
		elif not st.buildings.has(b):
			b = q.building(b)
		if b == "" or not st.buildings.has(b):
			return "no hay edificio %s" % JSON.stringify(t)
		var o: Array = st.buildings[b].get("origin", [0, 0])
		var f: Array = st.buildings[b].get("footprint", [1, 1])
		world_pos = Iso.tile_to_world(Vector2i(int(o[0]) + int(f[0]) / 2, int(o[1]) + int(f[1]) / 2)) + Vector2(0, -20)
		var bid := b
		check = func(p: Vector2) -> bool: return w.pick_building(p) == bid if button == "left" \
			else w.command_target_building(p, shift) == bid
	elif t.has("person") or t.has("npc"):
		var who := str(t.get("person", t.get("npc", "")))
		if who == "who":
			who = q.who()
		elif who == "spouse":
			who = q.spouse()
		elif not st.characters.has(who):
			who = _npc_by(who)
		if w.view_of(who) == null:
			return "no veo a %s en la ciudad" % who
		world_pos = w.view_of(who).position + Vector2(0, -12)
		var cid := who
		check = func(p: Vector2) -> bool: return w.pick_character(p) == cid or w.pick_any_character(p) == cid
	elif t.has("service"):
		var sid := str(t["service"])
		var svc := {}
		for s: Dictionary in SimQuery.map_services(st, Game.sim.catalog):
			if str(s["id"]) == sid or str(s.get("kind", "")) == sid:
				svc = s
				break
		if svc.is_empty():
			return "no hay servicio %s en el mapa" % sid
		world_pos = (w.camera().screen_to_world(w.service_screen(str(svc["id"]))))
		var sv := str(svc["id"])
		check = func(p: Vector2) -> bool: return str(w.pick_service(p).get("id", "")) == sv
	else:
		return "objetivo del mapa sin tipo: %s" % JSON.stringify(t)
	await _bring_into_view(world_pos)
	var cam: WorldCamera = w.camera()
	var at := Vector2.INF
	var people := not (t.has("person") or t.has("npc"))
	var base := cam.world_to_screen(world_pos)
	for attempt: int in 2:
		base = cam.world_to_screen(world_pos)
		var free := _free_rect()
		for off: Vector2 in _offsets():
			var p := base + off
			if free.has_point(p) and check.call(p) and (not people or (w.pick_character(p) == "" and w.pick_any_character(p) == "")):
				at = p
				break
		if at != Vector2.INF or attempt == 1:
			break
		# nothing clickable in the free part: drag the target to the middle of it, as a person would
		await drv.drag(Vector2(480, 280), Vector2(480, 280) - (base - free.get_center()).limit_length(260.0), "middle")
	if at == Vector2.INF:
		var om: Control = app.hud().open_manage_panel()
		print("[Flow] world miss: target=%s base=%s cam=%s free=%s open=%s (in tree visible=%s)" % [t, base, cam.position,
			_free_rect(), UiDriver.path_of(om), om.is_visible_in_tree() if om != null else false])
		return "no encuentro dónde pulsar %s (cerca de %s)" % [JSON.stringify(t), base.round()]
	if not _free_rect().has_point(at):
		return "%s queda debajo del HUD (%s)" % [JSON.stringify(t), at.round()]
	await drv.move_to(at)
	for i: int in 4:   # somebody walking moved while the pointer travelled: aim again at where they are now
		if check.call(at):
			break
		var now := cam.world_to_screen(w.view_of(_who_of(t)).position + Vector2(0, -12)) \
			if (t.has("person") or t.has("npc")) and w.view_of(_who_of(t)) != null else base
		for off: Vector2 in _offsets():
			if check.call(now + off):
				at = now + off
				break
		await drv.move_to(at, 1)
	var h := drv.hovered()
	if h != null:   # STOP or PASS: the GUI takes the click, the town does not get it
		return "en %s lo tapa %s" % [at.round(), UiDriver.path_of(h)]
	await drv.click_at(at, button, double, shift)
	return ""


## Points around a target, nearest first (rings of 4 px up to 64 px, 16 points each).
static func _offsets() -> Array:
	var out: Array = [Vector2.ZERO]
	for r: int in range(4, 68, 4):
		for k: int in 16:
			out.append((Vector2.RIGHT.rotated(TAU * k / 16.0) * r).round())
	return out


## The character id a world target names ("who", "spouse", an id or an occupation).
func _who_of(t: Dictionary) -> String:
	var who := str(t.get("person", t.get("npc", "")))
	if who == "who":
		return q.who()
	if who == "spouse":
		return q.spouse()
	return who if Game.sim.state.characters.has(who) else _npc_by(who)


func _npc_by(occupation: String) -> String:
	var w: WorldView = app.world()
	var ids: Array = Game.sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = Game.sim.state.characters[id]
		if (str(c.get("occupation", "")) == occupation or str(c.get("profession", "")) == occupation) and w.view_of(id) != null:
			return id
	return ""


func _click_station(zone: String, button: String) -> String:
	if app.interior_building == "":
		return "no estoy dentro de ningún edificio"
	var iv: InteriorView = app.interior()
	if zone == "*":
		var zones: Array = (iv.get("_stations") as Dictionary).keys()
		zones.sort()
		if zones.is_empty():
			return "la sala no tiene puestos"
		zone = str(zones[0])
	if iv.station_view(zone) == null:
		return "la sala no tiene el puesto %s" % zone
	var base: Vector2 = iv.station_screen(zone)
	var at := Vector2.INF
	for off: Vector2 in _offsets():
		if iv.pick_station(base + off) == zone and iv.pick_character(base + off) == "":   # a person in front takes it
			at = base + off
			break
	if at == Vector2.INF:
		return "no encuentro el puesto %s en la sala (cerca de %s)" % [zone, base.round()]
	await drv.move_to(at)
	var h := drv.hovered()
	if h != null:   # STOP or PASS: either way the GUI takes the click and the room never sees it
		return "el puesto %s lo tapa %s" % [zone, UiDriver.path_of(h)]
	await drv.click_at(at, button)
	return ""


func _click_door() -> String:
	if app.interior_building == "":
		return "no estoy dentro de ningún edificio"
	var iv: InteriorView = app.interior()
	var at: Vector2 = iv.door_screen()
	if not iv.is_door(at):
		return "la puerta no está en %s" % at.round()
	await drv.move_to(at)
	var h := drv.hovered()
	if h != null:
		return "la puerta: lo tapa %s" % UiDriver.path_of(h)
	await drv.click_at(at, "left")
	return ""
