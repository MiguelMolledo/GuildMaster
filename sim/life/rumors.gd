class_name Rumors
extends RefCounted
## Meeting points and rumours (docs/gdd/04f_vida_y_fiestas.md §4.24.2; docs/contratos/vida.md). A corrillo is two to
## five townsfolk (or visitors) standing at the seats of one meeting point (social_points of data/maps). When it forms
## (every meeting.tell_every minutes, one at a time per point) it tells a rumour about something that really
## happened (the chronicle), is happening or will happen (an open election, an event in force, the board, a rival's debt, the prices of another town, the visitors, the
## bandits seen on the eve of a raid): data/life/rumors.json, weighted by the point's ambience (meeting.kinds topics).
## A character of the player's family within hear_tiles hears it: it goes to the book of rumours
## (state.town.rumors.heard, the last keep_heard) once per rumour. The rest is view: the bubble over the speaker.
##
## state.town.rumors: told {point: {key, rumor, text_key, params, speaker, until, useful}} (the rumour in the air at
## each point), heard [{key, rumor, text_key, params, minute, point, useful}].
## Params: values that start with «@» are i18n keys (a city, an item, an office), the rest go as they are.


static func cfg(sim: Sim) -> Dictionary:
	return Life.cfg(sim.catalog).get("meeting", {})


static func defs(sim: Sim) -> Dictionary:
	return sim.catalog.life_tables.get("rumors", {})


static func book(st: WorldState) -> Dictionary:
	var b: Variant = st.town.get("rumors")
	if b is Dictionary and (b as Dictionary).size() > 0:
		return b
	Life.ensure(st)
	return st.town["rumors"]


## Once per minute (Life.step): on the hour the corrillos tell; every minute those in the air may be heard.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var b := book(st)
	var told: Dictionary = b["told"]
	for p: String in told.keys():
		if now >= int(told[p].get("until", 0)):
			told.erase(p)
	var every := maxi(1, int(cfg(sim).get("tell_every", 10)))
	if now % every == 0 and (Clock.phase(now, sim.catalog.time) != "night" or _night_points(sim)):
		_tell(sim, now)
	if not told.is_empty():
		_hear(sim, now)


static func _night_points(sim: Sim) -> bool:
	return not Life.points(sim, ["tavern"]).is_empty()


## The people standing now at each meeting point's seats: {point id: [chr...]} (only points with someone).
static func corrillos(sim: Sim) -> Dictionary:
	var st := sim.state
	var seats := {}
	var kinds: Dictionary = cfg(sim).get("kinds", {})
	for p: Dictionary in Life.map(sim).get("social_points", []):
		if not kinds.has(str(p.get("kind", ""))):
			continue
		for s: Variant in p.get("slots", []):
			seats["%d,%d" % [int(s[0]), int(s[1])]] = str(p["id"])
	var out := {}
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		if not bool(ch.get("alive", true)) or str(ch.get("location", "")) != "" or Life.offstage(st, id) \
				or not (ch.get("path", []) as Array).is_empty() or ch.get("bandit") is Dictionary:
			continue
		var pos: Array = ch.get("position", [])
		if pos.size() != 2:
			continue
		var k := "%d,%d" % [int(pos[0]), int(pos[1])]
		if seats.has(k):
			var pid: String = seats[k]
			if not out.has(pid):
				out[pid] = []
			(out[pid] as Array).append(id)
	return out


static func _point(sim: Sim, id: String) -> Dictionary:
	for p: Dictionary in Life.map(sim).get("social_points", []):
		if str(p.get("id", "")) == id:
			return p
	return {}


