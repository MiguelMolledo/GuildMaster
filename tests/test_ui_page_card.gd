extends "res://tests/test_case.gd"
## The page kit (docs/ui/04_kit_de_pagina.md): each template of PageCard creates its nodes; no text of a page lands
## outside the safe area measured on its background; the title's ribbon is mounted on the page's top edge (half of it
## above the parchment) and its text fits the ribbon's cloth; without the kit (or without one piece) the card falls back
## to the pieces of the theme of today; the chosen variants alternate card after card; the event card says the event's
## name, its effects and how long it lasts.

const SCENE := "res://game/ui/page_card.tscn"
const ILL := "res://assets/art/ui/page_kit/piloto/event_war.png"
const ILL_SMALL := "res://assets/art/ui/page_kit/piloto/event_war_192.png"
const FACE := "res://assets/art/ui/page_kit/piloto/portrait_artesana.png"


func _card() -> PageCard:
	PageKit.use_kit(null)
	return (load(SCENE) as PackedScene).instantiate() as PageCard


func _data(template: String) -> Dictionary:
	return {"template": template, "title": "Guerra regional", "image": load(ILL_SMALL if template == "notice" else ILL),
		"portrait": load(FACE), "subtitle": ["Tejedora · oficial · 24 años"],
		"blocks": [
			{"type": "paragraph", "text": "Las tropas del conde cruzan la comarca y cortan los caminos del condado."},
			{"type": "divider"},
			{"type": "effects", "items": [{"text": "Armas: precio ×2", "sign": ""}, {"text": "Muertes ×1,2", "sign": "-"},
				{"text": "Clientes ×1,3", "sign": "+"}, {"text": "Los recados tardan ×1,5", "sign": "-"}]},
			{"type": "quote", "text": "Que Dios guarde los caminos.", "who": "el párroco"},
			{"type": "figures", "items": [{"label": "Dura", "value": "4 estaciones"}]}],
		"footer_figures": [{"label": "", "value": "Dura 4 estaciones"}],
		"seal": {"text": "G"}, "buttons": [{"id": "ok", "text": "Entendido", "primary": true}]}


func _texts(n: Node, out: Array) -> Array:
	if (n is Label or n is Button) and str(n.get("text")) != "":
		out.append(n)
	for c: Node in n.get_children():
		_texts(c, out)
	return out


## The rect of `c` in the coordinates of `card` (the card is not in the tree: positions add up).
func _rect_in(card: Control, c: Control) -> Rect2:
	var p := c.position
	var n := c.get_parent()
	while n != null and n != card:
		if n is Control:
			p += (n as Control).position
		n = n.get_parent()
	return Rect2(p, c.size)


func test_each_template_creates_its_nodes() -> void:
	var want := {"card": ["Illustration", "Ribbon", "RibbonText", "Footer", "Seal", "Button_ok", "Cartouche"],
		"plate": ["Plate", "Illustration", "Ribbon", "TextBand", "Veil", "Frame", "Button_ok"],
		"sheet": ["Top", "Portrait", "Side", "Ribbon", "Footer", "Corner0", "Corner3"],
		"notice": ["Illustration", "Ribbon", "Frame", "Footer"]}
	for t: String in want:
		var c := _card()
		c.build(_data(t))
		for n: String in want[t]:
			check(c.find_child(n, true, false) != null, "%s: has %s" % [t, n])
		check(c.find_child("Block0_paragraph", true, false) != null, "%s: the paragraph block" % t)
		check(c.find_child("Block2_effects", true, false) != null, "%s: the effects block" % t)
		c.free()
	var c2 := _card()
	c2.build(_data("card"))
	var ill := c2.find_child("Illustration", true, false) as TextureRect
	check(ill.material is ShaderMaterial, "the card's illustration is faded with a mask of the kit")
	eq(ill.custom_minimum_size, Vector2(240, 135), "the illustration at ×1")
	c2.free()
	var c3 := _card()
	c3.build(_data("plate"))
	eq((c3.find_child("Plate", true, false) as Control).custom_minimum_size, Vector2(480, 270), "the plate at ×2")
	c3.free()
	var c4 := _card()
	c4.build(_data("sheet"))
	eq((c4.find_child("Portrait", true, false) as Control).custom_minimum_size, Vector2(128, 128), "portrait ×2")
	c4.free()


