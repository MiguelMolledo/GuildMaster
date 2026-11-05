class_name LifeQuery
extends RefCounted
## What the view shows of the living town II (docs/gdd/04f_vida_y_fiestas.md §4.24; docs/contratos/vida.md): the
## bubble over a visitor, a guard, a brawler or the one telling a rumour; the rumour's sentence when the player's
## people are near; the texts of the book of rumours. Reads the state only (Rumors, Visitors, Watch, Incidents);
## gives no orders. The bubbles are the scenes game/visuals/bubbles/<id>.tscn (greybox until the art arrives).

const VISITOR_BUBBLES: Dictionary = {"peddler": "shop", "minstrel": "show", "beggar": "alms", "pilgrim": "pray",
	"merchant": "shop"}


## The bubble of `chr` from the living town ("" = none: the H7 one, if any, stays).
static func bubble_of(sim: Sim, chr: String) -> String:
	var st := sim.state
	if not Life.on(sim):
		return ""
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty():
		return ""
	if not Rumors.told_by(st, chr).is_empty() and _player_near(sim, chr):
		return "rumor"
	var t: Variant = ch.get("town")
	var shown := str((t as Dictionary).get("shown", "")) if t is Dictionary else ""
	match shown:
		"brawl":
			return "fight"
		"watch_fight":
			return "think"
		"guard_greet":
			return "wave"
		"bandit":
			return ""
	if ch.get("visitor") is Dictionary and str((t as Dictionary).get("state", "") if t is Dictionary else "") == "social":
		return str(VISITOR_BUBBLES.get(str(ch["visitor"].get("kind", "")), ""))
	return ""


## The rumour `chr` is telling, as a sentence, when a person of the player's family is within hear_tiles ("" if not).
static func phrase_of(sim: Sim, chr: String) -> String:
	if not Life.on(sim):
		return ""
	var told := Rumors.told_by(sim.state, chr)
	if told.is_empty() or not _player_near(sim, chr):
		return ""
	return rumor_text(sim, told)


static func _player_near(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var tiles := int(Rumors.cfg(sim).get("hear_tiles", 4))
	var at := Life.tile_of(st, chr)
	for f: String in Life.humans(st):
		for m: Variant in st.families[f].get("members", []):
			var c: Dictionary = st.characters.get(str(m), {})
			if not c.is_empty() and bool(c.get("alive", true)) and str(c.get("location", "")) == "" \
					and Life.dist(Life.tile_of(st, str(m)), at) <= tiles:
				return true
	return false


## The sentence of a rumour (told or heard): its text with the params; «@key» params are translated.
static func rumor_text(sim: Sim, r: Dictionary) -> String:
	var p := {}
	var raw: Dictionary = r.get("params", {})
	for k: String in raw:
		var v: Variant = raw[k]
		if v is String and (v as String).begins_with("@"):
			var key := (v as String).substr(1)
			var txt := SimQuery.t_(key)
			if key.begins_with("item.") or key.begins_with("visitor.") or key.begins_with("title."):
				txt = txt.to_lower()
			p[k] = txt
		else:
			p[k] = v
	return SimQuery.t_(str(r.get("text_key", ""))).format(p)


## The book of rumours: [{text, where, useful}] newest first.
static func book(sim: Sim) -> Array:
	var out: Array = []
	for h: Dictionary in Rumors.heard(sim.state):
		var kind := ""
		for p: Dictionary in Life.map(sim).get("social_points", []):
			if str(p.get("id", "")) == str(h.get("point", "")):
				kind = str(p.get("kind", ""))
		if str(h.get("point", "")).begins_with("inn:"):
			kind = "tavern"  # posada: heard at the bar of the Taberna-Posada (InnRumors)
		var day := Clock.day(int(h.get("minute", 0))) + 1
		out.append({"text": rumor_text(sim, h), "where": SimQuery.t_("ui.rumors.where") % [day,
			SimQuery.t_("life.point." + kind) if kind != "" else ""], "useful": bool(h.get("useful", false))})
	return out


## «Guardia de la villa · puerta» («Guardia de Bellcaire · ronda de noche»: the town's watch) / «Mercader de Portvell» for the NPC panel ("" for anybody else).
static func role_line(sim: Sim, chr: String) -> String:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.get("guard") is Dictionary:
		var role := str(ch["guard"].get("role", "")).get_slice("_", 0)
		var wk := str(sim.state.families.get(str(ch.get("family", "")), {}).get("name_key", "family.watch"))
		return SimQuery.t_("ui.life.guard") % [SimQuery.t_(wk if wk != "" else "family.watch"), SimQuery.t_("ui.life.role." + role)]
	if ch.get("visitor") is Dictionary:
		var v: Dictionary = ch["visitor"]
		var kind := SimQuery.t_("visitor." + str(v.get("kind", "")))
		kind = kind.substr(0, 1).to_upper() + kind.substr(1)
		return SimQuery.t_("ui.life.visitor") % [kind, SimQuery.t_(Rumors._city_key(sim, str(v.get("city", ""))))]
	return ""


## Whether `chr` carries a lantern now (a guard on its night round).
static func lantern(sim: Sim, chr: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	return ch.get("guard") is Dictionary and str(ch["guard"].get("role", "")).begins_with("night_") \
		and Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) in ["night", "dusk"]
