class_name TrialPanel
extends PanelContainer
## The trial (GDD 4.12.5, H11; docs/ui/mecanicas/tribunal.md of diseno-ui): accused against accuser, the charge and its
## severity with the sentence it may bring, the time left; the scale with its parts (the accuser's proofs «?» until
## the hearing); the 3-5 witnesses with their disposition and, in the preparation, Convince / Bribe / Threaten for the
## selected person (far away: walks first, the action queued). In the hearing, the same panel: Question the witnesses
## against, Rest the defense, and the judge (if it is the selected person and not a party) can rule. Opens with the
## HUD's Trials button (key J), a trial notice or when the hearing starts (the HUD pauses then). Reads the state and gives
## orders (order_sink). docs/ui/mecanicas/tribunal.md: the portraits of accused and accuser (and the judge in the
## hearing), the hint «dicen tener pruebas» while they are hidden (decision b), the witnesses with their portrait and,
## written, why an action is off; bribing and threatening a witness ask first with their risk (the extra charge of
## data/justice.json), a verdict against the scale too; in the hearing «Lo que va pasando»: the parts of the scale
## as steps (the accusation's plea and proofs, each witness and its questioning, the defense), no rule of its own.

signal closed

const DISP_COLORS: Dictionary = {"favor": Color(0.55, 0.85, 0.5), "neutral": Color(0.8, 0.8, 0.75),
	"against": Color(1, 0.5, 0.45)}

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var trial_id: String = ""
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%RestButton as Button).pressed.connect(func() -> void: _give({"type": "trial_rest", "actor": actor,
		"trial": trial_id}))
	(%GuiltyButton as Button).pressed.connect(func() -> void: request_verdict("guilty"))
	(%InnocentButton as Button).pressed.connect(func() -> void: request_verdict("innocent"))


## Opens the trial `tid` for the selected person `who`.
func open_for(s: Sim, who: String, tid: String) -> void:
	_bind()
	sim = s
	actor = who
	trial_id = tid
	(%RestButton as Button).text = SimQuery.t_("ui.trial.rest")
	(%GuiltyButton as Button).text = SimQuery.t_("ui.trial.guilty")
	(%InnocentButton as Button).text = SimQuery.t_("ui.trial.innocent")
	(%WitnessesTitle as Label).text = SimQuery.t_("ui.trial.witnesses")
	visible = true
	refresh(true)
	ViewConfig.info("TrialPanel", "open (trial=%s, actor=%s)" % [tid, who])


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var v := Tribunal.view(sim, trial_id, actor)
	if v.is_empty():
		close()
		return
	var t: Dictionary = v["trial"]
	var sig := "%s|%s|%s|%s|%d" % [actor, t["status"], v["scale"], v["witnesses"], int(v["minutes_left"]) / 60]
	if sig == _sig and not force:
		return
	_sig = sig
	var hearing := str(t["status"]) == "hearing"
	(%Title as Label).text = SimQuery.t_("ui.trial.hearing_title" if hearing else "ui.trial.title") % [
		SimQuery.t_("charge." + str(t["charge"])), SimQuery.t_("severity." + str(t["severity"]))]
	var jl := %JudgeLabel as Label  # the hearing: who presides and that the game waits (owner decision 2026-11-02)
	jl.visible = false   # tribunal.md: the judge is in the row of portraits now
	jl.text = SimQuery.t_("ui.trial.judge") % (str(v["judge"]) if str(v["judge"]) != "" else SimQuery.t_("trial.town"))
	var left := int(v["minutes_left"])
	(%TimeLabel as Label).text = (SimQuery.t_("ui.trial.hearing_left") if hearing else SimQuery.t_("ui.trial.prep_left")) \
		% [left / Clock.MINUTES_PER_DAY, (left % Clock.MINUTES_PER_DAY) / 60]
	var accuser := str(v["accuser_name"])
	(%Parties as Label).text = SimQuery.t_("ui.trial.parties") % [str(v["accused_name"]),
		SimQuery.t_("trial.town").to_lower() if accuser == "@town" else accuser]
	(%Parties as Label).visible = false   # the row of portraits says it
	(%Stake as Label).text = SimQuery.t_("ui.trial.stake") % [SimQuery.t_("severity." + str(t["severity"])).to_upper(),
		SimQuery.t_("sentence." + str(t["severity"]))]
	var sc: Dictionary = v["scale"]
	var hidden := bool(v["proofs_hidden"])
	var acc := int(sc["accusation"]) - (int(sc["a"]["proofs"]) if hidden else 0)
	var rh: Dictionary = v["rhetoric"]
	(%DefenseLabel as Label).text = SimQuery.t_("ui.trial.defense_total") % int(sc["defense"])
	(%DefenseParts as Label).text = SimQuery.t_("ui.trial.defense_parts") % [int(rh["accused"]), int(sc["d"]["rhetoric"]),
		int(sc["favor"]), int(sc["d"]["favor"]), int(v["reputation"]), int(sc["d"]["reputation"])]
	(%AccusationLabel as Label).text = SimQuery.t_("ui.trial.accusation_total_hidden" if hidden \
		else "ui.trial.accusation_total") % acc
	(%AccusationParts as Label).text = SimQuery.t_("ui.trial.accusation_parts") % [int(rh["accuser"]),
		int(sc["a"]["rhetoric"]), int(sc["against"]), int(sc["a"]["against"]),
		"?" if hidden else str(int(sc["a"]["proofs"]))]
	_draw_balance(int(sc["defense"]), acc)
	_fill_parties(v, hearing)
	var ph := %ProofsHint as Label
	ph.visible = hidden and int(sc["a"]["proofs"]) > 0
	ph.text = SimQuery.t_("ui.trial.proofs_hint") % (SimQuery.t_("trial.town") if accuser == "@town" else accuser)
	_fill_witnesses(v, hearing)
	_fill_steps(v, hearing)
	var rest := %RestButton as Button
	rest.visible = hearing
	rest.disabled = str(v["rest_reason"]) != ""
	rest.tooltip_text = SimQuery.reason_text(str(v["rest_reason"])) if rest.disabled else SimQuery.t_("ui.trial.rest_tip")
	var judge := str(v["verdict_reason"]) == ""
	(%JudgeRow as Control).visible = hearing and judge
	(%Hint as Label).text = SimQuery.t_("ui.trial.hint_hearing" if hearing else "ui.trial.hint_prep")
	reset_size()