## Without a window the tests run before the scene tree exists, so no Control gets a size: the check is by
## construction (the smoke script --smoke-script=pagina checks the real rects on screen): every text is inside Body,
## Body's margins are the safe area, no text asks for more width than the column, and Decor (frames, corners) has no
## text.
func test_no_text_outside_the_safe_area() -> void:
	for t: String in ["card", "plate", "sheet", "notice"]:
		var c := _card()
		c.build(_data(t))
		var body := c.find_child("Body", true, false) as MarginContainer
		var decor := c.find_child("Decor", true, false) as Control
		for side: String in ["left", "top", "right", "bottom"]:
			eq(body.get_theme_constant("margin_" + side), int(c.safe[side]), "%s: Body margin %s = safe" % [t, side])
		var texts := _texts(c, [])
		check(texts.size() >= 4, "%s: texts found (%d)" % [t, texts.size()])
		check(c.column_width > 100, "%s: a usable column (%d)" % [t, c.column_width])
		if t != "plate":
			eq(int(c.custom_minimum_size.x) - int(c.safe["left"]) - int(c.safe["right"]), c.column_width,
				"%s: the column is the card minus the safe area" % t)
		var ribbon := c.find_child("Ribbon", true, false) as Control
		for l: Control in texts:
			if ribbon.is_ancestor_of(l):  # the title on the ribbon: on the edge, checked in test_ribbon_on_the_top_edge
				continue
			check(body.is_ancestor_of(l), "%s: «%s» is inside the safe area (Body)" % [t, str(l.get("text")).left(24)])
			check(not decor.is_ancestor_of(l), "%s: no text in the decoration" % t)
			check(l.custom_minimum_size.x <= c.column_width, "%s: «%s» fits the column (%d <= %d)" % [t,
				str(l.get("text")).left(24), int(l.custom_minimum_size.x), c.column_width])
		c.free()
	# the safe area of a card is the one measured on its background (kit.json content_margin)
	var c2 := _card()
	c2.build(_data("card"))
	var file := str(c2.parts.get("page", ""))
	check(file.begins_with("page_bg_"), "the card uses a page background of the kit (%s)" % file)
	for v: Dictionary in PageKit.chosen("page_bg"):
		if str(v["file"]) == file:
			eq(int(c2.safe["left"]), int(v["content_margin"]["left"]), "left margin = the measured one")
			eq(int(c2.safe["top"]), int(v["content_margin"]["top"]), "top margin = the measured one")
	c2.free()


## What `l` (a RibbonText) needs on screen: {w, h} with the font of its variation (no window: no Label sizes).
func _ribbon_text_size(l: Label, width: float) -> Vector2:
	var th := PageKit.theme()
	var font := th.get_font("font", l.theme_type_variation)
	var fs := th.get_font_size("font_size", l.theme_type_variation)
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		return Vector2(font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, font.get_height(fs))
	var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var n := int(roundf(sz.y / font.get_height(fs)))
	return Vector2(sz.x, n * font.get_height(fs) + (n - 1) * th.get_constant("line_spacing", l.theme_type_variation))


