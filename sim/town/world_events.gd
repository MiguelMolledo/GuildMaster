class_name WorldEvents
extends RefCounted
## H13 · seasons in prices and production, and the global events (GDD 4.5.3 phase 2, 4.13). Data: data/seasons.json
## (goods groups; price and production multipliers by season and group) and data/events.json (each event: trigger,
## chance by season, duration, excludes, declarable, declarative effects, text). State: state.events_active, the
## events in force [{id, def, start, end, by}] (minutes; end is exclusive).
##
## Rolls: at day_started. On the first day of a season one roll for the season-scope events; every day one roll for
## the local ones. A roll starts at most one event: a single number from the world seed by key (Kin.roll "gev|..."),
## so it never moves any other roll, against the sum of the chances of the events that may start (each one keeps its
## own chance). A season event lasts whole seasons from the start of the season it falls in; a local one lasts whole
## days but never past the end of its season (GDD 4.13). The mayor declares the declarable ones (Offices,
## declare_event): they start at once with the same duration rule.
##
## Effects (a list of {kind, ...} like the microevents of 4.20): price / demand / production on a goods group,
## customers (counter frequency), errands (errand hours), mortality (the yearly death roll). Multipliers multiply;
## the season multiplies price and production too. Everything is 1 where nothing says otherwise.

const SCOPES: Array[String] = ["season", "local"]
const EFFECTS: Array[String] = ["price", "demand", "production", "customers", "errands", "mortality"]
const GROUP_EFFECTS: Array[String] = ["price", "demand", "production"]


## Once per minute, after Lifecycle (an event that ends at the year change still counts for that year's deaths).
static func step(sim: Sim) -> void:
	var st := sim.state
	if not st.events_active.is_empty():
		_end_due(sim, int(st.clock["minute"]))
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "day_started":
			_day(sim, int(e.get("day", 0)))


static func _day(sim: Sim, day: int) -> void:
	if not bool(sim.catalog.events.get("enabled", true)):
		return
	if day % _days_per_season(sim) == 0:
		_roll(sim, "season", day)
	_roll(sim, "local", day)


## One roll of `scope` on `day`: at most one event starts.
static func _roll(sim: Sim, scope: String, day: int) -> void:
	var st := sim.state
	var season := Clock.season(day * Clock.MINUTES_PER_DAY, sim.catalog.time)
	var options: Array = []
	var total := 0.0
	for id: String in _sorted_keys(sim.catalog.world_events()):
		var def: Dictionary = sim.catalog.world_events()[id]
		var trig: Dictionary = def.get("trigger", {})
		if str(def.get("scope", "")) != scope or day < int(trig.get("min_day", 0)) or can_start(sim, id) != "":
			continue
		var p := float(trig.get("chance", {}).get(season, 0.0))
		if p > 0.0:
			options.append({"id": id, "p": p})
			total += p
	if options.is_empty():
		return
	var r := Kin.roll(st, "gev|%s|%d" % [scope, day])
	if OS.is_debug_build():
		print("[WorldEvents] tirada %s del día %d (%s): %.3f contra %.3f entre %s" % [scope, day, season, r, total,
			options.map(func(o: Dictionary) -> String: return str(o["id"]))])
	for o: Dictionary in options:
		r -= float(o["p"])
		if r < 0.0:
			start(sim, str(o["id"]))
			return


## "" if event `id` may start now, else why not: unknown_event, event_disabled, event_active, event_excluded,
## too_many_events.
static func can_start(sim: Sim, id: String) -> String:
	var def: Dictionary = sim.catalog.world_events().get(id, {})
	if def.is_empty():
		return "unknown_event"
	if not bool(def.get("enabled", false)) or not bool(sim.catalog.events.get("enabled", true)):
		return "event_disabled"
	var rules: Dictionary = sim.catalog.events.get("rules", {})
	var locals := 0
	for ev: Dictionary in sim.state.events_active:
		var other := str(ev.get("def", ""))
		if other == id:
			return "event_active"
		if other in (def.get("excludes", []) as Array) \
				or id in (sim.catalog.world_events().get(other, {}).get("excludes", []) as Array):
			return "event_excluded"
		if str(sim.catalog.world_events().get(other, {}).get("scope", "")) == "local":
			locals += 1
	if sim.state.events_active.size() >= int(rules.get("max_active", 3)):
		return "too_many_events"
	if str(def.get("scope", "")) == "local" and locals >= int(rules.get("max_local_active", 1)):
		return "too_many_events"
	return ""


