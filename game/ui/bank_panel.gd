class_name BankPanel
extends PanelContainer
## The Banco's panel (docs/gdd/04d_otras_clases.md 4.22.5.6-4.22.5.7; the wide zone of its interior), three tabs:
##  Solicitudes: the applications waiting (Bank.applications): who asks, how much and for how long, the risk («Buena
##    solvencia» A, «Regular» B, «Mala» C; with the Informe de solvencia, the exact chance of default of each
##    installment), the most they accept as annual interest; the interest chosen with − / + (5 points, up to that
##    maximum), what they would owe; Conceder (grant_loan) and Rechazar (reject_application).
##  Cartera: the loans of the family's Bancos that run: borrower, capital and interest, what is owed, the next
##    installment, notarial or not.
##  Impagos: the households' loans in default: what is owed, since when, what the town gives back (Bank.recovery) and
##    «Reclamar garantía» (claim_collateral), off until a day has passed.
## The figures line: gold, capital out (the principal left of the running loans), interest earned, losses. Reads the
## state, gives orders through order_sink. Rows are rebuilt only when what they show changes.

signal closed

const TABS: Array[String] = ["applications", "portfolio", "defaults"]
const STEP: float = 0.05

var order_sink: Callable = Callable()
var sim: Sim = null
var building: String = ""
var actor_id: String = ""
var tab: String = "applications"
var chosen: Dictionary = {}   # application id -> annual interest chosen
var _shown: String = ""        # what the rows show now (rebuilt only when it changes)
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	for t: String in TABS:
		(get_node("%Tab" + t.to_pascal_case()) as Button).pressed.connect(show_tab.bind(t))


func setup(s: Sim, bld: String, who: String) -> void:
	_bind()
	sim = s
	building = bld
	set_actor(who)
	(%Title as Label).text = SimQuery.building_label(s.state, s.catalog, bld)
	for t: String in TABS:
		(get_node("%Tab" + t.to_pascal_case()) as Button).text = SimQuery.t_("ui.bank.tab." + t)
	_shown = ""
	refresh()


## Who gives the orders: `who` if it is of the owner family, else the owner family's head.
func set_actor(who: String) -> void:
	if sim == null:
		actor_id = who
		return
	var fam := str(sim.state.buildings.get(building, {}).get("owner", ""))
	actor_id = who if who != "" and str(sim.state.characters.get(who, {}).get("family", "")) == fam \
		else str(sim.state.families.get(fam, {}).get("head", who))


func open() -> void:
	visible = true
	_shown = ""
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_tab(t: String) -> void:
	tab = t
	ViewConfig.info("BankPanel", "tab %s (building=%s)" % [t, building])
	_shown = ""
	refresh()


var _minute: int = -1


func _process(_d: float) -> void:
	if visible and sim != null and int(sim.state.clock["minute"]) != _minute:
		_minute = int(sim.state.clock["minute"])
		refresh()


func _fam() -> String:
	return str(sim.state.buildings.get(building, {}).get("owner", ""))


func refresh() -> void:
	if sim == null or not sim.state.buildings.has(building):
		return
	for t: String in TABS:
		(get_node("%Tab" + t.to_pascal_case()) as Button).set_pressed_no_signal(t == tab)
	(%Figures as Label).text = figures_line()
	(%Hint as Label).text = SimQuery.t_("ui.bank.hint." + tab)
	var key := _signature()
	if key == _shown:
		return
	_shown = key
	var body := %Body as VBoxContainer
	for c: Node in body.get_children():
		body.remove_child(c)
		c.queue_free()
	match tab:
		"applications":
			_build_applications(body)
		"portfolio":
			_build_portfolio(body)
		"defaults":
			_build_defaults(body)


## What the rows depend on: the tab, the applications, the loans' states and what they owe, the gold, the day.
func _signature() -> String:
	var parts: PackedStringArray = [tab, str(Money.gold(sim.state, _fam())), str(Clock.day(int(sim.state.clock["minute"])))]
	for a: Dictionary in Bank.applications(sim.state, building):
		parts.append("%s:%s" % [a["id"], chosen.get(str(a["id"]), "")])
	for id: String in Bank.portfolio(sim.state, _fam()):
		var l: Dictionary = sim.state.loans[id]
		parts.append("%s:%s:%d" % [id, l.get("state", ""), int(l.get("outstanding", 0))])
	return "|".join(parts)


## «Oro 600 · prestado 1.200 · intereses 85 · pérdidas 0».
func figures_line() -> String:
	var fam := _fam()
	var out_cap := 0
	for id: String in Bank.portfolio(sim.state, fam):
		var l: Dictionary = sim.state.loans[id]
		if str(l.get("state", "")) in [Loans.ACTIVE, Loans.EXTENDED, "defaulted"]:
			out_cap += int(l.get("principal_left", 0))
	var interest := 0
	var losses := 0
	for e: Dictionary in sim.state.ledger.get("entries", []):
		if str(e.get("family", "")) != fam:
			continue
		if str(e["category"]) == Money.INTEREST:
			interest += int(e["amount"])
		elif str(e["category"]) == Money.BANK_LOSSES:
			losses -= int(e["amount"])
	return SimQuery.t_("ui.bank.figures") % [Money.gold(sim.state, fam), out_cap, interest, losses]


func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, name_: String, disabled: bool, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = name_
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _family_name(fam: String) -> String:
	return SimQuery.t_("ui.bank.the_family") % str(sim.state.families.get(fam, {}).get("name", fam))


## The risk's words (and its exact chance of default with the Informe de solvencia).
func risk_text(risk: String) -> String:
	var t := SimQuery.t_("ui.bank.risk." + risk)
	if Upgrades.flag(sim, building, "bank_exact_risk"):
		t += " (%d %%)" % roundi(float(Bank.risk_of(sim, building, risk)["default"]) * 100.0)
	return t


