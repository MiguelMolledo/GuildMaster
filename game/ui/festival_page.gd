class_name FestivalPage
extends RefCounted
## The card of a festival (04f 4.25.3 «La carta de la fiesta»; docs/ui/04_kit_de_pagina.md §4): the data for PageCard
## from a festival_eve (the town crier: «Pregón», tomorrow) or festival_started event of the sim, and the card of the
## player's wedding offer (festival_wedding_offer). The illustration of the feast (VisualPaths.illustration_or_greybox:
## a labelled greybox until the art arrives), its name on the ribbon, what it is, what changes today (each effect in
## plain words; its direction says if it helps or hurts), the contracts it brings, the day's schedule and who pays.
## Buttons: «Entendido», and on the crier the parts the family may still sponsor (festival_sponsor); on the wedding
## offer, pay the banquet (festival_host_wedding). Presentation only: the figures are the data's (data/festivals.json).


## The PageCard data of event `e` for the human family `fam` ({} if it is not a festival event or is unknown).
static func data_for(sim: Sim, e: Dictionary, fam: String = "") -> Dictionary:
	match str(e.get("type", "")):
		"festival_eve", "festival_started":
			return _feast(sim, e, fam)
		"festival_wedding_offer":
			return _wedding(sim, e)
	return {}


static func _feast(sim: Sim, e: Dictionary, fam: String) -> Dictionary:
	var id := str(e.get("def", ""))
	var def := Festivals.def_of(sim, id)
	if def.is_empty():
		return {}
	var inst := Festivals.find(sim, str(e.get("id", "")))
	var eve := str(e.get("type", "")) == "festival_eve"
	var blocks: Array = []
	var when := (SimQuery.t_("ui.festival_card.tomorrow") if eve else SimQuery.t_("ui.festival_card.today")) % (
		"%02d:00" % (int(def.get("start_hour", 0)) % 24))
	blocks.append({"type": "paragraph", "text": SimQuery.t_("festival.%s.story" % id)})
	var fx: Array = []
	for f: Dictionary in def.get("effects", []):
		if not inst.is_empty() and not Festivals._part_ok(inst, f):
			continue
		if str(f.get("kind", "")) in ["spectacle", "emotion"]:
			continue  # the schedule tells the spectacles; the gratitude goes with the sponsors' line
		var line := effect_line(sim, f)
		if not line.is_empty() and fx.size() < 6:
			fx.append(line)
	if not fx.is_empty():
		blocks.append({"type": "effects", "items": fx})
	var sched: Array = []
	for s: Dictionary in def.get("schedule", []):
		if not inst.is_empty() and not Festivals._part_ok(inst, s):
			continue
		sched.append(SimQuery.t_("ui.festival_card.line") % ["%02d:00" % (int(s.get("hour", 0)) % 24),
			SimQuery.t_("festival.what." + str(s.get("what", "")))])
	if not sched.is_empty():
		blocks.append({"type": "divider"})
		blocks.append({"type": "paragraph", "text": " · ".join(sched)})
	var n := FestivalContracts.open_of(sim, inst).size() if not inst.is_empty() else int(e.get("contracts", 0))
	var tail := SimQuery.t_("ui.festival_card.contracts") % n if n > 0 else SimQuery.t_("ui.festival_card.no_contracts")
	var sp := Festivals._sponsor_names(sim, inst) if not inst.is_empty() else ""
	if sp != "":
		tail += ". " + SimQuery.t_("ui.festival_card.thanks") % sp
	elif not inst.is_empty() and not eve:
		tail += ". " + SimQuery.t_("ui.festival_card.poor")
	blocks.append({"type": "paragraph", "text": tail})
	var buttons: Array = [{"id": "ok", "text": SimQuery.t_("ui.festival_card.ok"), "primary": true}]
	if eve and fam != "" and not inst.is_empty():
		for part: String in Festivals.sponsor_parts(sim, inst):
			if part in (inst.get("sponsors", {}).get(fam, []) as Array):
				continue
			var gold := int(Festivals.rules(sim).get("sponsor", {}).get("parts", {}).get(part, {}).get("gold", 0))
			buttons.append({"id": "sponsor:" + part, "text": SimQuery.t_("ui.festival_card.sponsor") % [
				SimQuery.t_("festival.part." + part).to_lower(), gold], "disabled": Money.gold(sim.state, fam) < gold,
				"tip": SimQuery.t_("ui.festival_card.sponsor_tip")})
	if fam != "" and not inst.is_empty():  # juegos (04f §4.26): enter a competition of the feast, or bet on it
		var g: Dictionary = inst.get("games", {}) if inst.get("games") is Dictionary else {}
		for f: Dictionary in def.get("effects", []):
			var spk := str(f.get("id", ""))
			if str(f.get("kind", "")) != "spectacle" or not Festivals._part_ok(inst, f) or not FestivalGames.is_game(sim, spk) \
					or not FestivalGames._to_come(inst, spk):
				continue
			var entered := (g.get("entries", {}) as Dictionary).has(spk)
			buttons.append({"id": "enter:" + spk, "text": SimQuery.t_("ui.festival_card.enter") % SimQuery.t_("spectacle." + spk),
				"disabled": entered, "tip": SimQuery.t_("ui.festival_card.enter_tip")})
			if not entered:
				buttons.append({"id": "bet:" + spk, "text": SimQuery.t_("ui.festival_card.bet") % SimQuery.t_("spectacle." + spk),
					"tip": SimQuery.t_("ui.festival_card.bet_tip")})
	var out := {"template": "card", "title": SimQuery.festival_name(id),
		"image": VisualPaths.illustration_or_greybox("events", id), "blocks": blocks,
		"footer_figures": [{"label": "", "value": when}], "buttons": buttons, "sticky": false,
		"seconds": float(ViewConfig.value("event_card_seconds", 12.0)) * (2.0 if buttons.size() > 1 else 1.0),
		"festival": id, "instance": str(e.get("id", ""))}
	if eve:
		out["ribbon"] = "%s: %s" % [SimQuery.t_("ui.festival_card.eve_ribbon"), SimQuery.festival_name(id)]
	return out