## Every template: the ribbon is centred on the page's top edge, part of it above the parchment (about half) and the
## rest over it; the column starts under it (no block under the ribbon); the title fits the ribbon's cloth in width and
## height, in the big gothic letter when it fits. A long title in the narrow notice takes the smaller letter (or two
## lines) and still fits; one that fits nowhere is cut with «…» inside the ribbon.
func test_ribbon_on_the_top_edge() -> void:
	var titles := {"card": "Festividad religiosa", "plate": "Fiesta popular", "sheet": "Agnès Ferrer",
		"notice": "Fiesta popular"}
	for t: String in titles:
		for turn: int in 2:  # both ribbons of the kit
			var c := _card()
			for _i: int in turn:
				PageKit.variant("ribbon")
			var d := _data(t)
			d["title"] = titles[t]
			c.build(d)
			var r := c.find_child("Ribbon", true, false) as PanelContainer
			check(r != null and (c.find_child("Decor", true, false) as Control).is_ancestor_of(r),
				"%s: the ribbon is over the page (Decor)" % t)
			if r == null:
				c.free()
				continue
			var h := r.custom_minimum_size.y
			var w := r.custom_minimum_size.x
			eq(r.anchor_left, 0.5, "%s: centred" % t)
			eq(r.offset_left, -r.offset_right, "%s: centred on the card" % t)
			check(r.offset_top < 0.0, "%s: the ribbon rises above the parchment (top %d)" % [t, int(r.offset_top)])
			check(r.offset_bottom > 0.0, "%s: and is mounted on its edge (bottom %d)" % [t, int(r.offset_bottom)])
			check(-r.offset_top >= h * 0.4 and -r.offset_top <= h * 0.6, "%s: about half outside (%d of %d)" % [t,
				int(-r.offset_top), int(h)])
			eq(c.ribbon_overhang, int(-r.offset_top), "%s: ribbon_overhang says how much" % t)
			check(w <= float(c.custom_minimum_size.x if t != "plate" else 516) - 24.0, "%s: narrower than the card" % t)
			if t != "plate":
				check(int(c.safe["top"]) >= int(r.offset_bottom) + PageCard.RIBBON_GAP,
					"%s: the column starts under the ribbon (top %d, ribbon to %d)" % [t, int(c.safe["top"]),
					int(r.offset_bottom)])
			var l := r.get_node("RibbonText") as Label
			eq(l.text, titles[t], "%s: the title on the ribbon" % t)
			eq(l.theme_type_variation, &"PageRibbon", "%s: «%s» in the big letter" % [t, titles[t]])
			var st := r.get_theme_stylebox("panel") as StyleBoxTexture
			var cloth := Vector2(w - st.content_margin_left - st.content_margin_right,
				h - st.content_margin_top - st.content_margin_bottom)
			var need := _ribbon_text_size(l, cloth.x)
			check(need.x <= cloth.x and need.y <= cloth.y, "%s (%s): the text %s fits the cloth %s" % [t,
				c.parts.get("ribbon", ""), need, cloth])
			c.free()
	# a long title in the notice: a smaller letter, and still inside the cloth
	for title: String in ["Familia, cortejo y herencia · 12/14", "Oficio: carpintero · 10/12",
			"Una crónica larguísima que no cabe de ninguna manera en una cinta tan corta como esta"]:
		var c := _card()
		var d := _data("notice")
		d["ribbon"] = title
		c.build(d)
		var r := c.find_child("Ribbon", true, false) as PanelContainer
		var l := r.get_node("RibbonText") as Label
		var st := r.get_theme_stylebox("panel") as StyleBoxTexture
		var cloth := Vector2(r.custom_minimum_size.x - st.content_margin_left - st.content_margin_right,
			r.custom_minimum_size.y - st.content_margin_top - st.content_margin_bottom)
		check(r.custom_minimum_size.x <= 236.0 - 24.0, "notice: «%s» on a ribbon inside the notice" % title.left(20))
		eq(l.theme_type_variation, &"PageRibbonSmall", "notice: «%s» in the smaller letter" % title.left(20))
		if l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var need := _ribbon_text_size(l, l.custom_minimum_size.x if l.custom_minimum_size.x > 0 else cloth.x)
			check(need.x <= cloth.x and need.y <= cloth.y, "notice: «%s» %s fits the cloth %s" % [title.left(20), need,
				cloth])
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF:  # a wrapped label asks for all its lines (else it shows none)
				check(not l.clip_text and l.custom_minimum_size.y >= need.y, "notice: «%s» asks for its %d px of lines" % [
					title.left(20), int(need.y)])
		else:
			check(title.length() > 60, "only a title that fits nowhere is cut («%s»)" % title.left(20))
			check(l.clip_text, "the cut title does not leave the ribbon")
		c.free()