## Each corrillo of corrillo.min or more people with no rumour in the air tells one (the speaker: the first by id).
static func _tell(sim: Sim, now: int) -> void:
	var st := sim.state
	var b := book(st)
	var groups := corrillos(sim)
	var cmin := int(cfg(sim).get("corrillo", {}).get("min", 2))
	var cands: Array = []
	var built := false
	var pids: Array = groups.keys()
	pids.sort()
	for pid: String in pids:
		var who: Array = groups[pid]
		if who.size() < cmin or (b["told"] as Dictionary).has(pid):
			continue
		if not built:
			cands = candidates(sim, now)
			built = true
		if cands.is_empty():
			return
		var p := _point(sim, pid)
		var topics: Array = cfg(sim).get("kinds", {}).get(str(p.get("kind", "")), {}).get("topics", [])
		var total := 0.0
		var weights: Array = []
		var heard := {}
		for h: Dictionary in b["heard"]:
			heard[str(h.get("key", ""))] = true
		for c: Dictionary in cands:
			var w := float(c["weight"]) * (float(cfg(sim).get("topic_mult", 3.0)) if str(c["topic"]) in topics else 1.0)
			if heard.has(str(c["key"])):
				w *= float(cfg(sim).get("heard_mult", 0.25))  # old news: told less
			weights.append(w)
			total += w
		var r := Kin.roll(st, "life|rumor|%s|%d" % [pid, now]) * total
		var pick: Dictionary = cands[cands.size() - 1]
		for i: int in cands.size():
			r -= float(weights[i])
			if r < 0.0:
				pick = cands[i]
				break
		var told := pick.duplicate(true)
		told["speaker"] = str(who[0])
		told["until"] = now + int(cfg(sim).get("bubble_minutes", 40))
		told["point"] = pid
		told["listeners"] = who.size()
		b["told"][pid] = told
		sim.events.append({"type": "rumor_told", "point": pid, "rumor": str(pick["rumor"]), "key": str(pick["key"]),
			"speaker": str(who[0])})
		if OS.is_debug_build():
			print("[Rumors] corrillo en %s (%d): %s (%s)" % [pid, who.size(), pick["rumor"], pick["key"]])


## A character of a human family within hear_tiles of a point with a rumour in the air hears it (once per rumour).
static func _hear(sim: Sim, now: int) -> void:
	var st := sim.state
	var b := book(st)
	var tiles := int(cfg(sim).get("hear_tiles", 4))
	var listeners: Array = []
	for f: String in Life.humans(st):
		for m: Variant in st.families[f].get("members", []):
			var ch: Dictionary = st.characters.get(str(m), {})
			if not ch.is_empty() and bool(ch.get("alive", true)) and str(ch.get("location", "")) == "" \
					and not Region.is_away(st, str(m)):
				listeners.append(str(m))
	if listeners.is_empty():
		return
	var heard_keys := {}
	for h: Dictionary in b["heard"]:
		heard_keys[str(h.get("key", ""))] = true
	for pid: String in (b["told"] as Dictionary).keys():
		var told: Dictionary = b["told"][pid]
		if heard_keys.has(str(told["key"])):
			continue
		var p := _point(sim, pid)
		var who := ""
		for l: String in listeners:
			for s: Variant in p.get("slots", []):
				if Life.dist(Life.tile_of(st, l), s) <= tiles:
					who = l
					break
			if who != "":
				break
		if who == "":
			continue
		var entry := {"key": str(told["key"]), "rumor": str(told["rumor"]), "text_key": str(told["text_key"]),
			"params": (told.get("params", {}) as Dictionary).duplicate(true), "minute": now, "point": pid,
			"useful": bool(told.get("useful", false)), "by": who}
		(b["heard"] as Array).append(entry)
		heard_keys[str(told["key"])] = true
		var keep := int(cfg(sim).get("keep_heard", 60))
		while (b["heard"] as Array).size() > keep:
			(b["heard"] as Array).pop_front()
		sim.events.append({"type": "rumor_heard", "character": who, "rumor": str(told["rumor"]), "key": str(told["key"]),
			"point": pid, "useful": bool(told.get("useful", false))})
		if OS.is_debug_build():
			print("[Rumors] %s oye en %s: %s (%s)" % [who, pid, told["rumor"], told["key"]])


# --- What is talked about ----------------------------------------------------------------------------------------

