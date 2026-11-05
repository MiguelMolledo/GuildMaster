class_name BotPacing
extends BotArtisanNovice
## The pacing bot (docs/gdd/03b_diversion_y_ritmo.md §3b.6): plays year 1 of a new game as the novice blacksmith
## (BotArtisanNovice) but forges by hand in Forja viva at the anvil (playing the three decisions well) and reads every
## unlock card. It measures the rhythm a player would feel:
##   (a) the real seconds between decisions with sense (an order it gives, a decision of the Forja viva, a card read):
##       a game minute is real_seconds_per_day / 1440 at ×1, and 1/8 of that while the bot would «Saltar hasta…»
##       (§3b.5.2, O-D3: nothing to decide and something to wait for: a cycle under way, the night). Walking is never
##       skipped. Orders less than MERGE_S apart (the stops of one trip) count as one decision. gap_median_s, gap_p90_s, gap_max_s (the diana: median < 30 s, max < 60 s).
##   (b) the open goals of the goals zone (OpenGoals.view) at every game hour: goals_min, goals_mean (diana: >= 2).
##   (c) the day each unlock of data/unlocks.json came: unlock_<id>_day (-1 never), unlocks_off = how many of those
##       whose window ends inside the days played came outside their window ±1 day (or never); hooks not ready are
##       left out (diana: 0).
## Same orders as the player; draws nothing from state.rng itself.

const SKIP: float = 8.0
const MERGE_S: float = 3.0   # real seconds: orders closer than this to the last decision are the same decision

var _last_decision: float = -1.0   # real seconds (at the bot's pace) of the last decision
var _clock_s: float = 0.0          # real seconds played so far (at ×1, ×8 while skipping)
var _last_minute: int = -1
var _gaps: Array = []
var _goal_samples: Array = []
var _start_day: int = -1
var _days: int = 0


func orders(sim: Sim) -> Array:
	var st := sim.state
	var now := int(st.clock["minute"])
	if _start_day < 0:
		_start_day = Clock.day(now)
	var out: Array = []
	var card := _card(sim)
	if not card.is_empty():
		out = [card]
	else:
		var live := _live(sim)
		out = [live] if not live.is_empty() else super.orders(sim)
	_tick(sim, now, not out.is_empty())
	return out


## A card not read yet: unlock_seen.
func _card(sim: Sim) -> Dictionary:
	var fam := _fam(sim)
	for e: Dictionary in Unlocks.list(sim, fam):
		if not bool(e.get("seen", false)):
			return {"type": "unlock_seen", "actor": ACTOR, "unlock": str(e["id"]), "what": "card"}
	return {}


## The next decision of a Forja viva job of the protagonist, played well (the recipe's colour, its template, the
## temper the contract or the recipe wants).
func _live(sim: Sim) -> Dictionary:
	var v := LiveForge.view(sim, FORGE, ANVIL)
	if v.is_empty() or str(v["actor"]) != ACTOR or str(v["stage"]) == "done":
		return {}
	var rdef := LiveForge.recipe_def(sim, str(v["recipe"]))
	var part: Dictionary = sim.state.buildings[FORGE]["zones"][ANVIL]["job"]["live"]
	var o := {"type": "live_forge", "actor": ACTOR, "building": FORGE, "zone": ANVIL}
	match str(v["stage"]):
		"heat":
			o["step"] = "heat"
			o["choice"] = str(rdef.get("heat", ""))
		"strike":
			o["step"] = "strike"
			o["choice"] = str(LiveForge.template_of(sim, rdef, part)[(v["strikes"] as Array).size()])
		"quench":
			o["step"] = "quench"
			o["choice"] = LiveForge.wanted_quench(rdef, part)
	return o


