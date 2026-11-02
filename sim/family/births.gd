class_name Births
extends RefCounted
## Children (GDD 4.10.3, 4.10.9): at every dawn each married couple may have a child. The first one is possible
## first_child_days after the wedding; from then on daily_chance per day; between_days without a new one after a birth;
## at most max_per_couple. The child inherits the stats ((father + mother) / 2 + random(-jitter, +jitter), clamped,
## +bonus if both are high) and the hair and skin of one parent each (or, rarely, a new tone). It lives in the family's
## residence, is not controllable and has no inventory of its own until it comes of age (Lifecycle).
## Contract: docs/contratos/h8_familia.md. Figures: data/family.json "children", "visual", "names".
## The couple's memory lives in the mother's life: {wedding_day, last_birth_day}.


## At dawn (Ledger.is_dawn), after Lifecycle: the couples in order of the mother's id.
static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	var ids: Array = st.characters.keys()
	ids.sort()
	for m: String in ids:
		var father := couple_father(sim, m)
		if father == "":
			continue
		if not can_conceive(sim, m, today):
			continue
		var chance := float(sim.catalog.family.get("children", {}).get("daily_chance", 0.1))
		var r := Kin.roll(st, "birth|%d|%s" % [today, m])
		if r < chance:
			born(sim, m, father)


## The living husband of `mother` if she is a living, married woman ("" otherwise).
static func couple_father(sim: Sim, mother: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters.get(mother, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or not bool(ch.get("female", false)):
		return ""
	var sp := str(ch.get("spouse", ""))
	if sp == "" or not Kin.alive(st, sp) or bool(st.characters[sp].get("female", false)):
		return ""
	return sp


## Whether the couple of `mother` may have a child today (wedding wait, time since the last birth, how many, age).
static func can_conceive(sim: Sim, mother: String, today: int) -> bool:
	var cfg: Dictionary = sim.catalog.family.get("children", {})
	var ch: Dictionary = sim.state.characters[mother]
	var life: Dictionary = ch.get("life", {})
	if not life.has("wedding_day"):
		return false
	if today < int(life["wedding_day"]) + int(cfg.get("first_child_days", 2)):
		return false
	if life.has("last_birth_day") and today < int(life["last_birth_day"]) + int(cfg.get("between_days", 8)):
		return false
	if couple_children(sim.state, mother, str(ch.get("spouse", ""))).size() >= int(cfg.get("max_per_couple", 3)):
		return false
	return Kin.age(sim, mother) <= int(cfg.get("mother_max_age", 45))


## The children (alive or not) of both `a` and `b`.
static func couple_children(st: WorldState, a: String, b: String) -> Array:
	var out: Array = []
	for c: Variant in st.characters.get(a, {}).get("children", []):
		if b in (st.characters.get(str(c), {}).get("parents", []) as Array):
			out.append(str(c))
	return out


## A child is born to `mother` and `father` today: a new character of the father's family (both are in the same one
## after the wedding). Returns its id.
static func born(sim: Sim, mother: String, father: String) -> String:
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	var m: Dictionary = st.characters[mother]
	var f: Dictionary = st.characters[father]
	var fam := str(f.get("family", ""))
	var cfg: Dictionary = sim.catalog.family
	var key := "child|%d|%s" % [today, mother]
	var female := Kin.roll(st, key + "|sex") < 0.5
	var names: Array = cfg.get("names", {}).get("female" if female else "male", ["?"])
	var name := str(names[Kin.randi_range(st, key + "|name", 0, names.size() - 1)])
	var stats := child_stats(sim, m.get("stats", {}), f.get("stats", {}), key)
	var vis := child_visual(sim, m.get("visual", {}), f.get("visual", {}), key)
	var home := Kin.residence(sim, fam)
	var pos: Array = (st.buildings[home].get("door", m.get("position", [0, 0])) as Array).duplicate() if home != "" \
		else (m.get("position", [0, 0]) as Array).duplicate()
	var id := Ids.next(st, "chr")
	st.characters[id] = {"id": id, "name": name, "female": female, "family": fam, "controlled_by": "ai", "alive": true,
		"position": [int(pos[0]), int(pos[1])], "path": [], "move_progress": 0, "stats": stats,
		"inventory": Inventory.create("weight", 0.0), "equipment": {"tool": null, "clothes": null, "accessory": null},
		"location": home, "station": "", "order_queue": [], "home": "", "rank": "", "job": null, "hire_bans": {},
		"routine": {}, "occupation": "", "town": {}}
	st.characters[id].merge(Kin.character_fields(today, str(st.families.get(fam, {}).get("class", f.get("class", "artisan"))),
		"", int(vis["hair"]), int(vis["skin"]), cfg.get("directives", {}).get("default", ["work"])))
	st.characters[id]["parents"] = [father, mother]
	(st.families[fam]["members"] as Array).append(id)
	for p: Dictionary in [m, f]:
		var kids: Array = p.get("children", [])
		kids.append(id)
		p["children"] = kids
	m["life"]["last_birth_day"] = today
	Chronicle.add(st, "birth", {"family": fam, "character": id, "mother": mother, "father": father})
	sim.events.append({"type": "child_born", "family": fam, "character": id, "mother": mother, "father": father})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, "info", "notice.child_born", {"name": name, "mother": str(m.get("name", "")),
			"father": str(f.get("name", ""))}, id)
	if OS.is_debug_build():
		print("[Births] nace %s «%s» (%s) de %s y %s, familia %s, stats=%s, visual=%s" % [id, name,
			"niña" if female else "niño", mother, father, fam, stats, vis])
	return id


## (father + mother) / 2 + random(-jitter, +jitter), clamped to [stat_min, stat_max], +bonus if both are >= both_high_min.
static func child_stats(sim: Sim, a: Dictionary, b: Dictionary, key: String) -> Dictionary:
	var cfg: Dictionary = sim.catalog.family.get("children", {})
	var life: Dictionary = sim.catalog.family.get("life", {})
	var jit := int(cfg.get("stat_jitter", 1))
	var hi := int(cfg.get("both_high_min", 7))
	var out := {}
	var ks: Array = a.keys()
	ks.sort()
	for k: String in ks:
		var va := int(a.get(k, 1))
		var vb := int(b.get(k, va))
		var v := floori(float(va + vb) / 2.0) + Kin.randi_range(sim.state, "%s|stat|%s" % [key, k], -jit, jit)
		if va >= hi and vb >= hi:
			v += int(cfg.get("both_high_bonus", 1))
		out[k] = clampi(v, int(life.get("stat_min", 1)), int(life.get("stat_max", 10)))
	return out


## Hair and skin each from one parent at random; with new_tone_chance a tone of the palette instead (GDD 4.10.9).
static func child_visual(sim: Sim, a: Dictionary, b: Dictionary, key: String) -> Dictionary:
	var cfg: Dictionary = sim.catalog.family
	var tones := {"hair": int(cfg.get("visual", {}).get("hair_tones", 6)), "skin": int(cfg.get("visual", {}).get("skin_tones", 4))}
	var chance := float(cfg.get("children", {}).get("new_tone_chance", 0.1))
	var out := {}
	for k: String in ["hair", "skin"]:
		if Kin.roll(sim.state, "%s|%s|new" % [key, k]) < chance:
			out[k] = Kin.randi_range(sim.state, "%s|%s|tone" % [key, k], 0, int(tones[k]) - 1)
		else:
			var from: Dictionary = a if Kin.roll(sim.state, "%s|%s|parent" % [key, k]) < 0.5 else b
			out[k] = int(from.get(k, 0))
	return out