## The rumours that could be told now: [{key, rumor, topic, weight, text_key, params, useful}], in a fixed order.
static func candidates(sim: Sim, now: int) -> Array:
	var st := sim.state
	var out: Array = []
	var all := defs(sim)
	var names: Array = all.keys()
	names.sort()
	var since := now - int(cfg(sim).get("lookback_days", 4)) * Clock.MINUTES_PER_DAY
	var memo := {}  # the prices looked up while gathering (nothing changes them meanwhile): shared by the sources
	for rid: String in names:
		var d: Dictionary = all[rid]
		var base := {"rumor": rid, "topic": str(d.get("topic", "")), "weight": float(d.get("weight", 1.0)),
			"text_key": str(d.get("text_key", "rumor." + rid)), "useful": bool(d.get("useful", false))}
		for c: Dictionary in _of_source(sim, str(d.get("source", "")), d, since, now, memo):
			var e := base.duplicate(true)
			e["key"] = "%s|%s" % [rid, c["key"]]
			e["params"] = c["params"]
			out.append(e)
	return out


static func _of_source(sim: Sim, source: String, d: Dictionary, since: int, now: int, memo: Dictionary = {}) -> Array:
	var st := sim.state
	var out: Array = []
	match source:
		"chronicle":
			var kinds: Array = d.get("kinds", [])
			for i: int in range(st.chronicle.size() - 1, -1, -1):
				var e: Dictionary = st.chronicle[i]
				if int(e.get("minute", 0)) < since:
					break
				if str(e.get("kind", "")) in kinds:
					out.append({"key": "%d|%s" % [int(e["minute"]), e.get("kind", "")], "params": _chronicle_params(sim, e)})
				if out.size() >= 6:
					break
		"loans":
			var ids: Array = st.loans.keys()
			ids.sort()
			for id: String in ids:
				var l: Dictionary = st.loans[id]
				var fam := str(l.get("family", ""))
				if Loans.is_open(l) and str(st.families.get(fam, {}).get("controlled_by", "")) != "human" \
						and int(l.get("outstanding", 0)) > 0:
					out.append({"key": id, "params": {"family": _family_name(st, fam), "amount": int(l["outstanding"])}})
		"city_prices":
			var best := _best_city_item(sim, memo)
			if not best.is_empty():
				out.append({"key": "%s|%s" % [best["city"], best["item"]],
					"params": {"city": "@" + str(best["city_key"]), "item": "@item." + str(best["item"])}})
		"visitor_prices":
			for v: String in Visitors.alive(st):
				var vis: Dictionary = st.characters[v].get("visitor", {})
				if str(vis.get("kind", "")) != "merchant":
					continue
				var item := _dear_item(sim, str(vis.get("city", "")), memo)
				if item != "":
					out.append({"key": "%s|%s" % [v, item], "params": {"name": str(st.characters[v].get("name", "")),
						"city": "@" + _city_key(sim, str(vis.get("city", ""))), "item": "@item." + item}})
		"elections":
			for el: Dictionary in st.elections:
				if str(el.get("status", "")) == "open":
					var od: Dictionary = sim.catalog.tables.get("offices", {}).get(str(el.get("office", "")), {})
					out.append({"key": str(el.get("id", "")), "params": {"office": "@" + str(od.get("name_key", "office." + str(el.get("office", "")))),
						"day": int(el.get("day", 0)) + 1}})
		"events":
			for e: Dictionary in st.events_active:
				var def: Dictionary = sim.catalog.world_events().get(str(e.get("def", "")), {})
				out.append({"key": str(e.get("id", "")), "params": {"event": "@" + str(def.get("text_key", "event." + str(e.get("def", "")))),
					"days": maxi(1, ceili(float(int(e.get("end", now)) - now) / float(Clock.MINUTES_PER_DAY)))}})
		"board":
			for c: Dictionary in st.contracts.get("board", []):
				out.append({"key": str(c.get("id", "")), "params": {"item": "@item." + str(c.get("item", "")),
					"qty": int(c.get("qty", 1)), "pay": int(c.get("pay", 0))}})
				if out.size() >= 3:
					break
		"visitors":  # the last one who came: the news of the day
			var alive := Visitors.alive(st)
			if not alive.is_empty():
				var v: String = alive[alive.size() - 1]
				var vis: Dictionary = st.characters[v].get("visitor", {})
				var f := ".f" if bool(st.characters[v].get("female", false)) else ""
				out.append({"key": v, "params": {"name": str(st.characters[v].get("name", "")),
					"kind": "@visitor." + str(vis.get("kind", "")) + f, "city": "@" + _city_key(sim, str(vis.get("city", "")))}})
		"warning":
			var w: Dictionary = Incidents.book(st).get("warned", {})
			for k: String in w:
				if int(w[k].get("until", 0)) > now:
					out.append({"key": k, "params": {"place": "@" + str(w[k].get("place_key", "nest.road"))}})
	return out


