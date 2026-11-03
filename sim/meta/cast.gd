class_name Cast
extends RefCounted
## The cast of a game (data/cast.json, docs/contratos/poblacion.md, GDD 4.11.1 and 4.10.9): the cosmetic part of who
## lives in the town. With the cast seed of the game it decides the given names and house surnames of the protagonist's
## family, the rival, the competitors and the townsfolk households of the map, their ages inside the range of their
## role, the sex when the data does not fix it, their look (hair and skin tones, base portrait) and clothes colours,
## and the townsfolk's personality. What weighs on the balance never varies: the stats of the key characters, gold,
## debt, buildings, ranks, professions and the protagonist's age come from data/starts and data/maps as they are.
##   - mode "fixed" (the tests, the scenarios, the bots' targets): the names, ages and tones of data/starts and
##     data/maps, exactly today's town; births and newcomers draw from data/family.json names with the H8 keys.
##   - mode "random" (a player's new game): everything above dealt from data/cast.json.
## Every draw comes from its own stream (Cast._rng: the cast seed + a key): it never moves any other roll of the game.
## The cast seed is a sub-seed of the world seed (sub_seed): the new-game screen's «Otra familia» changes only its
## roll, so the world (events, market, every rule's roll) keeps its seed. It is saved in WorldState.cast.
## Cities: generate() reads the map it is given and the size of its population; another map (or a second town of
## the same game) takes its id into the keys and gets other people.

const FIXED: String = "fixed"
const RANDOM: String = "random"
const MODES: Array[String] = ["fixed", "random"]


## The cast seed of a new game: the world seed and the roll of the new-game screen (0 = its first proposal).
static func sub_seed(world_seed: int, roll: int = 0) -> int:
	return ("cast|%d|%d" % [world_seed, roll]).hash()


## The cast of `start` on `map` (only cosmetic fields): {protagonist {name_m, name_f, family_name, visual},
## rival {family_name, colors, character {name, female, age, visual}}, competitors [{family_name, colors, character,
## spouse}], households [{family_name, colors, members [{name, female, age, visual, stats}]}]}; visual = {hair, skin,
## portrait {type, variant}}. player_primary: the colour the player chose (no AI family gets one close to it).
static func generate(catalog: Catalog, start: Dictionary, map: Dictionary, mode: String, cast_seed: int,
		player_primary: String = "") -> Dictionary:
	var ctx := _context(catalog, mode, cast_seed, str(map.get("id", "")), player_primary)
	if mode == FIXED:
		_reserve_data(ctx, start, map)
	var out := {"protagonist": _protagonist(ctx, start), "competitors": [], "households": []}
	var rv: Dictionary = start.get("rival", {})
	if not rv.is_empty():
		out["rival"] = _workshop_family(ctx, rv, str(rv.get("profession", start.get("profession", ""))), "rival", "rival")
	var i := 0
	for cp: Dictionary in start.get("competitors", []):
		out["competitors"].append(_workshop_family(ctx, cp, str(cp.get("profession", "")), "comp|%d" % i, "competitor"))
		i += 1
	out["households"] = households(ctx, map)
	if OS.is_debug_build():
		print("[Cast] reparto %s (semilla %d, mapa %s): %s «%s» / «%s» de los %s; %d competidores, %d casas" % [mode,
			cast_seed, map.get("id", ""), "protagonista", out["protagonist"]["name_m"], out["protagonist"]["name_f"],
			out["protagonist"]["family_name"], (out["competitors"] as Array).size(), (out["households"] as Array).size()])
	return out


## Only the protagonist's proposal of `start` (the new-game screen): {name_m, name_f, family_name, visual}. The same
## as generate() gives for it with the same seed (the protagonist is dealt first).
static func proposal(catalog: Catalog, start: Dictionary, mode: String, cast_seed: int) -> Dictionary:
	var ctx := _context(catalog, mode, cast_seed, str(start.get("map", "")), "")
	return _protagonist(ctx, start)