static func _wedding(sim: Sim, e: Dictionary) -> Dictionary:
	var couple: Array = e.get("couple", [])
	var a := str(sim.state.characters.get(str(couple[0]) if couple.size() > 0 else "", {}).get("name", ""))
	var b := str(sim.state.characters.get(str(couple[1]) if couple.size() > 1 else "", {}).get("name", ""))
	var gold := int(Festivals.rules(sim).get("wedding", {}).get("player_feast_gold", 80))
	var fam := str(e.get("family", ""))
	return {"template": "card", "title": SimQuery.t_("ui.festival_card.wedding_title"),
		"image": VisualPaths.illustration_or_greybox("events", "noble_wedding"),
		"blocks": [{"type": "paragraph", "text": SimQuery.t_("ui.festival_card.wedding_body") % [a, b]}],
		"buttons": [{"id": "plain", "text": SimQuery.t_("ui.festival_card.plain_wedding")},
			{"id": "host_wedding", "text": SimQuery.t_("ui.festival_card.host_wedding") % gold, "primary": true,
				"disabled": Money.gold(sim.state, fam) < gold,
				"tip": SimQuery.t_("ui.festival_card.host_wedding_short") % [gold, Money.gold(sim.state, fam)]
					if Money.gold(sim.state, fam) < gold else SimQuery.t_("ui.festival_card.host_wedding_tip")}],
		"sticky": true, "festival": "noble_wedding", "instance": ""}


## One effect of data/festivals.json as {text, sign} ({} for the ones the card does not tell: the life block's routine).
static func effect_line(sim: Sim, f: Dictionary) -> Dictionary:
	var kind := str(f.get("kind", ""))
	var m := float(f.get("mult", 1.0))
	var num := SimQuery._num(m)
	match kind:
		"price", "demand", "customers", "production":
			return EventPage.effect_line(f)
		"holy_day":
			return {"text": SimQuery.t_("ui.festival_card.fx_holy_day") % SimQuery._num(float(f.get("work_mult", 1.0))),
				"sign": "-"}
		"tariff":
			return {"text": SimQuery.t_("ui.festival_card.fx_tariff"), "sign": "+"}
		"route_bonus":
			return {"text": SimQuery.t_("ui.festival_card.fx_route_bonus"), "sign": "+"}
		"stalls":
			return {"text": SimQuery.t_("ui.festival_card.fx_stalls") % int(f.get("count", 0)), "sign": ""}
		"visitors":
			return {"text": SimQuery.t_("ui.festival_card.fx_visitors") % num, "sign": "+"}
		"service":
			return {"text": SimQuery.t_("ui.festival_card.fx_service") % num, "sign": "+"}
		"spectacle":
			return {"text": SimQuery.t_("ui.festival_card.fx_spectacle") % [int(f.get("hour", 0)) % 24,
				SimQuery.t_("spectacle." + str(f.get("id", "")))], "sign": ""}
		"incident":
			if str(f.get("id", "")) != "altercation":
				return {}
			return {"text": SimQuery.t_("ui.festival_card.fx_incident") % num, "sign": "-"}
		"emotion":
			return {"text": SimQuery.t_("ui.festival_card.fx_emotion"), "sign": "+"}
		"reputation":
			if str(f.get("who", "")) != "mayor":
				return {}
			return {"text": SimQuery.t_("ui.festival_card.fx_reputation_mayor") % int(f.get("amount", 0)),
				"sign": "+" if int(f.get("amount", 0)) > 0 else "-"}
		"aguinaldo":
			return {"text": SimQuery.t_("ui.festival_card.fx_aguinaldo") % int(f.get("loyalty", 0)), "sign": "+"}
		"need":
			return {"text": SimQuery.t_("ui.festival_card.fx_need") % int(f.get("amount", 0)), "sign": "+"}
	return {}


## The order of a card button ({} for «Entendido» or «Boda sencilla»): sponsor:<part> or host_wedding.
static func order_for(button: String, d: Dictionary, actor: String) -> Dictionary:
	if button.begins_with("sponsor:"):
		return {"type": "festival_sponsor", "actor": actor, "festival": str(d.get("instance", "")),
			"part": button.substr(8)}
	if button == "host_wedding":
		return {"type": "festival_host_wedding", "actor": actor}
	if button.begins_with("enter:"):
		return {"type": "game_enter", "actor": actor, "festival": str(d.get("instance", "")), "spectacle": button.substr(6)}
	return {}
