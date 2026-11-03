class_name EventPage
extends RefCounted
## The page of a global event that starts (H13, GDD 4.13; docs/ui/04_kit_de_pagina.md §4): the data for PageCard from
## a world_event_started event of the sim. The illustration of the event on top (VisualPaths.illustration), its name
## on the ribbon, a sentence of what happens, each effect of data/events.json in one line (its direction says if it
## helps or hurts, never the colour alone), how long it lasts and «Entendido». Who declared it, if the mayor did.
## Presentation only: the figures are the event's own (data/events.json), nothing is computed here.


## The PageCard data of world_event_started event `e` ({} if the event is unknown).
static func data_for(sim: Sim, e: Dictionary) -> Dictionary:
	var id := str(e.get("def", ""))
	var def: Dictionary = sim.catalog.world_events().get(id, {})
	if def.is_empty():
		return {}
	var key := str(def.get("text_key", "event." + id))
	var blocks: Array = []
	var story := SimQuery.t_(key + ".story")
	blocks.append({"type": "paragraph", "text": story if story != key + ".story" else SimQuery.t_(key + ".desc")})
	var by := str(e.get("by", ""))
	if by != "" and sim.state.characters.has(by):
		blocks.append({"type": "paragraph", "text": SimQuery.t_("ui.event_card.declared") % str(
			sim.state.characters[by].get("name", ""))})
	var effects: Array = []
	for fx: Dictionary in def.get("effects", []):
		effects.append(effect_line(fx))
	if not effects.is_empty():
		blocks.append({"type": "effects", "items": effects})
	return {"template": "card", "title": SimQuery.t_(key), "image": VisualPaths.illustration("events", id),
		"blocks": blocks, "footer_figures": [{"label": "", "value": lasts_text(sim, def, e)}],
		"buttons": [{"id": "ok", "text": SimQuery.t_("ui.event_card.ok"), "primary": true}],
		"seconds": float(ViewConfig.value("event_card_seconds", 12.0)), "event": id}


## One effect of data/events.json as {text, sign}: «Armas: precio ×2». sign "+" helps, "-" hurts, "" depends on
## whether one buys or sells (prices, demand).
static func effect_line(fx: Dictionary) -> Dictionary:
	var kind := str(fx.get("kind", ""))
	var m := float(fx.get("mult", 1.0))
	var num := SimQuery._num(m)
	var group := SimQuery.t_("goods." + str(fx.get("group", "")))
	group = group.substr(0, 1).to_upper() + group.substr(1)
	var sign := ""
	match kind:
		"production", "customers":
			sign = "+" if m > 1.0 else "-"
		"errands", "mortality":
			sign = "-" if m > 1.0 else "+"
	var text := SimQuery.t_("ui.event_card.fx_" + kind)
	text = text % [group, num] if kind in ["price", "demand", "production"] else text % num
	return {"text": text, "sign": sign}


## «Dura 4 estaciones» / «Dura 3 días» from the event's start and end.
static func lasts_text(sim: Sim, def: Dictionary, e: Dictionary) -> String:
	var days := maxi(1, ceili(float(int(e.get("end", 0)) - int(e.get("start", 0))) / float(Clock.MINUTES_PER_DAY)))
	if str(def.get("scope", "")) == "season":
		var n := maxi(1, roundi(float(days) / float(WorldEvents._days_per_season(sim))))
		return SimQuery.t_("ui.event_card.lasts_season" if n == 1 else "ui.event_card.lasts_seasons") % n
	return SimQuery.t_("ui.event_card.lasts_day" if days == 1 else "ui.event_card.lasts_days") % days