## `start` and `map` (deep copies) with the cast's cosmetic fields in place of theirs, for NewGame.from_start: the
## rival, the competitors and the households of the population. The protagonist is a choice (NewGame._choices).
static func apply(start: Dictionary, map: Dictionary, cast: Dictionary) -> Dictionary:
	var st := start.duplicate(true)
	var mp := map.duplicate(true)
	if st.has("rival") and cast.has("rival"):
		_put_family(st["rival"], cast["rival"])
	var comps: Array = st.get("competitors", [])
	for i: int in mini(comps.size(), (cast.get("competitors", []) as Array).size()):
		_put_family(comps[i], cast["competitors"][i])
	var pop: Array = mp.get("population", [])
	for i: int in mini(pop.size(), (cast.get("households", []) as Array).size()):
		var hh: Dictionary = pop[i]
		var gen: Dictionary = cast["households"][i]
		hh["family_name"] = gen["family_name"]
		hh["colors"] = (gen["colors"] as Dictionary).duplicate()
		var members: Array = hh.get("members", [])
		for j: int in mini(members.size(), (gen["members"] as Array).size()):
			var m: Dictionary = members[j]
			var g: Dictionary = gen["members"][j]
			for k: String in ["name", "female", "age", "visual", "stats", "birth_offset"]:
				if g.has(k):
					m[k] = g[k].duplicate(true) if g[k] is Dictionary else g[k]
	return {"start": st, "map": mp}


## The households of `map`'s population (in its order), for generate() or a town added later. ctx from _context.
static func households(ctx: Dictionary, map: Dictionary) -> Array:
	var out: Array = []
	var i := 0
	for hh: Dictionary in map.get("population", []):
		var key := "hh|%d" % i
		var fixed := str(ctx["mode"]) == FIXED
		var fam := {"family_name": str(hh["family_name"]) if fixed and hh.has("family_name") else _surname(ctx, ""),
			"colors": (hh["colors"] as Dictionary).duplicate() if fixed and hh.get("colors") is Dictionary else _colors(ctx),
			"members": []}
		var house_look := _look(ctx, key + "|house")
		var j := 0
		for p: Dictionary in hh.get("members", []):
			var pk := "%s|%d" % [key, j]
			var female: bool = bool(p["female"]) if p.has("female") else _rng(ctx, pk + "|sex").randf() < 0.5
			var m := {"female": female}
			m["name"] = str(p["name"]) if fixed and p.has("name") else _name(ctx, female)
			m["age"] = int(p["age"]) if fixed and p.has("age") else _age(ctx, "townsfolk", pk, 25)
			var vis := _look(ctx, pk)
			if not fixed:
				var res := float(ctx["look"].get("kin_resemblance", 0.0))
				for k: String in ["hair", "skin"]:
					if _rng(ctx, "%s|%s|kin" % [pk, k]).randf() < res:
						vis[k] = house_look[k]
			if fixed and p.get("visual") is Dictionary:
				for k: String in ["hair", "skin"]:
					if (p["visual"] as Dictionary).has(k):
						vis[k] = int(p["visual"][k])
			vis["portrait"] = _portrait(ctx, _role_type(ctx, "townsfolk"), pk)
			m["visual"] = vis
			m["stats"] = (p.get("stats", {}) as Dictionary).duplicate() if fixed else _personality(ctx, p.get("stats", {}), pk)
			(fam["members"] as Array).append(m)
			j += 1
		out.append(fam)
		i += 1
	if str(ctx["mode"]) != FIXED:
		_keep_age_order(ctx, map, out)
	return out


