extends Node
## Scripted capture of the page kit (--smoke-script=pagina; docs/ui/04_kit_de_pagina.md; run it through `grimoire
## heavy` with the engine's --always-on-top). season_events at 23:50: the game runs past midnight and the next day's
## roll starts an event; its card shows by itself (kit_pagina_evento). Then the war's card (kit_pagina_guerra), and the
## other templates of PageCard over the same town: the notice (kit_pagina_aviso), the sheet (kit_pagina_ficha) and the
## plate (kit_pagina_lamina), and the wedding card on the kit (kit_pagina_boda). Every shot checks on screen that no
## text of the page leaves its safe area and that the title's ribbon sits on the page's top edge with its text on the
## cloth, and prints the count. Quits when done (1 if a text is outside), or after `timeout` seconds.

const SCENARIO: String = "season_events"
const DAY: int = 1440
const PILOT: String = "res://assets/art/ui/page_kit/piloto/"

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0
var _demo: PageCard = null
var _seen: float = -1.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokePagina] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokePagina] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _event_card() -> EventCard:
	return app.get_node("%EventCard") as EventCard


## Every Label and Button of `card` inside its safe area, on screen (global rects).
func _check(card: PageCard, shot: String) -> void:
	var r := card.get_global_rect()
	var s := card.safe
	var safe := Rect2(r.position + Vector2(float(s["left"]), float(s["top"])),
		r.size - Vector2(float(s["left"]) + float(s["right"]), float(s["top"]) + float(s["bottom"])))
	var n := 0
	var out := 0
	var ribbon := card.get_node("%Decor").get_node_or_null("Ribbon") as Control
	if ribbon is PanelContainer:  # the title's ribbon on the top edge: above the parchment, its text on the cloth
		var rr := ribbon.get_global_rect()
		var st := ribbon.get_theme_stylebox("panel")
		var cloth := Rect2(rr.position + Vector2(st.content_margin_left, st.content_margin_top), rr.size - Vector2(
			st.content_margin_left + st.content_margin_right, st.content_margin_top + st.content_margin_bottom))
		var lt := ribbon.get_node("RibbonText") as Label
		var tw := lt.get_theme_font("font").get_string_size(lt.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			lt.get_theme_font_size("font_size")).x
		var on_edge := rr.position.y < r.position.y and rr.end.y > r.position.y
		var fits := cloth.grow(0.5).encloses(lt.get_global_rect()) and (tw <= cloth.size.x + 0.5 or
			lt.autowrap_mode != TextServer.AUTOWRAP_OFF)
		if not on_edge or not fits:
			out += 1
		print("[SmokePagina] %s: cinta %s sobre el borde=%s (sobresale %d), texto «%s» %s ancho %d en el paño %s: %s" % [
			shot, rr, on_edge, int(r.position.y - rr.position.y), lt.text, lt.theme_type_variation, int(tw), cloth,
			"cabe" if fits else "NO CABE"])
	var stack: Array = [card]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		stack.append_array(x.get_children())
		if ribbon is PanelContainer and ribbon.is_ancestor_of(x):
			continue
		if (x is Label or x is Button) and (x as Control).is_visible_in_tree() and str(x.get("text")) != "":
			n += 1
			var g := (x as Control).get_global_rect()
			if not safe.grow(0.5).encloses(g):
				out += 1
				print("[SmokePagina] %s: «%s» %s fuera de la zona segura %s" % [shot, str(x.get("text")).left(30), g, safe])
	_bad += out
	print("[SmokePagina] %s: %d textos, %d fuera de la zona segura (carta %s, zona %s, piezas %s)" % [shot, n, out, r,
		safe, card.parts])


func _shot(card: PageCard, name: String) -> void:
	_check(card, name)
	app.save_shot(name)


