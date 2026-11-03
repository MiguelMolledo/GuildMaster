extends "res://tests/test_case.gd"
## docs/ui/mecanicas/rivales.md, only what exists without the rival AI (04c): the families panel lists the rival
## family first with what is public (title, reputation, businesses, head), the neighbours folded; its sheet shows its
## members, businesses from outside and public facts and never its gold or stores (_social rule 5); the townsperson's
## sheet links to its family.

const HERO := "chr_0001"

var cat := Catalog.load_from()


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _texts(n: Node) -> String:
	var out: PackedStringArray = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		out.append(_texts(c))
	return " ".join(out)


func _rival(sim: Sim) -> String:
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			return f
	return ""


func test_list_and_sheet_show_only_what_is_public() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim("town_e_start")
	var rival := _rival(sim)
	check(rival != "", "there is a rival family")
	var p: FamiliesPanel = _scene("res://game/ui/families_panel.tscn")
	p.open_for(sim, HERO)
	var g := p.groups()
	check(rival in (g[0] as Array), "the rival competes with you")
	check(not (p.get_node("%NeighboursList") as Control).visible, "the neighbours folded")
	var row := p.get_node("%RivalsList").get_node("Fam_" + rival)
	check((row.find_child("Public", true, false) as Label).text.contains("rep."), "what is public")
	p.show_family(rival)
	check((p.get_node("%SheetPage") as Control).visible, "its sheet")
	check(p.get_node("%Members").get_child_count() > 0, "its members")
	check(p.get_node("%Businesses").get_child_count() > 0, "its businesses")
	var all := _texts(p)
	var gold := Money.gold(sim.state, rival)
	check(not all.contains(MenuKit.gold_text(gold) + " de oro") and not all.contains("%d de oro" % gold), "never its gold (%d)" % gold)
	check((p.get_node("%NoGold") as Label).text.contains("no se sabe"), "the gold's place says so")
	p.free()
	TranslationServer.set_locale(before)


func test_the_sheet_links_to_the_family() -> void:
	var sim := _sim("town_e_start")
	var rival := _rival(sim)
	var head := str(sim.state.families[rival]["head"])
	var n: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	n.setup(sim, HERO, head)
	check((n.get_node("%FamilyLink") as Button).visible, "«Familia Ferrer ›»")
	n.free()
