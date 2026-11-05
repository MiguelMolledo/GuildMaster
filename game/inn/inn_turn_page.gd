class_name InnTurnPage
extends RefCounted
## The turn summary of the Taberna-Posada (docs/gdd/04f_vida_y_fiestas.md §4.27.4): the data for PageCard from the
## summary Inn.close_turn leaves in buildings[bld].inn.last_turn, and the same lines for the panel's Turno tab: guests
## by group, dishes sold, income and tips, beds, complaints, the fame gained or lost, the incidents and the rumour.
## Presentation only.


## The lines of a summary (the panel and the card's paragraphs).
static func lines(sim: Sim, t: Dictionary) -> Array:
	var out: Array = []
	var groups: PackedStringArray = []
	for g: Variant in sim.catalog.inn.get("clientele", {}).get("order", []):
		var bg: Dictionary = t.get("by_group", {}).get(g, {})
		if int(bg.get("came", 0)) > 0:
			groups.append("%s %d" % [SimQuery.t_("inn.group." + str(g)), int(bg["came"])])
	out.append(SimQuery.t_("ui.inn.sum.guests") % [int(t.get("guests", 0)), ", ".join(groups) if not groups.is_empty()
		else SimQuery.t_("ui.inn.sum.nobody")])
	var dishes: PackedStringArray = []
	var ids: Array = (t.get("dishes", {}) as Dictionary).keys()
	ids.sort()
	for d: Variant in ids:
		dishes.append("%s ×%d" % [SimQuery.t_("item." + str(Inn.dish(sim, str(d)).get("item", d))), int(t["dishes"][d])])
	if not dishes.is_empty():
		out.append(SimQuery.t_("ui.inn.sum.dishes") % ", ".join(dishes))
	out.append(SimQuery.t_("ui.inn.sum.money") % [int(t.get("income", 0)), int(t.get("tips", 0)), int(t.get("beds", 0)),
		int(t.get("beds_income", 0))])
	if int(t.get("house_cut", 0)) > 0:
		out.append(SimQuery.t_("ui.inn.sum.house_cut") % int(t["house_cut"]))
	var comp: PackedStringArray = []
	var ck: Array = (t.get("complaints", {}) as Dictionary).keys()
	ck.sort()
	for k: Variant in ck:
		comp.append("%s %d" % [SimQuery.t_("ui.inn.complaint." + str(k)), int(t["complaints"][k])])
	out.append(SimQuery.t_("ui.inn.sum.complaints") % (", ".join(comp) if not comp.is_empty() else SimQuery.t_("ui.inn.sum.none")))
	if int(t.get("dirty_beds", 0)) > 0:
		out.append(SimQuery.t_("ui.inn.sum.dirty_beds") % int(t["dirty_beds"]))
	var df := float(t.get("fame_after", 0.0)) - float(t.get("fame_before", 0.0))
	out.append(SimQuery.t_("ui.inn.sum.fame") % [("+" if df >= 0.0 else "") + SimQuery._num(snappedf(df, 0.01)),
		SimQuery._num(snappedf(float(t.get("fame_after", 0.0)), 0.1))])
	for i: Dictionary in t.get("incidents", []):
		out.append(SimQuery.t_("ui.inn.incident." + str(i.get("kind", ""))))
	if bool(t.get("minstrel", false)):
		out.append(SimQuery.t_("ui.inn.incident.minstrel"))
	var r: Dictionary = t.get("rumor", {})
	if not r.is_empty():
		out.append(SimQuery.t_("ui.inn.sum.rumor") % rumor_text(sim, r))
	return out


## A rumour as text: inn.rumor.<kind> with its args (items, cities and events by name).
static func rumor_text(sim: Sim, r: Dictionary) -> String:
	if str(r.get("kind", "")) == "life":
		return LifeQuery.rumor_text(sim, r)  # vida's rumours (data/life/rumors.json)
	var args: Array = (r.get("args", []) as Array).duplicate()
	match str(r.get("kind", "")):
		"price":
			args = [SimQuery.t_("item." + str(args[0])), SimQuery.t_("region." + str(args[1]))]
		"event":
			args = [SimQuery.t_("event." + str(args[0]))]
	var t := SimQuery.t_(str(r.get("key", "")))
	return t % args if t.count("%") >= args.size() and not args.is_empty() else t


## The PageCard data of the turn closed in `bld` ({} without summary).
static func data_for(sim: Sim, bld: String) -> Dictionary:
	var t: Dictionary = Inn.state_of(sim, bld).get("last_turn", {})
	if t.is_empty():
		return {}
	var blocks: Array = []
	var ls := lines(sim, t)
	blocks.append({"type": "paragraph", "text": str(ls[0])})
	var effects: Array = []
	var bad := {}
	var good := {}
	for i: Dictionary in t.get("incidents", []):
		var k := str(i.get("kind", ""))
		(bad if k in ["fight", "dash"] else good)[SimQuery.t_("ui.inn.incident." + k)] = true
	good[SimQuery.t_("ui.inn.incident.minstrel")] = true
	for i: int in range(1, ls.size()):
		var s := str(ls[i])
		effects.append({"text": s, "sign": "-" if bad.has(s) else ("+" if good.has(s) else "")})
	blocks.append({"type": "effects", "items": effects})
	var total := int(t.get("income", 0)) + int(t.get("tips", 0)) + int(t.get("beds_income", 0)) + int(t.get("house_cut", 0))
	return {"template": "card", "title": SimQuery.t_("ui.inn.sum.title") % (int(t.get("day", 0)) + 1),
		"image": VisualPaths.illustration("events", "inn_turn"), "blocks": blocks,
		"footer_figures": [{"label": SimQuery.t_("ui.inn.sum.total"), "value": str(total)}],
		"buttons": [{"id": "ok", "text": SimQuery.t_("ui.event_card.ok"), "primary": true}],
		"seconds": float(ViewConfig.value("event_card_seconds", 12.0)), "building": bld}
