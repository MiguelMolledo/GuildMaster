class_name TitleCard
extends PanelContainer
## The title ceremony (GDD 4.12.2, H9; docs/ui/mecanicas/titulos_y_reputacion.md §3): when the player's family gets a
## title at the town hall (title_granted), a card in the middle of the screen with the family's colours as two
## banners, the sealing-wax seal with the title's initial, the new title in large gothic, who received it, what it
## opens, and the ladder of titles with the new step lit. A click (or the button) closes it; it also closes by itself
## after `seconds` real seconds (data/view.json "title_card_seconds"). Reads only; gives no orders.

var _left: float = 0.0


func _ready() -> void:
	(%OkButton as Button).pressed.connect(close)
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())


## Shows the card for title_granted event `e` of `sim`.
func show_for(sim: Sim, e: Dictionary) -> void:
	var st := sim.state
	var fam := str(e.get("family", ""))
	var f: Dictionary = st.families.get(fam, {})
	var title := str(e.get("title", ""))
	(%Header as Label).text = SimQuery.t_("ui.title_card.header")
	(%Banner as ColorRect).color = ViewConfig.color(str(f.get("colors", {}).get("primary", "#808080")))
	(%BannerStripe as ColorRect).color = ViewConfig.color(str(f.get("colors", {}).get("secondary", "#c8a84e")))
	var tn0 := SimQuery.title_name(title)
	(%TitleName as Label).text = tn0.substr(0, 1).to_upper() + tn0.substr(1)  # gothic: capitals only at the start
	(%Text as Label).text = SimQuery.t_("ui.title_card.text") % [str(st.characters.get(str(e.get("actor", "")), {}).get(
		"name", "")), str(f.get("name", "")), SimQuery.title_name(title)]
	(%Unlocks as Label).text = SimQuery.t_("ui.town_hall.unlocks") % TownHallPanel.unlocks_text(sim.catalog, title,
		str(e.get("from", "")))
	(%BannerRight as ColorRect).color = (%Banner as ColorRect).color
	(%Initial as Label).text = SimQuery.title_name(title).substr(0, 1).to_upper()
	var box := %Ladder as HBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var ladder := sim.catalog.title_ladder()
	for i: int in ladder.size():
		var t := str(ladder[i])
		if i > 0:
			box.add_child(SocialKit.label("—", &"DimLabel"))
		var tn := SimQuery.title_name(t)
		var l := SocialKit.label(tn.substr(0, 1).to_upper() + tn.substr(1), &"GoldLabel" if t == title else &"DimLabel", t)
		if t == title:
			l.text = "[%s]" % l.text.to_upper()
		box.add_child(l)
	(%OkButton as Button).text = SimQuery.t_("ui.title_card.ok")
	visible = true
	_left = float(ViewConfig.value("title_card_seconds", 8.0))
	reset_size()
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) / 2.0).round()
	ViewConfig.info("TitleCard", "ceremony: %s -> %s (actor=%s)" % [fam, title, e.get("actor", "")])


func close() -> void:
	visible = false
	_left = 0.0


func _process(delta: float) -> void:
	if visible and _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()
