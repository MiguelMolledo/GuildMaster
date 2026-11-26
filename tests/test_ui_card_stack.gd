extends "res://tests/test_case.gd"
## The cards of the town (verificación A1-A2): a card in CardsLayer that does not pause goes small to the side stack
## (notice template, no illustration), the next one under it, never on top; a modal card is centred and a second
## modal waits until the first closes; the compact page keeps the first paragraph, the effects and the buttons.

const SCENE := "res://game/ui/page_card.tscn"


func _layer() -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = "CardsLayer"
	return l


func _card(layer: CanvasLayer) -> PageCard:
	var c := (load(SCENE) as PackedScene).instantiate() as PageCard
	layer.add_child(c)
	return c


func _data(title: String, modal: bool = false) -> Dictionary:
	return {"template": "card", "title": title, "modal": modal,
		"image": load("res://assets/art/ui/page_kit/piloto/event_war.png"),
		"blocks": [{"type": "paragraph", "text": "Primero."}, {"type": "divider"},
			{"type": "effects", "items": [{"text": "Precio ×2", "sign": ""}]}, {"type": "paragraph", "text": "Segundo."}],
		"buttons": [{"id": "ok", "text": "Entendido", "primary": true}]}


func test_compact_keeps_words_and_buttons() -> void:
	var c := PageCard.compact(_data("Guerra"))
	eq(str(c["template"]), "notice", "small template")
	check(not c.has("image"), "no illustration")
	eq((c["blocks"] as Array).size(), 2, "first paragraph and effects")
	eq((c["buttons"] as Array).size(), 1, "the buttons stay")
	eq((PageCard.compact(_data("Guerra"), true)["blocks"] as Array).size(), 1, "bare: only the first paragraph")


func test_town_cards_stack_without_overlap() -> void:
	PageCard._stack.clear()
	PageCard._waiting.clear()
	var layer := _layer()
	var a := _card(layer)
	var b := _card(layer)
	a.show_page(_data("Uno"))
	b.show_page(_data("Dos"))
	check(a.docked and b.docked, "both docked")
	eq(PageCard.stack().size(), 2, "two in the stack")
	check(b.position.y >= a.position.y + a.size.y, "the second under the first (%s, %s+%s)" % [b.position, a.position, a.size])
	check(a.position.x + a.size.x <= 957.0, "inside the screen on the right")
	a.close()
	eq(PageCard.stack().size(), 1, "one left")
	layer.free()
	PageCard._stack.clear()


func test_a_second_modal_waits() -> void:
	PageCard._stack.clear()
	PageCard._waiting.clear()
	PageCard._modal = null
	var layer := _layer()
	var a := _card(layer)
	var b := _card(layer)
	a.show_page(_data("Uno", true))
	b.show_page(_data("Dos", true))
	check(a.visible and not a.docked, "the first modal shows, centred")
	check(not b.visible, "the second waits")
	a.close()
	check(b.visible, "it shows when the first closes")
	layer.free()
	PageCard._modal = null
	PageCard._waiting.clear()


func test_a_new_game_clears_the_cards_of_the_game_before() -> void:
	PageCard._stack.clear()
	PageCard._waiting.clear()
	PageCard._modal = null
	var layer := _layer()
	var a := _card(layer)
	var b := _card(layer)
	var m := _card(layer)
	var w := _card(layer)
	a.show_page(_data("Uno"))
	b.show_page(_data("Dos"))
	m.show_page(_data("Tres", true))
	PageCard._waiting.append([w, _data("Cuatro")])
	for c: PageCard in [a, b, m, w]:   # what Game.started does to every card of the town
		c._on_game_started()
	check(not a.visible and not b.visible and not m.visible and not w.visible, "no card of the game before shows")
	eq(PageCard.stack().size(), 0, "the stack is empty")
	eq(PageCard._waiting.size(), 0, "nothing waits")
	var d := _card(layer)
	d.show_page(_data("Retar a Bernat"))
	check(d.visible and d.docked, "the new game's card shows at once (flow duelo, pelea_carta)")
	layer.free()
	PageCard._stack.clear()
	PageCard._waiting.clear()
	PageCard._modal = null
