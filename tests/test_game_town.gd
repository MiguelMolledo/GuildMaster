extends "res://tests/test_case.gd"
## H7 view (GDD 4.11.3, 4.11.5, 4.20, 4.5.4): every bubble and emotion icon has its scene; a walker shows the bubble
## of its activity and the emotion first; the townsperson nearest to the selected person says a phrase of its bank;
## the NPC sheet shows the emotion and gives the actions (walking first when far); the microevent card shows the text
## and the choices and gives resolve_microevent; the interior puts a customer at the counter. Windowless: the scenes
## are built by hand and the orders are caught by a sink.

const FAM := "fam_0001"
const HERO := "chr_0001"
const FORGE := "bld_0001"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _sink(o: Dictionary) -> void:
	_orders.append(o.duplicate(true))


func _texts(n: Node) -> String:
	var out: PackedStringArray = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		out.append(_texts(c))
	return " ".join(out)


func test_every_bubble_has_its_scene() -> void:
	for a: String in cat.town["activities"]:
		var b := str(cat.town["activities"][a]["bubble"])
		check(VisualPaths.has_scene("bubbles", b), "bubble %s of %s" % [b, a])
	for e: String in cat.town["emotions"]:
		check(VisualPaths.has_scene("bubbles", str(cat.town["emotions"][e]["icon"])), "icon of %s" % e)
	for p: String in ["bench", "dice_table"]:
		check(VisualPaths.has_scene("props", p), "prop %s" % p)
	var v := VisualPaths.instantiate("bubbles", "chat")
	check(v.get_node_or_null("Feet") != null and v.get_node_or_null("Greybox") != null, "Feet and Greybox")
	v.free()


func test_bubble_of_activity_and_emotion_first() -> void:
	var sim := _sim("plaza_dusk")
	sim.run_minutes(100)
	var social := ""
	for id: String in Population.townsfolk(sim.state):
		if str(TownLife.view(sim, id)["state"]) == "social" and str(TownLife.view(sim, id)["activity"]) != "greet":
			social = id
			break
	check(social != "", "somebody socialises at 20:20")
	var act := str(TownLife.view(sim, social)["activity"])
	eq(SimQuery.bubble_of(sim, social), str(cat.town["activities"][act]["bubble"]), "the activity's bubble")
	Emotions.add(sim, social, "angry", FAM)
	eq(SimQuery.bubble_of(sim, social), "emotion_angry", "an emotion goes first (4.11.5)")
	var cv := CharacterView.new()
	cv.setup(sim.state.characters[social], sim.state.families[str(sim.state.characters[social]["family"])])
	cv.set_bubble(SimQuery.bubble_of(sim, social))
	eq(cv.bubble_id, "emotion_angry", "the walker shows it")
	check(cv.get_node_or_null("Bubble") != null, "as a child scene")
	cv.set_bubble("")
	cv.free()


func test_the_nearest_townsperson_speaks() -> void:
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	var pos: Array = sim.state.characters[npc]["position"]
	sim.state.characters[HERO]["location"] = ""
	sim.state.characters[HERO]["position"] = [int(pos[0]), int(pos[1]) + 2]
	var talker := SimQuery.nearest_talker(sim, HERO)
	check(talker != "", "somebody near")
	var text := SimQuery.town_phrase(sim, talker, HERO)
	check(text != "" and not text.begins_with("phrase."), "a translated phrase (%s)" % text)
	sim.state.characters[HERO]["position"] = [2, 19]
	eq(SimQuery.town_phrase(sim, npc, HERO), "", "far away: nothing")


func test_npc_sheet_shows_emotion_and_gives_actions() -> void:
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	Emotions.add(sim, npc, "angry", FAM)
	var pos: Array = sim.state.characters[npc]["position"]
	sim.state.characters[HERO]["location"] = ""
	sim.state.characters[HERO]["position"] = [int(pos[0]), int(pos[1]) + 1]
	var panel: NpcPanel = (load("res://game/ui/npc_panel.tscn") as PackedScene).instantiate()
	panel.order_sink = _sink
	panel.setup(sim, HERO, npc)
	panel.open()
	var txt := _texts(panel)
	check(txt.contains(SimQuery.t_("emotion.angry")), "the emotion is listed (%s)" % txt)
	check(txt.contains(str(sim.state.characters[npc]["name"])), "the name")
	var acts := panel.get_node("%Actions")
	eq(acts.get_children().filter(func(n: Node) -> bool: return n.name != "AccuseRow").size(), 5,
		"five actions (H11 adds the accuse row)")
	check((acts.get_node("Talk") as Button).disabled, "angry: will not talk")
	_orders = []
	(acts.get_node("Insult") as Button).pressed.emit()
	eq(_orders, [], "insult asks first (docs/ui/mecanicas/_social.md rule 2)")
	check(SocialKit.accept_pending(panel), "the question waits on the sheet")
	eq(_orders, [{"type": "npc_insult", "actor": HERO, "target": npc}], "insult at once in range")
	sim.state.characters[HERO]["position"] = [2, 19]
	_orders = []
	panel.do_action("flatter")
	eq(str(_orders[0]["type"]), "move_to", "far: walks there first")
	eq([str(_orders[1]["type"]), bool(_orders[1]["queued"])], ["npc_flatter", true], "and the action waits behind")
	panel.free()


func test_microevent_card_shows_and_resolves() -> void:
	var sim := _sim("microevent_card")
	var card: MicroeventCard = (load("res://game/ui/microevent_card.tscn") as PackedScene).instantiate()
	card.order_sink = _sink
	card.follow(sim, HERO)
	check(card.visible, "the card shows the active microevent")
	var txt := _texts(card)
	var emp := str(sim.state.microevents["active"][0]["target"])
	check(txt.contains(str(sim.state.characters[emp]["name"])), "with the sick employee's name (%s)" % txt)
	eq(card.get_node("%Choices").get_child_count(), 3, "three choices")
	_orders = []
	(card.get_node("%Choices").get_child(0) as Button).pressed.emit()
	eq(_orders, [{"type": "resolve_microevent", "actor": HERO, "microevent": str(sim.state.microevents["active"][0]["id"]),
		"choice": "doctor"}], "choosing gives resolve_microevent")
	check(Orders.apply(sim, _orders[0])["ok"], "and the sim takes it")
	card.follow(sim, HERO)
	check(not card.visible, "no microevent: hidden")
	card.free()


func test_interior_shows_the_customer_at_the_counter() -> void:
	var sim := _sim("town_microevents")
	var guard := 0
	while Counter.customers(sim, FORGE).is_empty() and guard < 900:
		sim.run_minutes(5)
		guard += 5
	var who: Array = Counter.customers(sim, FORGE)
	check(not who.is_empty(), "a customer inside")
	var iv: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	iv.setup(sim, FORGE, HERO, true)
	iv.sync()
	var v := iv.view_of(str(who[0]))
	check(v != null, "drawn inside")
	eq(v.bubble_id, "shop", "with the market bubble")
	iv.free()
