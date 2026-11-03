class_name TrialPanel
extends PanelContainer
## The trial (GDD 4.12.5, H11; docs/ui/mecanicas/tribunal.md of diseno-ui): accused against accuser, the charge and its
## severity with the sentence it may bring, the time left; the scale with its parts (the accuser's proofs «?» until
## the hearing); the 3-5 witnesses with their disposition and, in the preparation, Convince / Bribe / Threaten for the
## selected person (far away: walks first, the action queued). In the hearing, the same panel: Question the witnesses
## against, Rest the defense, and the judge (if it is the selected person and not a party) can rule. Opens with the
## HUD's Trials button (key J), a trial notice or when the hearing starts (the HUD pauses then). Reads the state and gives
## orders (order_sink).

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
	(%GuiltyButton as Button).pressed.connect(func() -> void: _give({"type": "trial_verdict", "actor": actor,
		"trial": trial_id, "verdict": "guilty"}))
	(%InnocentButton as Button).pressed.connect(func() -> void: _give({"type": "trial_verdict", "actor": actor,
		"trial": trial_id, "verdict": "innocent"}))


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
	jl.visible = hearing
	jl.text = SimQuery.t_("ui.trial.judge") % (str(v["judge"]) if str(v["judge"]) != "" else SimQuery.t_("trial.town"))
	var left := int(v["minutes_left"])
	(%TimeLabel as Label).text = (SimQuery.t_("ui.trial.hearing_left") if hearing else SimQuery.t_("ui.trial.prep_left")) \
		% [left / Clock.MINUTES_PER_DAY, (left % Clock.MINUTES_PER_DAY) / 60]
	var accuser := str(v["accuser_name"])
	(%Parties as Label).text = SimQuery.t_("ui.trial.parties") % [str(v["accused_name"]),
		SimQuery.t_("trial.town").to_lower() if accuser == "@town" else accuser]
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
	_fill_witnesses(v, hearing)
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


func _fill_witnesses(v: Dictionary, hearing: bool) -> void:
	var box := %Witnesses as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for w: Dictionary in v["witnesses"]:
		var row := HBoxContainer.new()
		row.name = "W_" + str(w["character"])
		row.add_theme_constant_override("separation", 5)
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
		box.add_child(row)


func _button(node_name: String, text: String, why: String, o: Dictionary, walk: bool) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var far := walk and why == "too_far"
	b.disabled = why != "" and not far
	b.tooltip_text = SimQuery.t_("ui.court.walk") if far else (SimQuery.reason_text(why) if why != "" else "")
	b.pressed.connect(func() -> void:
		if far:
			_walk_then(o)
		else:
			_give(o))
	return b


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