## Hand work at the anvil goes in Forja viva.
func _make(sim: Sim, rid: String, mode: String) -> Dictionary:
	var w := super._make(sim, rid, mode)
	if not w.is_empty() and str(w.get("zone", "")) == ANVIL and not LiveForge.recipe_def(sim, str(w["recipe"])).is_empty():
		w["mode"] = LiveForge.MODE
	return w


## One game minute of the bot's clock: real seconds at ×1 or skipping, a gap when it decided, the goals each hour.
func _tick(sim: Sim, now: int, decided: bool) -> void:
	if _last_minute >= 0 and now > _last_minute:
		var spm := float(sim.catalog.time.get("real_seconds_per_day", 300)) / float(Clock.MINUTES_PER_DAY)
		_clock_s += float(now - _last_minute) * spm / (SKIP if _skipping(sim) else 1.0)
	_last_minute = now
	if decided:
		if _last_decision < 0.0:
			_last_decision = _clock_s
		elif _clock_s - _last_decision >= MERGE_S:   # orders a few seconds apart are one decision (a trip's stops)
			_gaps.append(_clock_s - _last_decision)
			_last_decision = _clock_s
	if now % 60 == 0:
		_goal_samples.append(OpenGoals.view(sim, _fam(sim)).size())
	_days = Clock.day(now) - _start_day + 1


## Whether a player would be skipping now: not walking, nothing to decide, and something to wait for (its own cycle
## under way, a queued trip leg is not waiting) or the night.
func _skipping(sim: Sim) -> bool:
	var ch: Dictionary = sim.state.characters.get(ACTOR, {})
	if not (ch.get("path", []) as Array).is_empty():
		return false
	if Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) == "night":
		return true
	return Production.job_zone(sim, ACTOR, str(ch.get("location", ""))) != ""


func measures(sim: Sim) -> Dictionary:
	var m := {}
	var g := _gaps.duplicate()
	g.sort()
	m["decisions"] = _gaps.size() + (1 if _last_decision >= 0.0 else 0)
	m["gap_median_s"] = snappedf(float(g[g.size() / 2]), 0.1) if not g.is_empty() else 0.0
	m["gap_p90_s"] = snappedf(float(g[mini(g.size() - 1, int(g.size() * 0.9))]), 0.1) if not g.is_empty() else 0.0
	m["gap_max_s"] = snappedf(float(g.back()), 0.1) if not g.is_empty() else 0.0
	var gs := _goal_samples.duplicate()
	gs.sort()
	m["goals_min"] = int(gs.front()) if not gs.is_empty() else 0
	var t := 0.0
	for x: Variant in gs:
		t += float(x)
	m["goals_mean"] = snappedf(t / maxf(1.0, float(gs.size())), 0.01)
	var fam := _fam(sim)
	var u: Dictionary = sim.state.unlocks.get(fam, {}) if sim.state.unlocks.get(fam) is Dictionary else {}
	var off := 0
	var came := 0
	for d: Dictionary in Unlocks.defs(sim):
		var id := str(d["id"])
		var day := -1
		if u.get(id) is Dictionary:
			day = Clock.day(int(u[id]["minute"])) - _start_day
			came += 1
		m["unlock_%s_day" % id] = day
		if not Unlocks.ready(sim, d):
			continue
		var w: Array = d.get("window", [0, 0])
		if int(w[1]) > _days - 1:
			continue  # its window ends after the days played: not judged
		if day < 0 or day < int(w[0]) - 1 or day > int(w[1]) + 1:
			off += 1
			print("  [pacing] %s: día %d fuera de su ventana %s" % [id, day, w])
	m["unlocks_came"] = came
	m["unlocks_off"] = off
	if OS.is_debug_build():
		print("[BotPacing] decisiones=%d hueco mediana=%.1f s p90=%.1f s máx=%.1f s · metas mín=%d media=%.2f · desbloqueos=%d fuera=%d" % [
			m["decisions"], m["gap_median_s"], m["gap_p90_s"], m["gap_max_s"], m["goals_min"], m["goals_mean"], came, off])
	return m
