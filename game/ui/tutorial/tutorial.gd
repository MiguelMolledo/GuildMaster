class_name Tutorial
extends CanvasLayer
## The interactive tutorial (docs/ui/05_tutorial.md): guided chapters and first-time hints, all from data
## (data/tutorial.json and data/tutorial/<chapter>.json). It listens (the sim's events through the context, the UI's
## through ctx.poll(), conditions every frame) and paints (TutorialOverlay); it never gives an order nor changes a rule.
## The only thing it touches of the session is the pause, on a step with "pause": true.
## A chapter runs its steps in order: a step waits for its "when" (phase "wait"), shows (phase "show") and moves on
## with its action ("done", advance "action") or with Next (advance "next"); a step whose "if" fails is skipped. At the
## end, the chapter is marked done (Settings tutorial/done) and a card offers the next one (phase "finished").
## Keys while something is shown: Tab skip the step (Next, Got it), Shift+Tab skip the chapter, Backspace repeat.
## The progress lives in the player's settings, not in the saved game.

signal step_shown(chapter: String, index: int, step_id: String)
signal chapter_finished(chapter: String)
signal hint_shown(hint_id: String)

const DATA_PATH: String = "res://data/tutorial.json"
const DIR: String = "res://data/tutorial/"
const KEYS: Dictionary = {"tutorial_skip": [KEY_TAB, false], "tutorial_chapter": [KEY_TAB, true],
	"tutorial_repeat": [KEY_BACKSPACE, false]}

var ctx: TutorialContext = null
var config: Dictionary = {}
var chapters: Dictionary = {}     # id -> chapter (data/tutorial/<id>.json)
var chapter_id: String = ""
var steps: Array = []
var index: int = -1
var phase: String = ""            # "" | "wait" | "show" | "finished"
var hint: Dictionary = {}         # the hint on screen ({} = none)
var focus: Dictionary = {}        # what the last frame resolved (TutorialTargets.resolve)
var use_settings: bool = true     # false: the progress stays in memory (tests)
var memory: Dictionary = {}       # the progress when use_settings is false
var hold: bool = false            # the steps do not move on by themselves (the smoke of the data walks them)
var _when_count: int = 0
var _counts: Array = []
var _hint_event: Dictionary = {}
var _hint_queue: Array = []       # [{hint, event}]
var _cam_start: Vector2 = Vector2.ZERO
var _focus_key: String = ""       # what the focus fell on last frame (a new world target moves the camera to it)

@onready var overlay: TutorialOverlay = %Overlay


func _ready() -> void:
	_bind()
	load_data()
	_ensure_keys()
	overlay.card.button_pressed.connect(_on_button)
	overlay.hide_all()


func _bind() -> void:
	if overlay == null:
		overlay = get_node("%Overlay") as TutorialOverlay
	overlay._bind()


## Reads data/tutorial.json and every chapter of its list.
func load_data() -> void:
	config = _read(DATA_PATH)
	chapters.clear()
	for id: Variant in config.get("chapters", []):
		var ch := _read(DIR + str(id) + ".json")
		if not ch.is_empty():
			chapters[str(id)] = ch
	_bind()
	overlay.look = config.get("look", {})
	_log("data: %d chapters, %d hints" % [chapters.size(), (config.get("hints", []) as Array).size()])


static func _read(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("tutorial: cannot read %s" % path)
		return {}
	return json.data


## The chapters in their order.
func chapter_ids() -> Array:
	return (config.get("chapters", []) as Array).filter(func(c: Variant) -> bool: return chapters.has(str(c)))


## Whether chapter `id` can be played now ("" = yes, else the i18n key of why not).
func cannot_play(id: String) -> String:
	var ch: Dictionary = chapters.get(id, {})
	if ch.is_empty():
		return "tutorial.ui.close"
	if ch.has("requires") and ctx != null and not ctx.condition(ch["requires"] as Dictionary):
		return "tutorial.ui.help_other_trade"
	return ""


func setup(c: TutorialContext) -> void:
	ctx = c


func running() -> bool:
	return phase != ""


func step() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}


# --- progress (the player's settings) -------------------------------------------------------------------------------

func progress(key: String) -> Variant:
	if not use_settings:
		return memory.get(key, Settings.DEFAULTS.get(key))
	return Settings.value(key)


func set_progress(key: String, v: Variant) -> void:
	if not use_settings:
		memory[key] = v
		return
	Settings.set_value(key, v)


func done_chapters() -> Array:
	var v: Variant = progress("tutorial/done")
	return (v as Array).duplicate() if v is Array else []


func seen_hints() -> Array:
	var v: Variant = progress("tutorial/seen")
	return (v as Array).duplicate() if v is Array else []


func hints_on() -> bool:
	return bool(progress("game/tutorial_hints"))


# --- chapters ---------------------------------------------------------------------------------------------------------

## Starts chapter `id` from its first step (another one in course stops; a hint on screen goes).
func start(id: String) -> bool:
	if not chapters.has(id):
		push_warning("tutorial: unknown chapter %s" % id)
		return false
	_close_hint(false)
	chapter_id = id
	steps = (chapters[id].get("steps", []) as Array).duplicate(true)
	index = -1
	phase = "wait"
	_log("chapter %s starts (%d steps)" % [id, steps.size()])
	on_event("ui", "chapter_started", {"chapter": id})
	_advance()
	return true


func stop() -> void:
	if phase != "":
		_log("chapter %s stops (step %d)" % [chapter_id, index + 1])
	phase = ""
	chapter_id = ""
	steps = []
	index = -1
	focus = {}
	_bind()
	overlay.hide_all()


## Tab: the step is skipped (its Next, if it only explains).
func skip_step() -> void:
	if phase in ["wait", "show"]:
		_log("skip step %s" % str(step().get("id", "")))
		_advance()
	elif phase == "finished":
		stop()


func skip_chapter() -> void:
	if phase != "":
		_log("skip chapter %s" % chapter_id)
		stop()


## Backspace: the step again (the card, the camera, the beat).
func repeat() -> void:
	if phase == "show":
		_show()


## «Siguiente» of a step that only explains.
func next() -> void:
	if phase == "show" and str(step().get("advance", "")) == "next":
		_advance()


## Jumps to step `i` of the chapter on, shown at once whatever its "when" (the smoke of the data).
func show_step(i: int) -> void:
	if i < 0 or i >= steps.size():
		return
	index = i
	_reset_counts()
	_show()


func _advance() -> void:
	index += 1
	while index < steps.size() and steps[index].has("if") and ctx != null \
			and not ctx.condition(steps[index]["if"] as Dictionary):
		_log("step %s skipped (if)" % str(steps[index].get("id", "")))
		index += 1
	if index >= steps.size():
		_finish()
		return
	_reset_counts()
	if step().has("when"):
		phase = "wait"
		focus = {}
		overlay.hide_all()
		_log("step %d/%d %s waits for %s" % [index + 1, steps.size(), step().get("id", ""), step()["when"]])
	else:
		_show()


func _reset_counts() -> void:
	_when_count = 0
	_counts = []
	for t: Variant in TutorialRules.as_list(step().get("done")):
		_counts.append(0)


func _show() -> void:
	phase = "show"
	var st := step()
	if ctx != null:
		_cam_start = ctx.camera_screen()
		if bool(st.get("pause", false)):
			ctx.set_paused(true)
		if st.has("target"):
			ctx.focus_camera(st["target"] as Dictionary)
	_log("step %d/%d %s shows (target=%s, advance=%s)" % [index + 1, steps.size(), st.get("id", ""),
		st.get("target", {}), st.get("advance", "")])
	step_shown.emit(chapter_id, index, str(st.get("id", "")))


func _finish() -> void:
	var done := done_chapters()
	if not chapter_id in done:
		done.append(chapter_id)
		set_progress("tutorial/done", done)
	phase = "finished"
	focus = {}
	_log("chapter %s finished" % chapter_id)
	chapter_finished.emit(chapter_id)


## The chapter after `id` in the order that can be played now ("" = none).
func next_chapter(id: String) -> String:
	var ids := chapter_ids()
	var i := ids.find(id)
	for j: int in range(i + 1, ids.size()):
		if cannot_play(str(ids[j])) == "":
			return str(ids[j])
	return ""


# --- events -----------------------------------------------------------------------------------------------------------

## An event of the sim ("sim") or of the UI ("ui").
func on_event(source: String, type: String, data: Dictionary) -> void:
	var resolve := func(v: Variant) -> Variant: return ctx.symbol(v, data) if ctx != null else v
	if hold:
		pass
	elif phase == "wait" and step().has("when"):
		var w: Dictionary = step()["when"]
		if _event_is(w, source, type, data, resolve):
			_when_count += 1
			if _when_count >= int(w.get("count", 1)):
				_show()
				return
	elif phase == "show" and str(step().get("advance", "")) == "action":
		var list := TutorialRules.as_list(step().get("done"))
		for i: int in list.size():
			var t: Dictionary = list[i]
			if _event_is(t, source, type, data, resolve):
				_counts[i] = int(_counts[i]) + 1
				if int(_counts[i]) >= int(t.get("count", 1)):
					_log("step %s done (%s %s)" % [step().get("id", ""), source, type])
					_advance()
					return
	_hint_events(source, type, data, resolve)


func _event_is(t: Dictionary, source: String, type: String, data: Dictionary, resolve: Callable) -> bool:
	if not TutorialRules.event_matches(t, source, type, data, resolve):
		return false
	return source != "sim" or bool(t.get("anyone", false)) or ctx == null or ctx.mine(data)


## The conditions of the state, every frame.
func _check_states() -> void:
	if ctx == null:
		return
	if hold:
		pass
	elif phase == "wait" and TutorialRules.kind(step().get("when")) == "state":
		if ctx.condition(step()["when"] as Dictionary):
			_show()
	elif phase == "show" and str(step().get("advance", "")) == "action":
		for t: Variant in TutorialRules.as_list(step().get("done")):
			if TutorialRules.kind(t) == "state" and _state_done(t as Dictionary):
				_log("step %s done (state %s)" % [step().get("id", ""), (t as Dictionary)["state"]])
				_advance()
				return
	_hint_states()


func _state_done(t: Dictionary) -> bool:
	if str(t["state"]) == "camera_moved":
		return ctx.camera_screen().distance_to(_cam_start) >= float(t.get("px", 32))
	return ctx.condition(t)


# --- hints ------------------------------------------------------------------------------------------------------------

func _hint_events(source: String, type: String, data: Dictionary, resolve: Callable) -> void:
	if not hint.is_empty() and hint.has("until") and _event_is(hint["until"] as Dictionary, source, type, data, resolve):
		_close_hint(true)   # the player did what it asked: seen
	for q: Dictionary in _hint_queue.duplicate():
		var h: Dictionary = q["hint"]
		if h.has("until") and _event_is(h["until"] as Dictionary, source, type, data, resolve):
			_hint_queue.erase(q)
	for h: Dictionary in config.get("hints", []):
		if TutorialRules.kind(h.get("when")) == source and _event_is(h["when"] as Dictionary, source, type, data, resolve):
			_offer_hint(h, data)


func _hint_states() -> void:
	if not hints_on():
		return
	if not hint.is_empty() and TutorialRules.kind(hint.get("until")) == "state" and ctx.condition(hint["until"] as Dictionary):
		_close_hint(true)
	# a hint about something on screen (a panel open) goes when it is no longer there; it will come back next time
	if not hint.is_empty() and TutorialRules.kind(hint.get("when")) == "state" and not ctx.condition(hint["when"] as Dictionary):
		_close_hint(false)
	for h: Dictionary in config.get("hints", []):
		if TutorialRules.kind(h.get("when")) == "state" and not str(h["id"]) in seen_hints() \
				and str(hint.get("id", "")) != str(h["id"]) and ctx.condition(h["when"] as Dictionary):
			_offer_hint(h, {})


