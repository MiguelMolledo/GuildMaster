class_name MicroeventCard
extends PanelContainer
## The card of a microevent of the player's family (H7, GDD 4.20; top left, under the group): not blocking, the time keeps running. Its text,
## one button per choice and the time left before the default choice applies (marked with «·»). Choosing gives
## resolve_microevent (a management order: it applies at once, also in pause). Shows the oldest active one; hidden
## when there is none. Only reads Microevents.active_for / view and gives orders (order_sink).

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # who decides: the selected person if of the family, else the head
var shown_id: String = ""


func follow(s: Sim, who: String) -> void:
	sim = s
	var fam := SimQuery.player_family(s.state)
	actor = SimQuery.family_actor(s.state, fam, who)
	var act := Microevents.active_for(s, fam) if fam != "" else []
	visible = not act.is_empty()
	if not visible:
		shown_id = ""
		return
	var v := Microevents.view(s, str(act[0]["id"]))
	if str(v["id"]) != shown_id:
		shown_id = str(v["id"])
		_build(v)
	var def_text := ""
	for c: Dictionary in v["choices"]:
		if str(c["id"]) == str(v["default"]):
			def_text = SimQuery.t_(str(c["text_key"]))
	(%Time as Label).text = SimQuery.t_("ui.microevent.time") % [SimQuery.minutes_left_label(int(v["minutes_left"])),
		def_text]
	(%More as Label).visible = act.size() > 1
	(%More as Label).text = SimQuery.t_("ui.microevent.more") % (act.size() - 1)


func _build(v: Dictionary) -> void:
	(%Title as Label).text = SimQuery.t_("ui.microevent.title")
	(%Text as Label).text = SimQuery.microevent_text(sim, v)
	var box := %Choices as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for c: Dictionary in v["choices"]:
		var b := Button.new()
		b.name = str(c["id"]).capitalize()
		b.text = ("· " if str(c["id"]) == str(v["default"]) else "") + SimQuery.t_(str(c["text_key"]))
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(288, 0)
		var choice := str(c["id"])
		b.pressed.connect(func() -> void: choose(choice))
		box.add_child(b)
	reset_size()


func choose(choice: String) -> void:
	if shown_id == "" or actor == "":
		return
	var o := {"type": "resolve_microevent", "actor": actor, "microevent": shown_id, "choice": choice}
	ViewConfig.info("MicroeventCard", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	shown_id = ""