## Starts event `id` now (by: the character who declared it, "" = the roll). Does not check can_start (the callers
## do). Notices for the human families. Returns the id of the event in force ("" if unknown).
static func start(sim: Sim, id: String, by: String = "") -> String:
	var st := sim.state
	var def: Dictionary = sim.catalog.world_events().get(id, {})
	if def.is_empty():
		return ""
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	var dps := _days_per_season(sim)
	var season_start := today - today % dps
	var season_end := (season_start + dps) * Clock.MINUTES_PER_DAY
	var dur: Dictionary = def.get("duration", {})
	var end := 0
	if str(def.get("scope", "")) == "season":
		var span: Array = dur.get("seasons", [1, 1])
		var n := Kin.randi_range(st, "gev|dur|%s|%d" % [id, today], int(span[0]), int(span[1]))
		end = (season_start + n * dps) * Clock.MINUTES_PER_DAY
	else:
		var span: Array = dur.get("days", [1, 1])
		var n := Kin.randi_range(st, "gev|dur|%s|%d" % [id, today], int(span[0]), int(span[1]))
		end = mini(now + n * Clock.MINUTES_PER_DAY, season_end)  # a local event never outlasts its season
	var ev := {"id": Ids.next(st, "gev"), "def": id, "start": now, "end": end, "by": by}
	st.events_active.append(ev)
	sim.events.append({"type": "world_event_started", "id": str(ev["id"]), "def": id, "start": now, "end": end,
		"by": by})
	var params := {"event": id, "days": _days_text(end - now)}
	var key := "notice.event_started"
	if by != "" and st.characters.has(by):
		key = "notice.event_declared"
		params["name"] = str(st.characters[by].get("name", ""))
	for f: String in _humans(st):
		Notices.add(sim, f, Notices.WARNING, key, params, by)
	if OS.is_debug_build():
		print("[WorldEvents] empieza %s (%s) en el minuto %d hasta el %d (%s días, por=%s)" % [ev["id"], id, now, end,
			params["days"], by if by != "" else "tirada"])
	return str(ev["id"])


static func _end_due(sim: Sim, now: int) -> void:
	var st := sim.state
	var keep: Array = []
	var ended: Array = []
	for ev: Dictionary in st.events_active:
		if now >= int(ev.get("end", 0)):
			ended.append(ev)
		else:
			keep.append(ev)
	if ended.is_empty():
		return
	st.events_active = keep
	for ev: Dictionary in ended:
		sim.events.append({"type": "world_event_ended", "id": str(ev.get("id", "")), "def": str(ev.get("def", ""))})
		for f: String in _humans(st):
			Notices.add(sim, f, Notices.INFO, "notice.event_ended", {"event": str(ev.get("def", ""))})
		if OS.is_debug_build():
			print("[WorldEvents] acaba %s (%s) en el minuto %d" % [ev.get("id", ""), ev.get("def", ""), now])


# --- Multipliers (what the rules read) --------------------------------------------------------------------------------

## mod_estación × mod_evento of `item`'s market price (GDD 4.5.3, phase 2).
static func price_mult(sim: Sim, item: String) -> float:
	return season_mult(sim, "price", item) * event_mult(sim, "price", item)


## What the events do to `item`'s demand (the market clamps the result to its limits).
static func demand_mult(sim: Sim, item: String) -> float:
	return event_mult(sim, "demand", item)


## The speed of a cycle whose product is `item` (0.5 = it takes twice as long).
static func production_mult(sim: Sim, item: String) -> float:
	return season_mult(sim, "production", item) * event_mult(sim, "production", item)


static func customers_mult(sim: Sim) -> float:
	return event_mult(sim, "customers")


static func errands_mult(sim: Sim) -> float:
	return event_mult(sim, "errands")


static func mortality_mult(sim: Sim) -> float:
	return event_mult(sim, "mortality")


## The season's multiplier of `table` (price | production) for `item`: the product over its goods groups.
static func season_mult(sim: Sim, table: String, item: String) -> float:
	return season_mult_in(sim, season_table(sim, table), item)


## The season's entries of `table` now ({group: mult}; Region.prices looks it up once for many items).
static func season_table(sim: Sim, table: String) -> Dictionary:
	return sim.catalog.seasons.get(table, {}).get(Clock.season(int(sim.state.clock["minute"]), sim.catalog.time), {})


static func season_mult_in(sim: Sim, by_group: Dictionary, item: String) -> float:
	if by_group.is_empty():
		return 1.0
	var m := 1.0
	for g: String in sim.catalog.goods_of(item):
		if by_group.has(g):
			m *= float(by_group[g])
	return m