## A hint fires: shown now if nothing else is, kept for later if another hint is on screen; dropped while a chapter
## runs (it will fire again the next time) or if hints are off or it was seen.
func _offer_hint(h: Dictionary, ev: Dictionary) -> void:
	var id := str(h.get("id", ""))
	if not hints_on() or id in seen_hints() or phase != "" or str(hint.get("id", "")) == id:
		return
	for q: Dictionary in _hint_queue:
		if str((q["hint"] as Dictionary)["id"]) == id:
			return
	if not hint.is_empty():
		if _hint_queue.size() < 3:
			_hint_queue.append({"hint": h, "event": ev})
		return
	hint = h
	_hint_event = ev.duplicate()
	if ctx != null and h.has("target"):
		ctx.focus_camera(h["target"] as Dictionary, _hint_event)
	_log("hint %s" % id)
	hint_shown.emit(id)


## Closes the hint on screen; `seen`: it is marked as seen (Got it).
func _close_hint(seen: bool) -> void:
	if hint.is_empty():
		return
	if seen:
		var s := seen_hints()
		if not str(hint["id"]) in s:
			s.append(str(hint["id"]))
			set_progress("tutorial/seen", s)
	_log("hint %s closes (seen=%s)" % [hint.get("id", ""), seen])
	hint = {}
	_hint_event = {}
	while not _hint_queue.is_empty():
		var q: Dictionary = _hint_queue.pop_front()
		_offer_hint(q["hint"], q["event"])
		if not hint.is_empty():
			break


## «No volver a mostrar»: every hint off (Options turns them on again).
func hints_off() -> void:
	_close_hint(true)
	_hint_queue.clear()
	set_progress("game/tutorial_hints", false)
	_log("hints off")


# --- each frame -------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(_delta: float) -> void:
	if ctx == null:
		return
	if ctx.blocked():
		overlay.hide_all()
		return
	for ev: Array in ctx.poll():
		on_event("ui", str(ev[0]), ev[1] as Dictionary)
	_check_states()
	paint()


## Puts on screen what there is now: the step, the end of the chapter's card or the hint.
func paint() -> void:
	_bind()
	var openers: Dictionary = config.get("openers", {})
	var args := ctx.text_args() if ctx != null else {}
	var guided := bool(progress("game/tutorial_guided"))
	var passing: Array = ctx.passthrough() if ctx != null else []
	if phase == "show":
		var st := step()
		var t: Dictionary = st.get("target", {})
		focus = TutorialTargets.resolve(t, ctx, openers) if not t.is_empty() and ctx != null else {}
		_follow_camera()
		var found := bool(focus.get("found", false))
		var rect: Rect2 = focus.get("rect", Rect2()) if found else Rect2()
		overlay.show_focus(rect, found, guided, passing, _step_card(st, args))
	elif phase == "finished":
		focus = {}
		overlay.show_focus(Rect2(), false, false, [], _end_card(args))
	elif not hint.is_empty():
		var t: Dictionary = hint.get("target", {})
		focus = TutorialTargets.resolve(t, ctx, {}, _hint_event) if not t.is_empty() and ctx != null else {}
		_follow_camera()
		var rect: Rect2 = focus.get("rect", Rect2()) if bool(focus.get("found", false)) else Rect2()
		overlay.show_focus(rect, false, false, [], _hint_card(hint, args))
	else:
		focus = {}
		overlay.hide_all()


## When the focus moves to another world target (the step's own after its opener, the street after leaving a
## building), the camera goes to it once; it never chases it frame by frame.
func _follow_camera() -> void:
	var key := "%s|%s|%s" % [phase, focus.get("found", false), focus.get("target", {})]
	if key == _focus_key:
		return
	_focus_key = key
	if bool(focus.get("found", false)) and bool(focus.get("world", false)) and ctx != null:
		ctx.focus_camera(focus.get("target", {}) as Dictionary, _hint_event)


func _t(key: String, args: Dictionary = {}) -> String:
	return TutorialRules.fill(tr(key), args)