func _demo_card() -> PageCard:
	if _demo == null:
		_demo = (load("res://game/ui/page_card.tscn") as PackedScene).instantiate() as PageCard
		app.get_node("CardsLayer").add_child(_demo)
	return _demo


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokePagina] TIMEOUT in step %s" % _step)
		app.save_shot("kit_pagina_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario(SCENARIO)
				app.hud().close_panels()
				Game.start(r["state"], Game.sim.catalog)
				Game.set_paused(false)
				_go("midnight")
		"midnight":
			if _event_card().visible and _seen < 0.0:
				_seen = _total
			if _event_card().visible and _total - _seen > 0.6:
				Game.set_paused(true)
				print("[SmokePagina] carta de evento: %s" % [_event_card().shown])
				_shot(_event_card(), "kit_pagina_evento")
				_event_card().close()
				var now := int(Game.sim.state.clock["minute"])
				_event_card().show_for(Game.sim, {"type": "world_event_started", "def": "war", "start": now,
					"end": now + 8 * DAY, "by": ""})
				_go("war")
			elif int(Game.sim.state.clock["minute"]) > 7 * DAY + 120:
				print("[SmokePagina] no event card after midnight")
				app.save_shot("kit_pagina_sin_carta")
				_go("war_only")
		"war_only":
			Game.set_paused(true)
			var now := int(Game.sim.state.clock["minute"])
			_event_card().show_for(Game.sim, {"type": "world_event_started", "def": "war", "start": now,
				"end": now + 8 * DAY, "by": ""})
			_go("war")
		"war":
			if _t > 0.5:
				_shot(_event_card(), "kit_pagina_guerra")
				_event_card().close()
				_demo_card().show_page({"template": "notice", "title": "Fiesta popular",
					"image": load(PILOT + "event_festival_192.png"),
					"blocks": [{"type": "paragraph", "text": "Música y puestos en la plaza: más clientes."}],
					"buttons": [{"id": "ok", "text": "Entendido", "primary": true}]})
				_demo.position = Vector2(4, 404 - _demo.size.y + 132).round()
				_go("notice")
		"notice":
			if _t > 0.5:
				_shot(_demo, "kit_pagina_aviso")
				_demo.close()
				_demo_card().show_page({"template": "sheet", "title": "Agnès Ferrer",
					"portrait": load(PILOT + "portrait_artesana.png"),
					"subtitle": ["Tejedora · oficial · 24 años", "Familia Ferrer"],
					"blocks": [{"type": "divider"},
						{"type": "paragraph", "text": "Relación con Hugo: Cordial (+32). Le gustan los regalos de tela."},
						{"type": "effects", "items": [{"text": "Agradecida (hacia los Herrero)", "sign": "+"},
							{"text": "Celosa (hacia los Ferrer)", "sign": "-"}]},
						{"type": "quote", "text": "Mi telar no para ni en fiestas.", "who": "Agnès"},
						{"type": "figures", "items": [{"label": "Oficio", "value": "3"}, {"label": "Carisma", "value": "5"}]}],
					"buttons": [{"id": "talk", "text": "Conversar", "primary": true}, {"id": "close", "text": "Cerrar"}]})
				_demo.position = Vector2(600, 58)
				_go("sheet")
		"sheet":
			if _t > 0.5:
				_shot(_demo, "kit_pagina_ficha")
				_demo.close()
				_demo_card().show_page({"template": "plate", "title": "Fiesta popular",
					"image": load(PILOT + "event_festival.png"),
					"blocks": [{"type": "paragraph", "text": "Música, puestos y baile en la plaza: el pueblo está en la calle y gasta."}],
					"buttons": [{"id": "ok", "text": "¡Viva la fiesta!", "primary": true}]})
				_go("plate")
		"plate":
			if _t > 0.5:
				_shot(_demo, "kit_pagina_lamina")
				_demo.close()
				var st: WorldState = Game.sim.state
				var fam := SimQuery.player_family(st)
				var hero := SimQuery.family_actor(st, fam)
				var other := ""
				for id: String in st.characters:
					if str(st.characters[id].get("family", "")) != fam and bool(st.characters[id].get("female", false)):
						other = id
						break
				var wed := app.get_node("%WeddingCard") as WeddingCard
				wed.show_for(Game.sim, {"type": "wedding", "character": hero, "spouse": other, "family": fam,
					"from_family": str(st.characters.get(other, {}).get("family", ""))})
				_go("wedding")
		"wedding":
			if _t > 0.5:
				var wed := app.get_node("%WeddingCard") as WeddingCard
				_shot(wed, "kit_pagina_boda")
				wed.close()
				_go("done")
				print("[SmokePagina] done: %d textos fuera de la zona segura" % _bad)
				get_tree().quit(1 if _bad > 0 else 0)
