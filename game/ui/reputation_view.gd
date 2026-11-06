class_name ReputationView
extends RefCounted
## The Reputation tab of the account book (docs/ui/mecanicas/titulos_y_reputacion.md §3): the global figure and its
## trend of the last 2 days; each class as a bar with its modifier and the mark of what the next title asks; the
## passive reputation; the next title's requirements; and the last changes grouped by day and reason
## («Comercio justo ×6 · +6»), not one row per sale. Builds rows into the book's content box (the book only calls
## fill); reads the state only. Row names (tests): rep_global (its «Value»), rep_<class>, req_<kind>, log_<i>.

const TREND_DAYS: int = 2


static func fill(box: VBoxContainer, sim: Sim, fam: String) -> void:
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var rep := Reputation.of(st, fam)
	var now := int(st.clock["minute"])
	var log: Array = f.get("reputation_log", [])
	# global and trend
	var head := HBoxContainer.new()
	head.name = "rep_global"
	head.add_theme_constant_override("separation", 8)
	head.add_child(SocialKit.label(SimQuery.t_("ui.rep.title"), &"SectionTitle", "Name"))
	var v := SocialKit.label(str(rep), &"GoldLabel" if rep >= 0 else &"ReasonLabel", "Value")
	head.add_child(v)
	var trend := 0
	for e: Dictionary in log:
		if int(e.get("minute", 0)) >= now - TREND_DAYS * Clock.MINUTES_PER_DAY:
			trend += int(e.get("amount", 0))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(SocialKit.label(SimQuery.t_("ui.rep.trend") % [("↑ " if trend > 0 else ("↓ " if trend < 0 else "")) \
		+ SocialKit.signed(trend), TREND_DAYS], &"PositiveLabel" if trend > 0 else (&"ReasonLabel" if trend < 0 else &"DimLabel"),
		"Trend"))
	box.add_child(head)
	# classes as bars with the next title's mark
	var nx := Titles.next_of(sim, fam)
	var need := int(sim.catalog.titles().get(nx, {}).get("reputation", 0)) if nx != "" else rep
	var top := float(maxi(maxi(need, rep), 1)) * 1.25
	for c: Variant in sim.catalog.politics.get("reputation", {}).get("classes", []):
		var mod := Reputation.class_mod(st, fam, str(c))
		var row := HBoxContainer.new()
		row.name = "rep_" + str(c)
		row.add_theme_constant_override("separation", 6)
		var n := SocialKit.label(SimQuery.t_("class_people." + str(c)), &"", "Name")
		n.custom_minimum_size = Vector2(90, 0)
		row.add_child(n)
		var bar := SocialKit.threshold_bar(float(maxi(0, rep + mod)), top, float(need), 150.0, "Bar")
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var val := SocialKit.label("%d %s" % [rep + mod, SocialKit.signed(mod) if mod != 0 else ""], &"", "Value")
		val.custom_minimum_size = Vector2(56, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		box.add_child(row)
	if nx != "":
		var tn := SimQuery.title_name(nx)
		box.add_child(SocialKit.label(SimQuery.t_("ui.rep.mark") % [need, tn.substr(0, 1).to_upper() + tn.substr(1)], &"DimLabel", "MarkNote"))
	# passive
	var n_staff := 0
	for b: String in Titles.business_ids(sim, fam):
		for e: String in Staff.employees_of(st, b):
			if Staff.is_active(sim, e):
				n_staff += 1
				break
	var per := int(sim.catalog.politics.get("reputation", {}).get("passive", {}).get("per_business_with_staff", 0))
	box.add_child(SocialKit.label(SimQuery.t_("ui.ledger.rep.passive") % [per * n_staff, n_staff], &"DimLabel", "Passive"))
	# the next title's requirements
	if nx != "":
		box.add_child(SocialKit.label(SimQuery.t_("ui.ledger.rep.next") % [SimQuery.title_name(nx),
			Titles.cost_of(sim, fam, nx)], &"BoldLabel", "NextTitle"))
		for r: Dictionary in Titles.requirements(sim, fam, nx):
			if str(r["kind"]) == "gold":
				continue
			var line := HBoxContainer.new()
			line.name = "req_" + str(r["kind"])
			var a := SocialKit.label(SimQuery.t_("ui.town_hall.req_" + str(r["kind"])), &"", "Name")
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(a)
			var txt := (SimQuery.t_("ui.rep.done") if bool(r["ok"]) else SimQuery.t_("ui.rep.pending")) if str(r["kind"]) == "event" \
				else "%d / %d" % [int(r["have"]), int(r["need"])]
			line.add_child(SocialKit.label(txt, &"PositiveLabel" if bool(r["ok"]) else &"ReasonLabel", "Value"))
			box.add_child(line)
	# the last changes, grouped by day and reason
	box.add_child(SocialKit.label(SimQuery.t_("ui.rep.changes"), &"BoldLabel", "ChangesTitle"))
	var groups := grouped(log)
	if groups.is_empty():
		box.add_child(SocialKit.label(SimQuery.t_("ui.ledger.rep.none"), &"DimLabel", "None"))
	for i: int in mini(groups.size(), 12):
		var g: Dictionary = groups[i]
		var p := PanelContainer.new()
		p.name = "log_%d" % i
		p.theme_type_variation = &"RowPanel"
		var h := HBoxContainer.new()
		p.add_child(h)
		h.add_child(SocialKit.label(SimQuery.t_("ui.rep.day") % (int(g["day"]) + 1), &"DimLabel", "Day"))
		var what := LedgerPanel.reason_text(str(g["reason"]))
		if int(g["count"]) > 1:
			what += " ×%d" % int(g["count"])
		var w := SocialKit.label(what, &"", "What")
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w.clip_text = true
		h.add_child(w)
		h.add_child(SocialKit.label(SocialKit.signed(int(g["amount"])), &"PositiveLabel" if int(g["amount"]) >= 0 else &"ReasonLabel", "Amount"))
		box.add_child(p)


## The log grouped by (day, reason), newest first: [{day, reason, count, amount}].
static func grouped(log: Array) -> Array:
	var out: Array = []
	var index := {}
	for i: int in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		var day := Clock.day(int(e.get("minute", 0)))
		var reason := str(e.get("reason", ""))
		var k := "%d|%s" % [day, reason]
		if index.has(k):
			var g: Dictionary = out[int(index[k])]
			g["count"] = int(g["count"]) + 1
			g["amount"] = int(g["amount"]) + int(e.get("amount", 0))
		else:
			index[k] = out.size()
			out.append({"day": day, "reason": reason, "count": 1, "amount": int(e.get("amount", 0))})
	return out
