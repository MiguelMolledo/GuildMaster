class_name WeddingCard
extends PageCard
## The wedding card (docs/ui/mecanicas/cortejo_y_boda.md §3, §6), a «Carta» of the page kit
## (docs/ui/04_kit_de_pagina.md §4): when someone of the player's family marries (event wedding), a letter in the middle
## with «¡Hugo y Agnès se casan!» on the ribbon, the two portraits with their names and each family's colours under
## them, «&» between them, and what it means: the spouse lives in the family's home now, the job it leaves
## (employee_left married of the same step, or its trade), when the first child may come (the wife's wedding day +
## data/family.json children.first_child_days). A click or the button closes it; also by itself after view.json
## title_card_seconds. Listens to Events itself; reads only, gives no orders.

var wedding: Dictionary = {}   # what the card says (tests): {a, b, lines}


func _ready() -> void:
	super._ready()
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			var sim: Sim = g.get("sim")
			for e: Dictionary in events:
				if str(e.get("type", "")) == "wedding" and str(e.get("family", "")) == SimQuery.player_family(sim.state):
					show_for(sim, e, events))


## Shows the card for wedding event `e` (and the events of its step: the job left).
func show_for(sim: Sim, e: Dictionary, events: Array = []) -> void:
	show_page(data_for(sim, e, events))
	ViewConfig.info("WeddingCard", "wedding: %s + %s (%s)" % [wedding.get("a", ""), wedding.get("b", ""),
		wedding.get("lines", [])])


## The PageCard data of wedding event `e`.
func data_for(sim: Sim, e: Dictionary, events: Array = []) -> Dictionary:
	var st := sim.state
	var a := str(e.get("character", ""))
	var b := str(e.get("spouse", ""))
	var fam := str(e.get("family", ""))
	var old := str(e.get("from_family", ""))
	var ac: Dictionary = st.characters.get(a, {})
	var bc: Dictionary = st.characters.get(b, {})
	var lines: PackedStringArray = [SimQuery.t_("ui.wedding.home") % str(bc.get("name", b))]
	for x: Dictionary in events:
		if str(x.get("type", "")) == "employee_left" and str(x.get("employee", "")) == b and str(x.get("reason", "")) == "married":
			lines.append(SimQuery.t_("ui.wedding.job") % SimQuery.building_label(st, sim.catalog, str(x.get("building", ""))))
	if lines.size() == 1 and str(bc.get("occupation", "")) != "" and not TownLife.is_household(st, fam):
		lines.append(SimQuery.t_("ui.wedding.job") % SimQuery.occupation_name(str(bc["occupation"])))  # no longer a townsperson
	var wife: Dictionary = bc if bool(bc.get("female", false)) else ac
	var wd := int(wife.get("life", {}).get("wedding_day", -1)) if wife.get("life") is Dictionary else -1
	if wd >= 0:
		var first := wd + int(sim.catalog.family.get("children", {}).get("first_child_days", 0))
		lines.append(SimQuery.t_("ui.wedding.child") % (first + 1))
	wedding = {"a": a, "b": b, "lines": lines}
	var people := {"type": "portraits", "mid": "&",
		"left_name": str(ac.get("name", a)), "right_name": str(bc.get("name", b)),
		"left_band": SocialKit.ribbon(st, fam, Vector2(64, 6)),
		"right_band": SocialKit.ribbon(st, old if st.families.has(old) else fam, Vector2(64, 6))}
	for pair: Array in [["left_node", a], ["right_node", b]]:
		if st.characters.has(str(pair[1])):
			var p := SocialKit.portrait(st, str(pair[1]))
			p.scale = Vector2(2, 2)
			var holder := Control.new()  # a scaled Control keeps its unscaled size in containers: reserve the ×2
			holder.custom_minimum_size = p.custom_minimum_size * 2.0 if p.custom_minimum_size != Vector2.ZERO \
				else Vector2(80, 80)
			holder.add_child(p)
			people[pair[0]] = holder
	var items: Array = []
	for l: String in lines:
		items.append({"text": l, "sign": ""})
	return {"template": "card", "title": SimQuery.t_("ui.wedding.text") % [str(ac.get("name", a)),
		str(bc.get("name", b))], "blocks": [people, {"type": "divider"}, {"type": "effects", "items": items}],
		"buttons": [{"id": "ok", "text": SimQuery.t_("ui.wedding.ok"), "primary": true}],
		"seconds": float(ViewConfig.value("title_card_seconds", 8.0))}