## The townsfolk's ages are drawn, but who is older than whom stays the data's: the government goes to the eldest of
## each titled house (Offices.setup) and an heir is the eldest child, so the drawn ages are handed out in the order of
## the data's (oldest first; ties by id, as the rules break them). Ties among the drawn ones keep that order with a
## day inside the birth year (birth_offset: the age, a whole number of years, does not change).
static func _keep_age_order(ctx: Dictionary, map: Dictionary, gen: Array) -> void:
	var order: Array = []  # [data age, index in the population] of the members with an age in the data
	var drawn: Array = []
	var n := 0
	var pop: Array = map.get("population", [])
	for i: int in pop.size():
		var members: Array = pop[i].get("members", [])
		for j: int in members.size():
			if (members[j] as Dictionary).has("age"):
				order.append([int(members[j]["age"]), n, i, j])
				drawn.append(int(gen[i]["members"][j]["age"]))
			n += 1
	order.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	drawn.sort()
	drawn.reverse()
	var dpy := Clock.days_per_year((ctx["catalog"] as Catalog).time)
	var prev := -1
	var tie := 0
	for k: int in order.size():
		var age := int(drawn[k])
		tie = tie + 1 if age == prev else 0
		prev = age
		var m: Dictionary = gen[int(order[k][2])]["members"][int(order[k][3])]
		m["age"] = age
		m["birth_offset"] = mini(tie, dpy - 1)  # the younger of a tie is born later in the same year


## The context of a deal: the tables, the seed, the decks dealt so far and what is taken.
static func _context(catalog: Catalog, mode: String, cast_seed: int, map_id: String, player_primary: String) -> Dictionary:
	var cfg: Dictionary = catalog.cast
	return {"catalog": catalog, "cfg": cfg, "mode": mode if mode in MODES else RANDOM, "seed": cast_seed, "map": map_id,
		"look": cfg.get("look", {}), "names": {}, "surnames": {}, "decks": {}, "colors_used": {},
		"player_primary": player_primary}


## Fixed cast: the names and surnames written in the data are taken first (a generated one never repeats them).
static func _reserve_data(ctx: Dictionary, start: Dictionary, map: Dictionary) -> void:
	var d: Dictionary = start.get("defaults", {})
	ctx["names"][str(d.get("name", ""))] = true
	ctx["surnames"][str(d.get("family_name", ""))] = true
	var fams: Array = [start.get("rival", {})]
	fams.append_array(start.get("competitors", []))
	for f: Dictionary in fams:
		ctx["surnames"][str(f.get("family_name", ""))] = true
		for who: String in ["character", "spouse"]:
			if f.get(who) is Dictionary:
				ctx["names"][str(f[who].get("name", ""))] = true
	for hh: Dictionary in map.get("population", []):
		ctx["surnames"][str(hh.get("family_name", ""))] = true
		for p: Dictionary in hh.get("members", []):
			ctx["names"][str(p.get("name", ""))] = true


static func _protagonist(ctx: Dictionary, start: Dictionary) -> Dictionary:
	var d: Dictionary = start.get("defaults", {})
	var cls := str(start.get("class", "artisan"))
	var vis := _look(ctx, "pro")
	vis["portrait"] = _portrait(ctx, cls, "pro")
	if str(ctx["mode"]) == FIXED:
		var dv: Dictionary = d.get("visual", {})
		for k: String in ["hair", "skin"]:
			if dv.has(k):
				vis[k] = int(dv[k])
		return {"name_m": str(d.get("name", "")), "name_f": str(d.get("name", "")),
			"family_name": str(d.get("family_name", "")), "visual": vis}
	return {"name_m": _name(ctx, false), "name_f": _name(ctx, true),
		"family_name": _surname(ctx, str(start.get("profession", ""))), "visual": vis}


## The rival or a competitor: {family_name, colors, character, spouse?} from its block of the start.
static func _workshop_family(ctx: Dictionary, src: Dictionary, profession: String, key: String, role: String) -> Dictionary:
	var fixed := str(ctx["mode"]) == FIXED
	var out := {"family_name": str(src.get("family_name", "")) if fixed else _surname(ctx, profession),
		"colors": (src.get("colors", {}) as Dictionary).duplicate() if fixed else _colors(ctx)}
	out["character"] = _person(ctx, src.get("character", {}), role, key)
	if src.get("spouse") is Dictionary and not (src["spouse"] as Dictionary).is_empty():
		out["spouse"] = _person(ctx, src["spouse"], role + "_spouse", key + "|spouse")
	return out


