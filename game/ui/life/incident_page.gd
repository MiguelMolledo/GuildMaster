class_name IncidentPage
extends RefCounted
## The page of an incident with a card for the player's family (docs/gdd/04f_vida_y_fiestas.md §4.24.5, principle 5:
## its card, its notice and its chronicle): the data for PageCard. The illustration (VisualPaths.illustration
## "events" by the incident's id: VisualPaths.EVENT_ILLUSTRATION_ALIAS gives the art's name; a visible greybox with its label while the art is missing), what happens, the figures
## (the band, the ransom) and one button per choice the card offers, the one it takes by default marked, a choice the
## family cannot take now off with the reason (Incidents.choice_block). Presentation only.

const SIZE: Vector2i = Vector2i(240, 135)


static func data_for(sim: Sim, inc: Dictionary, actor: String) -> Dictionary:
	var st := sim.state
	var def := str(inc.get("def", ""))
	var p := text_params(sim, inc)
	var blocks: Array = []
	var img := VisualPaths.illustration("events", def)
	if img == null:
		img = greybox()
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.life.art_missing") % def})
	blocks.append({"type": "paragraph", "text": SimQuery.t_("incident.%s.story" % def).format(p)})
	var figs: Array = []
	if def == "bandit_raid":
		figs.append({"label": SimQuery.t_("ui.incident.band"), "value": str(p.get("band", 0))})
	if def == "kidnapping":
		figs.append({"label": SimQuery.t_("ui.incident.ransom"), "value": str(int(inc.get("ransom", 0)))})
	var card: Dictionary = inc.get("card", {})
	var buttons: Array = []
	var dflt := str(card.get("default", ""))
	for c: Variant in card.get("choices", []):
		var id := str(c)
		var why := Incidents.choice_block(sim, inc, id, actor, {"helpers": 2})
		var tp := p.duplicate()
		tp["n"] = 2
		tp["cost"] = Incidents.helper_cost(sim, inc, 2)
		buttons.append({"id": id, "text": SimQuery.t_("incident.choice." + id), "primary": id == dflt,
			"disabled": why != "", "tip": SimQuery.reason_text(why) if why != "" else SimQuery.t_("incident.choice.%s.tip" % id).format(tp)})
	if def == "altercation" and str(inc.get("phase", "")) == "gathering" and not actor in (inc.get("people", []) as Array):
		# juegos (04f §4.26.6): bet on the brawl before they come to blows (the bookmaker, GameScreen)
		buttons.append({"id": "bet", "text": SimQuery.t_("incident.choice.bet"), "primary": false,
			"tip": SimQuery.t_("incident.choice.bet.tip")})
	buttons.append({"id": "later", "text": SimQuery.t_("ui.incident.close"), "primary": false})
	if dflt != "":
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.incident.default") % SimQuery.t_("incident.choice." + dflt)})
	return {"template": "card", "title": SimQuery.t_("incident." + def), "image": img, "blocks": blocks,
		"footer_figures": figs, "buttons": buttons, "sticky": true, "incident": str(inc.get("id", "")), "def": def}


## The params of the incident's texts, translated (names, the nest, the building).
static func text_params(sim: Sim, inc: Dictionary) -> Dictionary:
	var p := Incidents.params(sim, inc)
	p["place"] = SimQuery.t_(str(p.get("place", "nest.road")))
	var bld := str(p.get("building", ""))
	if bld != "" and sim.state.buildings.has(bld):
		p["building"] = SimQuery.building_label(sim.state, sim.catalog, bld)
	return p


## A visible stand-in for a missing illustration: a framed, cross-hatched plate (its label goes in the text).
static func greybox() -> Texture2D:
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.42, 0.36, 0.3, 1.0))
	for y: int in SIZE.y:
		for x: int in SIZE.x:
			if (x + y) % 12 == 0 or (x - y + 1200) % 12 == 0:
				img.set_pixel(x, y, Color(0.52, 0.45, 0.37, 1.0))
			if x < 2 or y < 2 or x >= SIZE.x - 2 or y >= SIZE.y - 2:
				img.set_pixel(x, y, Color(0.2, 0.16, 0.12, 1.0))
	return ImageTexture.create_from_image(img)
