class_name TrialCard
extends PanelContainer
## The court's cards (GDD 4.12.5, H11): «You are accused» when a trial opens against the player's family (who accuses,
## the charge and its severity, what it may cost, until when to prepare; «Prepare the defense» opens the trial panel),
## and the verdict (stamp INNOCENT / GUILTY, the final scale and the concrete sentence) when a trial of the player's
## family ends. Closes with a click, the button, or by itself after `trial_card_seconds` (data/view.json). Reads only.

signal prepare_requested(trial_id: String)

var trial_id: String = ""
var _left: float = 0.0
var _mode: String = ""


var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%OkButton as Button).pressed.connect(close)
	(%PrepareButton as Button).pressed.connect(func() -> void:
		close()
		prepare_requested.emit(trial_id))


## «You are accused» for trial `tid`.
func show_accusation(sim: Sim, tid: String) -> void:
	var v := Tribunal.view(sim, tid, "")
	if v.is_empty():
		return
	var t: Dictionary = v["trial"]
	_mode = "accusation"
	trial_id = tid
	var accuser := str(v["accuser_name"])
	(%Header as Label).text = SimQuery.t_("ui.trial_card.accused")
	(%Stamp as Label).visible = false
	(%Text as Label).text = SimQuery.t_("ui.trial_card.accused_text") % [SimQuery.t_("trial.town") if accuser == "@town"
		else accuser, str(v["accused_name"]), SimQuery.t_("charge." + str(t["charge"])),
		SimQuery.t_("severity." + str(t["severity"]))]
	(%Detail as Label).text = SimQuery.t_("ui.trial_card.accused_detail") % [SimQuery.t_("sentence." + str(t["severity"])),
		Clock.day(int(t["prep_until"])) + 1]
	(%PrepareButton as Button).text = SimQuery.t_("ui.trial_card.prepare")
	(%PrepareButton as Button).visible = true
	(%OkButton as Button).text = SimQuery.t_("ui.trial_card.later")
	_show(float(ViewConfig.value("trial_card_seconds", 12.0)))


## The verdict of trial_verdict event `e`.
func show_verdict(sim: Sim, e: Dictionary) -> void:
	var st := sim.state
	var t := Tribunal.trial(st, str(e.get("trial", "")))
	if t.is_empty():
		return
	_mode = "verdict"
	trial_id = str(t["id"])
	var guilty := str(t["verdict"]) == "guilty"
	(%Header as Label).text = SimQuery.t_("ui.trial_card.verdict") % SimQuery.t_("charge." + str(t["charge"]))
	var stamp := %Stamp as Label
	stamp.visible = true
	stamp.text = "— %s —" % SimQuery.t_("ui.trial_card.guilty" if guilty else "ui.trial_card.innocent")  # the stamp in bold capitals
	stamp.theme_type_variation = &"SealLabel" if guilty else &"GoldLabel"
	(%Text as Label).text = SimQuery.t_("ui.trial_card.scale") % [str(st.characters.get(str(t["accused"]), {}).get(
		"name", "")), int(t["scale"].get("defense", 0)), int(t["scale"].get("accusation", 0))]
	(%Detail as Label).text = sentence_text(sim, t)
	(%PrepareButton as Button).visible = false
	(%OkButton as Button).text = SimQuery.t_("ui.title_card.ok") if not guilty else SimQuery.t_("ui.trial_card.ok")
	_show(float(ViewConfig.value("trial_card_seconds", 12.0)))


## What the trial cost (or that it cost nothing), in words.
static func sentence_text(sim: Sim, t: Dictionary) -> String:
	if str(t["verdict"]) != "guilty":
		return SimQuery.t_("ui.trial_card.free_fabricated" if bool(t.get("fabricated", false)) else "ui.trial_card.free")
	var s: Dictionary = t.get("sentence", {})
	match str(s.get("kind", "")):
		"fine":
			return SimQuery.t_("ui.trial_card.s_fine") % int(s.get("gold", 0))
		"confiscation":
			return SimQuery.t_("ui.trial_card.s_confiscation") % [int(s.get("units", 0)),
				SimQuery.building_label(sim.state, sim.catalog, str(s.get("building", "")))]
		"office_loss":
			var parts: PackedStringArray = []
			if str(s.get("office", "")) != "":
				parts.append(SimQuery.t_("ui.trial_card.s_office") % SimQuery.office_name(str(s["office"])))
			if str(s.get("title", "")) != "":
				parts.append(SimQuery.t_("ui.trial_card.s_title") % SimQuery.title_name(str(s["title"])))
			return " · ".join(parts) if not parts.is_empty() else SimQuery.t_("sentence.grave")
		"banishment":
			return SimQuery.t_("ui.trial_card.s_banished") % (int(s.get("until", 0)) + 1)
	return ""


func _show(seconds: float) -> void:
	_bind()
	visible = true
	_left = seconds
	reset_size()
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) / 2.0).round()
	ViewConfig.info("TrialCard", "%s (trial=%s)" % [_mode, trial_id])


func close() -> void:
	visible = false
	_left = 0.0


func _process(delta: float) -> void:
	if visible and _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()
