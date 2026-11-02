class_name TitleCard
extends PanelContainer
## The title ceremony (GDD 4.12.2, H9): when the player's family gets a title at the town hall (title_granted), a
## card in the middle of the screen with the family's colours as a banner, who received it, the new title and what it
## opens. A click (or the button) closes it; it also closes by itself after `seconds` real seconds
## (data/view.json "title_card_seconds"). Reads only; gives no orders.

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
	(%TitleName as Label).text = SimQuery.title_name(title).to_upper()
	(%Text as Label).text = SimQuery.t_("ui.title_card.text") % [str(st.characters.get(str(e.get("actor", "")), {}).get(
		"name", "")), str(f.get("name", "")), SimQuery.title_name(title)]
	(%Unlocks as Label).text = SimQuery.t_("ui.town_hall.unlocks") % TownHallPanel.unlocks_text(sim.catalog, title)
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