## The scale as in the mockup: green for the defense to the left of the middle, red for the accusation to the right,
## each as long as its share of the larger side (a dynamic bar: drawn by code, docs/protocolos/editar-a-mano.md).
func _draw_balance(defense: int, accusation: int) -> void:
	var track := %Balance as Control
	var w := track.size.x if track.size.x > 0.0 else track.custom_minimum_size.x
	var h := track.custom_minimum_size.y
	var half := w / 2.0
	var most := float(maxi(1, maxi(defense, accusation)))
	var dw := roundf(half * float(maxi(0, defense)) / most)
	var aw := roundf(half * float(maxi(0, accusation)) / most)
	var d := %DefenseFill as ColorRect
	var a := %AccusationFill as ColorRect
	d.position = Vector2(half - dw, 0)
	d.size = Vector2(dw, h)
	a.position = Vector2(half, 0)
	a.size = Vector2(aw, h)
	(%Middle as ColorRect).position = Vector2(half - 1, 0)


func _badge(disp: String) -> Label:
	var l := Label.new()
	l.name = "Disposition"
	l.custom_minimum_size = Vector2(66, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.12, 0.1, 0.1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = DISP_COLORS.get(disp, Color.WHITE)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	l.add_theme_stylebox_override("normal", sb)
	return l


## The portraits of the parties; in the hearing the judge's in the middle.
func _fill_parties(v: Dictionary, hearing: bool) -> void:
	var t: Dictionary = v["trial"]
	var st := sim.state
	for pair: Array in [[%AccusedSlot, str(t["accused"])], [%AccuserSlot, str(t.get("accuser", ""))]]:
		var slot := pair[0] as Control
		SocialKit.clear(slot)
		if st.characters.has(str(pair[1])):
			slot.add_child(SocialKit.portrait(st, str(pair[1])))
	(%AccusedText as Label).text = SimQuery.t_("ui.trial.accused_line") % str(v["accused_name"])
	var accuser := str(v["accuser_name"])
	(%AccuserText as Label).text = SimQuery.t_("ui.trial.accuser_line") % (SimQuery.t_("trial.town") if accuser == "@town" else accuser)
	var js := %JudgeSlot as Control
	SocialKit.clear(js)
	var judge := str((Offices.holders(sim, "judge") + [""])[0])
	js.visible = hearing and st.characters.has(judge)
	if js.visible:
		js.add_child(SocialKit.portrait(st, judge))
	(%VsLabel as Label).text = SimQuery.t_("ui.trial.judge") % (str(v["judge"]) if str(v["judge"]) != "" else SimQuery.t_("trial.town")) \
		if hearing else SimQuery.t_("ui.trial.versus")
	(%Hint as Label).visible = not hearing   # the hearing has «lo que va pasando» instead


## «Lo que va pasando» in the hearing: the scale's parts as steps.
func _fill_steps(v: Dictionary, hearing: bool) -> void:
	(%StepsTitle as Control).visible = hearing
	var box := %Steps as GridContainer
	SocialKit.clear(box)
	box.visible = hearing
	if not hearing:
		return
	(%StepsTitle as Label).text = SimQuery.t_("ui.trial.steps")
	var sc: Dictionary = v["scale"]
	var pts := int(sim.catalog.justice.get("trial", {}).get("witness", 15))
	var lines: Array = [[SimQuery.t_("ui.trial.step_plea_acc"), int(sc["a"]["rhetoric"]), false],
		[SimQuery.t_("ui.trial.step_proofs"), int(sc["a"]["proofs"]), false]]
	for w: Dictionary in v["witnesses"]:
		if not bool(w["alive"]):
			continue
		var disp := str(w["disposition"])
		if disp == "neutral":
			continue
		var txt := SimQuery.t_("ui.trial.step_witness_" + disp) % str(w["name"])
		var cross := str(w.get("cross", ""))
		var p := pts
		if cross != "":
			txt += " · " + SimQuery.t_("ui.trial.cross_" + cross)
			p = 0 if cross == "ok" else pts * 2
		lines.append([txt, p, disp == "favor"])
	lines.append([SimQuery.t_("ui.trial.step_plea_def"), int(sc["d"]["rhetoric"]) + int(sc["d"]["reputation"]), true])
	for i: int in lines.size():
		var row := HBoxContainer.new()
		row.name = "Step_%d" % i
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := SocialKit.label("%d. %s" % [i + 1, str(lines[i][0])], &"", "Text")
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var n := int(lines[i][1])
		row.add_child(SocialKit.label(("+%d" % n), &"PositiveLabel" if bool(lines[i][2]) else &"ReasonLabel", "Points"))
		box.add_child(row)


## A verdict against the scale asks first (tribunal.md §4).
func request_verdict(verdict: String) -> void:
	var v := Tribunal.view(sim, trial_id, actor)
	var sc: Dictionary = v.get("scale", {})
	var by_scale := "innocent" if int(sc.get("defense", 0)) > int(sc.get("accusation", 0)) else "guilty"
	var o := {"type": "trial_verdict", "actor": actor, "trial": trial_id, "verdict": verdict}
	if verdict == by_scale:
		_give(o)
		return
	SocialKit.ask(self, SimQuery.t_("ui.trial.verdict_q") % SimQuery.t_("ui.trial." + verdict), SimQuery.t_("ui.trial.verdict_body"),
		SimQuery.t_("ui.trial." + verdict), func() -> void: _give(o), SimQuery.t_("ui.menu.cannot_undo"))


func _fill_witnesses(v: Dictionary, hearing: bool) -> void:
	var box := %Witnesses as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for w: Dictionary in v["witnesses"]:
		var row := HBoxContainer.new()
		row.name = "W_" + str(w["character"])
		row.add_theme_constant_override("separation", 5)
		if sim.state.characters.has(str(w["character"])):
			var pf := SocialKit.portrait(sim.state, str(w["character"]))
			pf.scale = Vector2(0.75, 0.75)   # 30 px rows: five witnesses and the hearing's steps fit the modal
			var hold := Control.new()
			hold.custom_minimum_size = Vector2(30, 30)
			hold.add_child(pf)
			row.add_child(hold)
		var who := Label.new()
		who.custom_minimum_size = Vector2(150, 0)
		who.text = "%s · %s" % [str(w["name"]), SimQuery.t_("ui.trial.why_" + str(w["why"]))]
		row.add_child(who)
		var disp := str(w["disposition"])
		var d := _badge(disp)
		d.text = SimQuery.t_("ui.trial.disp_" + disp)
		if str(w.get("cross", "")) != "":
			d.text += " " + SimQuery.t_("ui.trial.cross_" + str(w["cross"]))
			d.custom_minimum_size = Vector2(130, 0)
		if not bool(w["alive"]):
			d.text = SimQuery.t_("ui.trial.gone")
		row.add_child(d)
		if hearing:
			if disp == "against":
				row.add_child(_button("Cross", SimQuery.t_("ui.trial.cross") % SimQuery.t_("ui.trial.band_" + str(
					w["bands"].get("cross", "doubtful"))), str(w["cross_reason"]),
					{"type": "trial_cross", "actor": actor, "trial": trial_id, "witness": str(w["character"])}, false))
		else:
			for k: String in ["convince", "bribe", "threaten"]:
				var text := SimQuery.t_("ui.trial.act_" + k)
				if k == "bribe":
					text = text % int(w["bribe_gold"])
				else:
					text = text % SimQuery.t_("ui.trial.band_" + str(w["bands"].get(k, "doubtful")))
				var why := str(w["actions"][k])
				row.add_child(_button(k.capitalize(), text, why, {"type": "witness_action", "actor": actor,
					"trial": trial_id, "witness": str(w["character"]), "kind": k}, true))
			var off := ""
			for k: String in ["convince", "bribe", "threaten"]:
				var why := str(w["actions"][k])
				if off == "" and why != "" and why != "too_far":
					off = SimQuery.t_("ui.npc.reason_line") % [SimQuery.t_("ui.trial.verb_" + k), _witness_reason(why, w)]
			if off != "":
				var r := SocialKit.label(off, &"ReasonLabel", "Why")
				r.clip_text = true
				r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(r)
		box.add_child(row)


func _button(node_name: String, text: String, why: String, o: Dictionary, walk: bool) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var far := walk and why == "too_far"
	b.disabled = why != "" and not far
	b.tooltip_text = SimQuery.t_("ui.court.walk") if far else (SimQuery.reason_text(why) if why != "" else "")
	b.pressed.connect(func() -> void: request(o, far))
	return b


## The reason a witness action is off, with the gold missing for a bribe.
func _witness_reason(why: String, w: Dictionary) -> String:
	if why == "not_enough_gold":
		var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
		return SimQuery.t_("ui.trial.gold_missing") % maxi(0, int(w["bribe_gold"]) - Money.gold(sim.state, fam))
	return SimQuery.reason_text(why)


## Bribing and threatening a witness ask first, with what it risks (tribunal.md §4).
func request(o: Dictionary, far: bool) -> void:
	var kind := str(o.get("kind", ""))
	var go := func() -> void:
		if far:
			_walk_then(o)
		else:
			_give(o)
	if not kind in ["bribe", "threaten"]:
		go.call()
		return
	var wa: Dictionary = sim.catalog.justice.get("witness_actions", {}).get(kind, {})
	var charge := str(wa.get("extra_charge", ""))
	var sev := SimQuery.t_("severity." + Tribunal.severity_of(sim, charge)) if charge != "" else ""
	var who := str(sim.state.characters.get(str(o.get("witness", "")), {}).get("name", ""))
	var band := SocialKit.check_band(sim, actor, str(o.get("witness", "")), str(wa.get("stat", "stealth")),
		str(wa.get("against", "empathy")))
	var odds := SocialKit.check_text(band, str(wa.get("stat", "stealth")), str(wa.get("against", "empathy")))
	var body := SimQuery.t_("ui.trial.ask_bribe_body") % [Tribunal.bribe_gold(sim, str(o.get("witness", ""))), odds,
		SimQuery.t_("charge." + charge), sev] if kind == "bribe" else SimQuery.t_("ui.trial.ask_threaten_body") % [odds,
		SimQuery.t_("charge." + charge), sev]
	SocialKit.ask(self, SimQuery.t_("ui.trial.ask_" + kind) % who, body, SimQuery.t_("ui.trial.verb_" + kind), go)


## Walks to the witness first and queues the action behind (like the townsperson's sheet).
func _walk_then(o: Dictionary) -> void:
	var spot := Courtship.spot(sim.state, str(o["witness"]))
	var orders: Array = []
	if str(sim.state.characters[actor].get("location", "")) != "":
		orders.append({"type": "exit_building", "actor": actor})
		orders.append({"type": "move_to", "actor": actor, "tile": spot, "queued": true})
	else:
		orders.append({"type": "move_to", "actor": actor, "tile": spot})
	var q := o.duplicate()
	q["queued"] = true
	orders.append(q)
	for x: Dictionary in orders:
		_give(x)


func _give(o: Dictionary) -> void:
	ViewConfig.info("TrialPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