## One character of a workshop family: its sex from the data (a balance input: who courts whom), the rest generated.
static func _person(ctx: Dictionary, src: Dictionary, role: String, key: String) -> Dictionary:
	var fixed := str(ctx["mode"]) == FIXED
	var female := bool(src.get("female", false))
	var vis := _look(ctx, key)
	if fixed and src.get("visual") is Dictionary:
		for k: String in ["hair", "skin"]:
			if (src["visual"] as Dictionary).has(k):
				vis[k] = int(src["visual"][k])
	vis["portrait"] = _portrait(ctx, _role_type(ctx, role.trim_suffix("_spouse")), key)
	return {"name": str(src.get("name", "")) if fixed and src.has("name") else _name(ctx, female), "female": female,
		"age": int(src.get("age", 30)) if fixed and src.has("age") else _age(ctx, role, key, int(src.get("age", 30))),
		"visual": vis}


static func _put_family(dst: Dictionary, gen: Dictionary) -> void:
	dst["family_name"] = gen["family_name"]
	dst["colors"] = (gen["colors"] as Dictionary).duplicate()
	for who: String in ["character", "spouse"]:
		if gen.has(who) and dst.get(who) is Dictionary:
			var c: Dictionary = dst[who]
			c["name"] = gen[who]["name"]
			c["age"] = gen[who]["age"]
			var vis: Dictionary = (c.get("visual", {}) as Dictionary).duplicate()
			vis.merge(gen[who]["visual"], true)
			c["visual"] = vis


## The next given name of `female`'s deck nobody in the cast has (the deck is the pool shuffled with the seed); with
## the deck spent, any of the pool.
static func _name(ctx: Dictionary, female: bool) -> String:
	var pool: Array = ctx["cfg"].get("names", {}).get("female" if female else "male", [])
	var name := _deal(ctx, "names|" + ("female" if female else "male"), pool, ctx["names"])
	ctx["names"][name] = true
	return name


## A house surname: one of `profession`'s trade list while it has unused ones, else a general one; never repeated.
static func _surname(ctx: Dictionary, profession: String) -> String:
	var sn: Dictionary = ctx["cfg"].get("surnames", {})
	var trade: Array = sn.get("trade", {}).get(profession, [])
	var name := ""
	if profession != "" and not trade.is_empty():
		name = _deal(ctx, "surnames|" + profession, trade, ctx["surnames"], false)
	if name == "":
		name = _deal(ctx, "surnames|general", sn.get("general", []), ctx["surnames"])
	ctx["surnames"][name] = true
	return name


## The first card of the deck `deck_id` (pool shuffled with the seed) not in `taken`; "" if every one is taken and
## not `reuse`, else one of the pool by the seed.
static func _deal(ctx: Dictionary, deck_id: String, pool: Array, taken: Dictionary, reuse: bool = true) -> String:
	if pool.is_empty():
		return "?"
	if not ctx["decks"].has(deck_id):
		ctx["decks"][deck_id] = _shuffled(pool, _rng(ctx, "deck|" + deck_id))
	for n: Variant in ctx["decks"][deck_id]:
		if not taken.has(str(n)):
			return str(n)
	if not reuse:
		return ""
	return str(pool[_rng(ctx, "reuse|%s|%d" % [deck_id, taken.size()]).randi_range(0, pool.size() - 1)])


static func _shuffled(pool: Array, r: RandomNumberGenerator) -> Array:
	var a := pool.duplicate()
	for i: int in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
	return a


## A clothes pair not dealt yet, far enough from the player's primary.
static func _colors(ctx: Dictionary) -> Dictionary:
	var cfg: Dictionary = ctx["cfg"].get("family_colors", {})
	var pairs: Array = cfg.get("pairs", [])
	if pairs.is_empty():
		return {"primary": "#808080", "secondary": "#c0c0c0"}
	if not ctx["decks"].has("colors"):
		var idx: Array = range(pairs.size())
		ctx["decks"]["colors"] = _shuffled(idx, _rng(ctx, "deck|colors"))
	var pp := str(ctx.get("player_primary", ""))
	var near := float(cfg.get("min_distance", 0.25))
	var pick := -1
	for i: Variant in ctx["decks"]["colors"]:
		if ctx["colors_used"].has(int(i)):
			continue
		if pp != "" and Color.html_is_valid(pp) and _distance(Color.html(pp), Color.html(str(pairs[int(i)][0]))) < near:
			continue
		pick = int(i)
		break
	if pick < 0:  # every pair dealt (a big town): reuse them in deck order
		pick = int(ctx["decks"]["colors"][ctx["colors_used"].size() % pairs.size()])
	ctx["colors_used"][pick] = true
	return {"primary": str(pairs[pick][0]), "secondary": str(pairs[pick][1])}


static func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## Hair and skin tones of data/cast.json look (the fixed cast overwrites them with the data's).
static func _look(ctx: Dictionary, key: String) -> Dictionary:
	var hair: Array = ctx["look"].get("hair", [0])
	var skin: Array = ctx["look"].get("skin", [0])
	return {"hair": int(hair[_rng(ctx, key + "|hair").randi_range(0, hair.size() - 1)]),
		"skin": int(skin[_rng(ctx, key + "|skin").randi_range(0, skin.size() - 1)])}


## An age in the range of `role` (data/cast.json ages); `fallback` without one.
static func _age(ctx: Dictionary, role: String, key: String, fallback: int) -> int:
	var span: Variant = ctx["cfg"].get("ages", {}).get(role)
	if not span is Array or (span as Array).size() != 2:
		return fallback
	return _rng(ctx, key + "|age").randi_range(int(span[0]), int(span[1]))


## The townsfolk's personality: the stats of data/cast.json personality moved by -jitter..+jitter in [stat_min, max].
static func _personality(ctx: Dictionary, stats: Dictionary, key: String) -> Dictionary:
	var out := stats.duplicate()
	var cfg: Dictionary = ctx["cfg"].get("personality", {})
	var jit := int(cfg.get("jitter", 0))
	var life: Dictionary = (ctx["catalog"] as Catalog).family.get("life", {})
	for k: Variant in cfg.get("stats", []):
		if out.has(str(k)):
			out[str(k)] = clampi(int(out[str(k)]) + _rng(ctx, "%s|pers|%s" % [key, k]).randi_range(-jit, jit),
				int(life.get("stat_min", 1)), int(life.get("stat_max", 10)))
	return out


static func _role_type(ctx: Dictionary, role: String) -> String:
	return str(ctx["cfg"].get("portraits", {}).get("roles", {}).get(role, "townsfolk"))


static func _portrait(ctx: Dictionary, type: String, key: String) -> Dictionary:
	var n := maxi(1, int(ctx["cfg"].get("portraits", {}).get("variants", 1)))
	return {"type": type, "variant": _rng(ctx, key + "|portrait").randi_range(0, n - 1)}


## The stream of one draw: the cast seed, the map and the key. Never state.rng: no other roll moves.
static func _rng(ctx: Dictionary, key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d|%s|%s" % [int(ctx["seed"]), str(ctx["map"]), key]).hash()
	return r


# --- After the start: births and newcomers (Births.born, Population._arrive) ---------------------------------------

## The portrait type of somebody of family `fam` with no other say: the class of the human family, rival for an AI
## family with a profile, townsfolk for the rest (also SaveFile's migration to v14).
static func family_type(st: WorldState, fam: String) -> String:
	var f: Dictionary = st.families.get(fam, {})
	if str(f.get("controlled_by", "")) == "human":
		return str(f.get("class", "artisan"))
	if str(f.get("ai_profile", "")) != "":
		return "rival"
	return "townsfolk"


## Name and look of a child born today (Births.born) to `mother` and `father` of family `fam`. Fixed cast: the H8 draw
## as it was (data/family.json names and tones, world-seed keys). Generated cast: a name no living person has and a
## new tone from data/cast.json look. The portrait type is the father's.
static func newborn(sim: Sim, key: String, female: bool, mother: Dictionary, father: Dictionary, fam: String) -> Dictionary:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.family
	var ptype := str(father.get("visual", {}).get("portrait", {}).get("type", family_type(st, fam))) \
		if father.get("visual") is Dictionary and father["visual"].get("portrait") is Dictionary else family_type(st, fam)
	if mode_of(st) == FIXED:
		var names: Array = cfg.get("names", {}).get("female" if female else "male", ["?"])
		var vis := Births.child_visual(sim, mother.get("visual", {}), father.get("visual", {}), key)
		vis["portrait"] = _later_portrait(sim, ptype, key)
		return {"name": str(names[Kin.randi_range(st, key + "|name", 0, names.size() - 1)]), "visual": vis}
	var vis := {}
	var chance := float(cfg.get("children", {}).get("new_tone_chance", 0.1))
	var look: Dictionary = sim.catalog.cast.get("look", {})
	for k: String in ["hair", "skin"]:
		if Kin.roll(st, "%s|%s|new" % [key, k]) < chance:
			var tones: Array = look.get(k, [0])
			vis[k] = int(tones[_later_rng(st, "%s|%s|tone" % [key, k]).randi_range(0, tones.size() - 1)])
		else:
			var from: Dictionary = mother.get("visual", {}) if Kin.roll(st, "%s|%s|parent" % [key, k]) < 0.5 else father.get("visual", {})
			vis[k] = int(from.get(k, 0))
	vis["portrait"] = _later_portrait(sim, ptype, key)
	return {"name": fresh_name(sim, key, female), "visual": vis}


## Name and look of a newcomer (Population._arrive): {name, hair, skin, portrait}. Fixed cast: the H7 draw as it was.
static func newcomer(sim: Sim, key: String, female: bool) -> Dictionary:
	var st := sim.state
	var ptype := str(sim.catalog.cast.get("portraits", {}).get("roles", {}).get("newcomer", "townsfolk"))
	if mode_of(st) == FIXED:
		var names: Array = sim.catalog.family.get("names", {}).get("female" if female else "male", ["?"])
		var vis: Dictionary = sim.catalog.family.get("visual", {})
		return {"name": str(names[Kin.randi_range(st, key + "|name", 0, names.size() - 1)]),
			"hair": Kin.randi_range(st, key + "|hair", 0, int(vis.get("hair_tones", 6)) - 1),
			"skin": Kin.randi_range(st, key + "|skin", 0, int(vis.get("skin_tones", 4)) - 1),
			"portrait": _later_portrait(sim, ptype, key)}
	var look: Dictionary = sim.catalog.cast.get("look", {})
	var hair: Array = look.get("hair", [0])
	var skin: Array = look.get("skin", [0])
	return {"name": fresh_name(sim, key, female),
		"hair": int(hair[_later_rng(st, key + "|hair").randi_range(0, hair.size() - 1)]),
		"skin": int(skin[_later_rng(st, key + "|skin").randi_range(0, skin.size() - 1)]),
		"portrait": _later_portrait(sim, ptype, key)}


## A given name of data/cast.json no living person has (from a starting point drawn with the cast seed); if all are
## taken, the drawn one.
static func fresh_name(sim: Sim, key: String, female: bool) -> String:
	var pool: Array = sim.catalog.cast.get("names", {}).get("female" if female else "male", [])
	if pool.is_empty():
		pool = sim.catalog.family.get("names", {}).get("female" if female else "male", ["?"])
	var alive := {}
	for c: Dictionary in sim.state.characters.values():
		if bool(c.get("alive", true)):
			alive[str(c.get("name", ""))] = true
	var at := _later_rng(sim.state, key + "|name").randi_range(0, pool.size() - 1)
	for i: int in pool.size():
		var n := str(pool[(at + i) % pool.size()])
		if not alive.has(n):
			return n
	return str(pool[at])


## "fixed" or "random": how this game's cast was made (WorldState.cast; a game from before v14 is fixed).
static func mode_of(st: WorldState) -> String:
	return str(st.cast.get("mode", FIXED))


static func _later_portrait(sim: Sim, type: String, key: String) -> Dictionary:
	var n := maxi(1, int(sim.catalog.cast.get("portraits", {}).get("variants", 1)))
	return {"type": type, "variant": _later_rng(sim.state, key + "|portrait").randi_range(0, n - 1)}


static func _later_rng(st: WorldState, key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d|%s|later|%s" % [int(st.cast.get("seed", 0)), str(st.cast.get("map", "")), key]).hash()
	return r