func _step_card(st: Dictionary, args: Dictionary) -> Dictionary:
	var ch: Dictionary = chapters.get(chapter_id, {})
	var a := args.duplicate()
	a.merge({"chapter": tr(str(ch.get("name_key", ""))), "n": index + 1, "total": steps.size()}, true)
	# the chapter on the ribbon (its short name if it has one: one line in the notice), the step count in the card
	var d := {"step": ribbon_name(chapter_id), "count": _t("tutorial.ui.step", a), "body": _t(str(st.get("text", "")),
		args), "foot": _t("tutorial.ui.keys")}
	if bool(focus.get("opener", false)) and str(focus.get("text", "")) != "":
		d["lead"] = _t(str(focus["text"]), args)
	if str(st.get("advance", "")) == "next":
		d["buttons"] = [{"id": "next", "text": tr("tutorial.ui.next"), "primary": true},
			{"id": "skip_chapter", "text": tr("tutorial.ui.skip_chapter")}]
	else:
		d["foot"] = tr("tutorial.ui.waiting") + " · " + _t("tutorial.ui.keys")
		d["buttons"] = [{"id": "skip", "text": tr("tutorial.ui.skip_step")},
			{"id": "skip_chapter", "text": tr("tutorial.ui.skip_chapter")}]
	return d


## The chapter's name for the ribbon: `<name_key>.short` when i18n has it (a long name would not fit one line of the
## notice's ribbon), else the name.
func ribbon_name(id: String) -> String:
	var key := str(chapters.get(id, {}).get("name_key", ""))
	var short := tr(key + ".short")
	return short if short != key + ".short" else tr(key)


func _end_card(args: Dictionary) -> Dictionary:
	var ch: Dictionary = chapters.get(chapter_id, {})
	var nxt := next_chapter(chapter_id)
	var a := args.duplicate()
	a["chapter"] = tr(str(ch.get("name_key", "")))
	a["next"] = tr(str(chapters.get(nxt, {}).get("name_key", ""))) if nxt != "" else ""
	var d := {"step": ribbon_name(chapter_id),   # the chapter's name on the ribbon (the short one if it has it)
		"body": tr("tutorial.ui.chapter_done") + " " + (_t("tutorial.ui.chapter_done_body", a) if nxt != ""
			else tr("tutorial.ui.all_done"))}
	var buttons: Array = []
	if nxt != "":
		buttons.append({"id": "next_chapter", "text": tr("tutorial.ui.next_chapter"), "primary": true})
	buttons.append({"id": "close", "text": tr("tutorial.ui.close"), "primary": nxt == ""})
	d["buttons"] = buttons
	return d


func _hint_card(h: Dictionary, args: Dictionary) -> Dictionary:
	return {"step": tr("tutorial.ui.hint"), "body": _t(str(h.get("text", "")), args),
		"buttons": [{"id": "got_it", "text": tr("tutorial.ui.got_it"), "primary": true},
			{"id": "never", "text": tr("tutorial.ui.never")}]}


func _on_button(id: String) -> void:
	_log("button %s" % id)
	match id:
		"next":
			next()
		"skip":
			skip_step()
		"skip_chapter":
			skip_chapter()
		"next_chapter":
			var nxt := next_chapter(chapter_id)
			stop()
			if nxt != "":
				start(nxt)
		"close":
			stop()
		"got_it":
			_close_hint(true)
		"never":
			hints_off()


# --- keys -------------------------------------------------------------------------------------------------------------

static func _ensure_keys() -> void:
	for a: String in KEYS:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.2)
		var e := InputEventKey.new()
		e.physical_keycode = (KEYS[a] as Array)[0] as Key
		e.shift_pressed = bool((KEYS[a] as Array)[1])
		InputMap.action_add_event(a, e)


## Tab / Shift+Tab / Backspace while a step, the end card or a hint is shown (not while typing, not over a menu).
func _input(event: InputEvent) -> void:
	if ctx == null or ctx.blocked() or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if phase == "" and hint.is_empty():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if HudKeys.pressed(event, "tutorial_chapter"):
		if phase == "":
			return
		skip_chapter()
	elif HudKeys.pressed(event, "tutorial_skip"):
		if phase != "":
			skip_step()
		else:
			_close_hint(true)
	elif HudKeys.pressed(event, "tutorial_repeat"):
		repeat()
	else:
		return
	get_viewport().set_input_as_handled()


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[Tutorial] %s" % msg)