## The product of the active events' effects of `kind` (on `item`'s groups for the group effects).
static func event_mult(sim: Sim, kind: String, item: String = "") -> float:
	var m := Festivals.mult(sim, kind, item)  # fiestas (04f 4.25.3): the festival of the hour, 1 when none
	if sim.state.events_active.is_empty():
		return m
	var groups: Array = sim.catalog.goods_of(item) if item != "" else []
	for ev: Dictionary in sim.state.events_active:
		for e: Dictionary in sim.catalog.world_events().get(str(ev.get("def", "")), {}).get("effects", []):
			if str(e.get("kind", "")) != kind:
				continue
			if kind in GROUP_EFFECTS and not str(e.get("group", "")) in groups:
				continue
			m *= float(e.get("mult", 1.0))
	return m


## Why `item`'s price is not its base now, for the market and the book: [{source: "season" | "event", id (the season
## or the event def), group, kind (price | demand), mult}] in that order, only the multipliers != 1.
static func factors(sim: Sim, item: String) -> Array:
	var out: Array = []
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	var by_group: Dictionary = sim.catalog.seasons.get("price", {}).get(season, {})
	for g: String in sim.catalog.goods_of(item):
		if by_group.has(g) and absf(float(by_group[g]) - 1.0) > 0.0001:
			out.append({"source": "season", "id": season, "group": g, "kind": "price", "mult": float(by_group[g])})
	for ev: Dictionary in sim.state.events_active:
		for e: Dictionary in sim.catalog.world_events().get(str(ev.get("def", "")), {}).get("effects", []):
			var k := str(e.get("kind", ""))
			if k in ["price", "demand"] and str(e.get("group", "")) in sim.catalog.goods_of(item) \
					and absf(float(e.get("mult", 1.0)) - 1.0) > 0.0001:
				out.append({"source": "event", "id": str(ev.get("def", "")), "group": str(e["group"]), "kind": k,
					"mult": float(e["mult"])})
	out.append_array(Festivals.factors(sim, item))  # fiestas (04f 4.25.3)
	return out


## The season's price multipliers now: {group: mult} (only the ones != 1), for the book.
static func season_prices(sim: Sim) -> Dictionary:
	var out := {}
	var by_group: Dictionary = sim.catalog.seasons.get("price", {}).get(Clock.season(int(sim.state.clock["minute"]),
		sim.catalog.time), {})
	for g: String in _sorted_keys(by_group):
		if absf(float(by_group[g]) - 1.0) > 0.0001:
			out[g] = float(by_group[g])
	return out


# --- Queries for the UI -----------------------------------------------------------------------------------------------

## The events in force, oldest first: [{id, def, text_key, scope, by, start, end, minutes_left, effects}].
static func view(sim: Sim) -> Array:
	var out: Array = []
	var now := int(sim.state.clock["minute"])
	for ev: Dictionary in sim.state.events_active:
		var def: Dictionary = sim.catalog.world_events().get(str(ev.get("def", "")), {})
		out.append({"id": str(ev.get("id", "")), "def": str(ev.get("def", "")),
			"text_key": str(def.get("text_key", "event." + str(ev.get("def", "")))), "scope": str(def.get("scope", "")),
			"by": str(ev.get("by", "")), "start": int(ev.get("start", 0)), "end": int(ev.get("end", 0)),
			"minutes_left": maxi(0, int(ev.get("end", 0)) - now), "effects": (def.get("effects", []) as Array).duplicate(true)})
	return out


## The events the mayor may declare (enabled and declarable), sorted.
static func declarable(sim: Sim) -> Array:
	var out: Array = []
	for id: String in _sorted_keys(sim.catalog.world_events()):
		var def: Dictionary = sim.catalog.world_events()[id]
		if bool(def.get("enabled", false)) and bool(def.get("declarable", false)):
			out.append(id)
	return out


static func is_active(sim: Sim, id: String) -> bool:
	for ev: Dictionary in sim.state.events_active:
		if str(ev.get("def", "")) == id:
			return true
	return false


# --- Internals --------------------------------------------------------------------------------------------------------

static func _days_per_season(sim: Sim) -> int:
	return maxi(1, int(sim.catalog.time.get("days_per_season", 2)))


## Whole days a span of minutes covers, rounded up (at least 1).
static func _days_text(minutes: int) -> int:
	return maxi(1, ceili(float(minutes) / float(Clock.MINUTES_PER_DAY)))


static func _humans(st: WorldState) -> Array:
	var out: Array = []
	for f: String in _sorted_keys(st.families):
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(f)
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = []
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys
