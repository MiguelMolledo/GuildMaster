class_name EventCard
extends PageCard
## The card of a global event (H13; docs/ui/04_kit_de_pagina.md §4): when an event starts (world_event_started, from
## the roll or declared by the mayor), a PageCard «Carta» with its illustration, name, effects and how long it lasts.
## It does not pause; «Entendido», a click on the button or view.json event_card_seconds close it. One at a time: if
## another starts while one is shown, it waits (docs/ui/mecanicas/_social.md). The notice of zone 7 still shows and
## stays in the book. Listens to Events itself (like WeddingCard); reads only, gives no orders.

var shown: Array = []      # the event ids shown (tests, smoke)
var _queue: Array = []


func _ready() -> void:
	super._ready()
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("step_done", func(events: Array) -> void:
			var g := get_node_or_null("/root/Game")
			if g == null or g.get("sim") == null:
				return
			for e: Dictionary in events:
				if str(e.get("type", "")) == "world_event_started":
					show_for(g.get("sim") as Sim, e))


## Shows the card of world_event_started event `e` (or queues it behind the one on screen).
func show_for(sim: Sim, e: Dictionary) -> void:
	var d := EventPage.data_for(sim, e)
	if d.is_empty():
		return
	if visible:
		_queue.append(d)
		return
	shown.append(str(d.get("event", "")))
	show_page(d)


func close() -> void:
	var was := visible
	super.close()
	if was:
		_next()


func _next() -> void:
	if _queue.is_empty():
		return
	var d: Dictionary = _queue.pop_front()
	shown.append(str(d.get("event", "")))
	show_page(d)