func test_missing_pieces_fall_back_to_the_theme() -> void:
	var c := _card()
	PageKit.use_kit({})
	c.build(_data("card"))
	eq(str(c.parts.get("page", "x")), "", "no kit: no page background of the kit")
	var sb := c.get_theme_stylebox("panel") as StyleBoxTexture
	var parch := PageKit.theme().get_stylebox("panel", "ParchmentPanel") as StyleBoxTexture
	check(sb != null and parch != null and sb.texture == parch.texture, "no kit: the parchment of the theme")
	var rib := c.find_child("Ribbon", true, false)
	check(rib is Label and (rib as Label).theme_type_variation == &"InkTitleLabel", "no ribbon: the title in ink")
	check(c.find_child("Block1_divider", true, false) is HSeparator, "no divider: the theme's DividerSeparator")
	check((c.find_child("Illustration", true, false) as TextureRect).material == null, "no mask: the image as is")
	eq(int(c.safe["left"]), 8, "no kit: the parchment's padding")
	c.free()
	# one piece missing: only that one falls back
	PageKit.use_kit(null)
	var k := PageKit.kit().duplicate(true)
	(k["slots"] as Dictionary).erase("ribbon")
	PageKit.use_kit(k)
	var c2 := (load(SCENE) as PackedScene).instantiate() as PageCard
	c2.build(_data("card"))
	check(str(c2.parts.get("page", "")) != "", "without the ribbon the page of the kit is still there")
	eq(str(c2.parts.get("ribbon", "x")), "", "without the ribbon: fallback for it")
	c2.free()
	# a file that does not load counts as missing
	var k2 := PageKit.kit().duplicate(true)
	k2["slots"]["page_bg"] = {"variants": [{"file": "no_such_file.png"}], "chosen": ["no_such_file.png"]}
	PageKit.use_kit(k2)
	check(not PageKit.has("page_bg"), "a chosen file that does not exist is missing")
	PageKit.use_kit(null)


func test_variants_alternate() -> void:
	PageKit.use_kit(null)
	var pages: Array = []
	var ribbons: Array = []
	for i: int in 2:
		var c := (load(SCENE) as PackedScene).instantiate() as PageCard
		c.build(_data("card"))
		pages.append(c.parts.get("page", ""))
		ribbons.append(c.parts.get("ribbon", ""))
		c.free()
	if PageKit.chosen("page_bg").size() >= 2:
		check(pages[0] != pages[1], "two cards in a row: two page backgrounds (%s)" % [pages])
	if PageKit.chosen("ribbon").size() >= 2:
		check(ribbons[0] != ribbons[1], "two cards in a row: two ribbons (%s)" % [ribbons])
	PageKit.reset_turns()
	var a := PageKit.variant("mask_side")
	var b := PageKit.variant("mask_side")
	PageKit.reset_turns()
	eq(PageKit.variant("mask_side"), a, "after reset the rotation starts again")
	if PageKit.chosen("mask_side").size() >= 2:
		check(a != b, "the masks alternate image after image")


func test_event_page_data() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var r := NewGame.from_scenario("season_events", 1)
	check(bool(r["ok"]), "season_events loads")
	var sim := Sim.new(r["state"], Catalog.load_from())
	var now := int(sim.state.clock["minute"])
	var dps := int(sim.catalog.time.get("days_per_season", 2))
	var e := {"type": "world_event_started", "def": "war", "start": now, "end": now + 4 * dps * 1440, "by": ""}
	var d := EventPage.data_for(sim, e)
	eq(str(d["title"]), "Guerra regional", "the event's name on the ribbon")
	check(d["image"] is Texture2D, "the war has its illustration")
	var fx: Array = []
	for b: Dictionary in d["blocks"]:
		if str(b["type"]) == "effects":
			fx = b["items"]
	eq(fx.size(), 4, "the four effects of the war")
	eq(str(fx[0]["text"]), "Armas: precio ×1.5", "price of weapons")
	eq(str(fx[3]["sign"]), "-", "slower errands hurt")
	eq(str(d["footer_figures"][0]["value"]), "Dura 4 estaciones", "how long it lasts")
	eq(str(d["buttons"][0]["text"]), "Entendido", "the button")
	var c := (load("res://game/ui/event_card.tscn") as PackedScene).instantiate() as EventCard
	c.show_for(sim, e)
	check(c.visible, "the event card shows")
	c.show_for(sim, {"type": "world_event_started", "def": "festival", "start": now, "end": now + 1440, "by": ""})
	eq(c.shown, ["war"], "a second event waits behind the first")
	c.close()
	eq(c.shown, ["war", "festival"], "closing the first shows the next")
	c.free()
	TranslationServer.set_locale(before)