static func _chronicle_params(sim: Sim, e: Dictionary) -> Dictionary:
	var st := sim.state
	var p := {"family": _family_name(st, str(e.get("family", "")))}
	for k: String in ["character", "spouse", "actor", "target", "rival", "heir", "victim"]:
		if e.has(k):
			p["name" if k in ["character", "actor"] else k] = str(st.characters.get(str(e[k]), {}).get("name", ""))
	if e.has("title"):
		p["title"] = "@title." + str(e["title"])
	if e.has("office"):
		p["office"] = "@office." + str(e["office"])
	if e.has("place_key"):
		p["place"] = "@" + str(e["place_key"])
	if e.has("age"):
		p["age"] = int(e["age"])
	return p


static func _family_name(st: WorldState, fam: String) -> String:
	var f: Dictionary = st.families.get(fam, {})
	return str(f.get("name", fam))


static func _city_key(sim: Sim, city: String) -> String:
	return str(Region.settlement(sim, city).get("name_key", "region." + city))


## The item and town of the region whose selling price beats the home market's the most (today).
static func _best_city_item(sim: Sim, here_of: Dictionary = {}) -> Dictionary:
	var best := {}
	var best_r := 1.05
	var home := Region.home_id(sim)
	# here_of: the home price of each item (and each city's dearest item, "@<city>"), worked out once for every city
	# and source (Market.price and Region.price only read)
	for s: Dictionary in Region.settlements(sim):
		var c := str(s.get("id", ""))
		if c == home or not Region.is_city(sim, c):
			continue
		var it := _dear_item(sim, c, here_of)
		if it == "":
			continue
		var here := float(maxi(1, int(here_of[it])))
		var r := float(int((here_of["@prices|" + c] as Dictionary)[it])) / here
		if r > best_r:
			best_r = r
			best = {"city": c, "item": it, "city_key": _city_key(sim, c)}
	return best


## The traded item that sells best in town `c` compared with home ("" if none or no region).
static func _dear_item(sim: Sim, c: String, here_of: Dictionary = {}) -> String:
	if here_of.has("@" + c):
		return str(here_of["@" + c])
	if c == "" or not Region.is_city(sim, c):
		return ""
	var best := ""
	var best_r := 1.0
	if not here_of.has("@items"):
		here_of["@items"] = Region.traded_items(sim)
	var items: Array = here_of["@items"]
	var there := Region.prices(sim, c, items, Inventory.NORMAL, "sell")  # the city's part looked up once
	here_of["@prices|" + c] = there
	for it: Variant in items:
		if not here_of.has(str(it)):
			here_of[str(it)] = Market.price(sim, str(it), Inventory.NORMAL, "sell")
		var here := float(maxi(1, int(here_of[str(it)])))
		var r := float(int(there[str(it)])) / here
		if r > best_r:
			best_r = r
			best = str(it)
	here_of["@" + c] = best
	return best


# --- Queries for the UI ---------------------------------------------------------------------------------------------

## The rumour in the air that `chr` is telling now ({} if none).
static func told_by(st: WorldState, chr: String) -> Dictionary:
	var r: Variant = st.town.get("rumors")
	if not r is Dictionary:
		return {}
	for pid: String in ((r as Dictionary).get("told", {}) as Dictionary):
		var t: Dictionary = r["told"][pid]
		if str(t.get("speaker", "")) == chr:
			return t
	return {}


## The rumours heard by the player's families, the newest first.
static func heard(st: WorldState) -> Array:
	var r: Variant = st.town.get("rumors")
	if not r is Dictionary:
		return []
	var out: Array = ((r as Dictionary).get("heard", []) as Array).duplicate()
	out.reverse()
	return out