func interest_of(app: Dictionary) -> float:
	return float(chosen.get(str(app["id"]), float(app["max_interest"])))


func _build_applications(body: VBoxContainer) -> void:
	var apps := Bank.applications(sim.state, building)
	if apps.is_empty():
		body.add_child(_label(SimQuery.t_("ui.bank.no_applications"), &"DimLabel"))
		return
	var gold := Money.gold(sim.state, _fam())
	for a: Dictionary in apps:
		var id := str(a["id"])
		var box := VBoxContainer.new()
		box.name = "App_" + id
		box.add_theme_constant_override("separation", 1)
		var who := _family_name(str(a["borrower_family"]))
		if str(a["kind"]) == "family":
			who += " · " + SimQuery.t_("ui.bank.a_family")
		box.add_child(_label(SimQuery.t_("ui.bank.asks") % [who, int(a["amount"]), int(a["term_days"])], &"BoldLabel"))
		var rk := _label(SimQuery.t_("ui.bank.risk_line") % [risk_text(str(a["risk"])), roundi(float(a["max_interest"]) * 100.0)])
		rk.theme_type_variation = &"PositiveLabel" if str(a["risk"]) == "A" else (&"WarningLabel" if str(a["risk"]) == "B" else &"ReasonLabel")
		box.add_child(rk)
		var row := HBoxContainer.new()
		var rate := interest_of(a)
		var q := Bank.quote(sim, int(a["amount"]), int(a["term_days"]), rate)
		row.add_child(_button("−", "Down", rate <= STEP + 0.0001, "", func() -> void: _nudge(a, -STEP)))
		var il := _label(SimQuery.t_("ui.bank.interest") % [roundi(rate * 100.0), int(q["owed"])])
		il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(il)
		row.add_child(_button("+", "Up", rate >= float(a["max_interest"]) - 0.0001, "", func() -> void: _nudge(a, STEP)))
		var short := gold < int(a["amount"])
		row.add_child(_button(SimQuery.t_("ui.bank.grant"), "Grant", short,
			SimQuery.t_("reason.not_enough_gold") if short else "", func() -> void: grant(id)))
		row.add_child(_button(SimQuery.t_("ui.bank.reject"), "Reject", false, "", func() -> void:
			_give({"type": "reject_application", "actor": actor_id, "application": id})))
		box.add_child(row)
		body.add_child(box)
		body.add_child(HSeparator.new())


func _nudge(a: Dictionary, step: float) -> void:
	var r := clampf(snappedf(interest_of(a) + step, 0.01), STEP, float(a["max_interest"]))
	chosen[str(a["id"])] = r
	refresh()


## Conceder: grant_loan at the interest chosen (the maximum unless changed).
func grant(id: String) -> void:
	var a := Bank.find_application(sim.state, id)
	if a.is_empty():
		return
	_give({"type": "grant_loan", "actor": actor_id, "application": id, "interest": interest_of(a)})
	chosen.erase(id)


func _build_portfolio(body: VBoxContainer) -> void:
	var any := false
	for id: String in Bank.portfolio(sim.state, _fam()):
		var l: Dictionary = sim.state.loans[id]
		if not str(l.get("state", "")) in [Loans.ACTIVE, Loans.EXTENDED]:
			continue
		any = true
		var box := VBoxContainer.new()
		box.name = "Loan_" + id
		box.add_theme_constant_override("separation", 1)
		box.add_child(_label(SimQuery.t_("ui.bank.loan_line") % [_family_name(str(l["family"])), int(l["principal"]),
			roundi(float(l.get("annual_interest", 0.0)) * 100.0), int(l["outstanding"])], &"BoldLabel"))
		var nd := Loans.next_due(l)
		var more := SimQuery.t_("ui.bank.next") % [Loans.next_amount(l), SimQuery.minute_label(nd - 1)]
		if bool(l.get("notarized", false)):
			more += " · " + SimQuery.t_("ui.bank.notarized")
		if str(l.get("state", "")) == Loans.EXTENDED:
			more += " · " + SimQuery.t_("ui.bank.extended")
		box.add_child(_label(more, &"DimLabel"))
		body.add_child(box)
	if not any:
		body.add_child(_label(SimQuery.t_("ui.bank.no_loans"), &"DimLabel"))


func _build_defaults(body: VBoxContainer) -> void:
	var any := false
	var after := int(Bank.cfg(sim).get("recovery", {}).get("claim_after_days", 1)) * Clock.MINUTES_PER_DAY
	for id: String in Bank.portfolio(sim.state, _fam()):
		var l: Dictionary = sim.state.loans[id]
		if str(l.get("state", "")) != "defaulted":
			continue
		any = true
		var box := VBoxContainer.new()
		box.name = "Default_" + id
		box.add_child(_label(SimQuery.t_("ui.bank.default_line") % [_family_name(str(l["family"])), int(l["outstanding"]),
			SimQuery.minute_label(int(l.get("defaulted_at", 0)))], &"ReasonLabel"))
		var soon := int(sim.state.clock["minute"]) - int(l.get("defaulted_at", 0)) < after
		box.add_child(_button(SimQuery.t_("ui.bank.claim") % Bank.recovery(sim, id), "Claim", soon,
			SimQuery.t_("reason.too_soon") if soon else "", func() -> void:
				_give({"type": "claim_collateral", "actor": actor_id, "loan": id})))
		body.add_child(box)
	if not any:
		body.add_child(_label(SimQuery.t_("ui.bank.no_defaults"), &"DimLabel"))


func _give(o: Dictionary) -> void:
	ViewConfig.info("BankPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_shown = ""
	refresh()
