class_name BotRogueNovice
extends RefCounted
## Bot rogue_novice (docs/gdd/04d_otras_clases.md §4.22.6.14 «thief»; H12, the Rogue's first trade): the thief of a new
## game rogue_thief, playing like a careful novice through the same orders as the UI. By day and at dusk he picks purses
## in the streets (the nearest person of another family with no guard in view of her, at most picks_per_day); at night
## he robs one storage whose door no guard sees; he takes the loot to his den, sells it to the fence up to the town's
## cap and launders what is left; he repays the debt when he can. Caught, he answers the arrest card: bribe if he can
## spare it, else surrender. Measures: picks, picks_ok, burgles, burgles_ok, fenced_gold, laundered, arrests, trials.

const ID: String = "rogue_novice"
const PICKS_PER_DAY: int = 8
const SEEK_TILES: int = 14
const DEBT_RESERVE: int = 20
const BURGLE_HOURS: int = 2  # sleep and food: the night's burglary only in its first hours, then home to sleep

var fam: String = ""
var me: String = ""
var m: Dictionary = {}
var _day: int = -1
var _picks: int = 0
var _burgled_night: int = -1
var _last: String = ""


func _add(k: String, n: int = 1) -> void:
	m[k] = int(m.get(k, 0)) + n


func measures(_sim: Sim) -> Dictionary:
	var out := {}
	for k: String in ["picks", "picks_ok", "burgles", "burgles_ok", "fenced_gold", "laundered", "arrests", "trials"]:
		out[k] = int(m.get(k, 0))
	return out


func orders(sim: Sim) -> Array:
	var st := sim.state
	if fam == "":
		fam = SimQuery.player_family(st)
		me = Kin.head(st, fam)
	_watch(sim)
	if me == "" or not Kin.alive(st, me) or Tribunal.is_banished(st, me) or Region.is_away(st, me):
		return []
	var arrest := Rogue.pending_arrest(st, me)
	if not arrest.is_empty():
		var odds := Rogue.arrest_odds(sim, me, str(arrest["guard"]))
		var bribe := Money.gold(st, fam) >= int(odds["bribe_price"]) + 60 and float(odds["bribe"]) >= 0.5
		return [{"type": "arrest_response", "actor": me, "choice": "bribe" if bribe else "surrender"}]
	var ch: Dictionary = st.characters[me]
	if not (ch.get("path", []) as Array).is_empty() or not (ch.get("order_queue", []) as Array).is_empty():
		return []
	var day := Clock.day(int(st.clock["minute"]))
	if day != _day:
		_day = day
		_picks = 0
	var o := _repay(sim)
	if not o.is_empty():
		return [o]
	var ph := Clock.phase(int(st.clock["minute"]), sim.catalog.time)
	var den := Rogue.den_of(st, fam)
	var night := _night(sim)  # sleep and food: one burglary a night (the night spans midnight), then to bed
	if _carries_stolen(sim) and (ph in ["dawn", "night"] and _burgled_night == night or ph == "dawn" \
			or (ph == "dusk" and _picks >= PICKS_PER_DAY)):
		return _at_den(sim, den)
	if ph in ["day", "dusk"] and _picks < PICKS_PER_DAY:
		o = _pick(sim)
		if not o.is_empty():
			return [o]
	if ph == "night" and _burgled_night != night \
			and int(st.clock["minute"]) - NeedsRoutine.night_start(sim, int(st.clock["minute"])) > BURGLE_HOURS * 60:
		_burgled_night = night  # sleep and food: no storage within the first hours of the night: to bed (the Rutina)
	if ph == "night" and _burgled_night != night:
		o = _burgle(sim)
		if not o.is_empty():
			o["manual"] = true  # sleep and food: the night's burglary is ordered over the Rutina (NeedsRoutine.bot_filter)
			return [o]
	if _carries_stolen(sim) or str(ch.get("location", "")) != den:
		return _at_den(sim, den)
	return []


# --- What happened -----------------------------------------------------------------------------------------------------

func _watch(sim: Sim) -> void:
	for e: Dictionary in sim.events:
		if str(e.get("family", "")) != fam:
			continue
		match str(e.get("type", "")):
			"pickpocket_done":
				_add("picks")
				_add("picks_ok")
			"pickpocket_failed":
				_add("picks")
			"burgle_done":
				_add("burgles")
				_add("burgles_ok")
			"burgle_failed":
				_add("burgles")
			"fence_sold":
				_add("fenced_gold", int(e.get("gold", 0)))
			"launder_done":
				_add("laundered")
			"rogue_arrest_card", "rogue_arrested":
				if str(e.get("type", "")) == "rogue_arrest_card" or not m.has("_card"):
					_add("arrests")
			"trial_opened":
				_add("trials")


# --- Debt ------------------------------------------------------------------------------------------------------------

func _repay(sim: Sim) -> Dictionary:
	var gold := Money.gold(sim.state, fam)
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if not str(s["state"]) in ["active", "extended"]:
			continue
		var owed := int(s["outstanding"])
		if gold >= owed + DEBT_RESERVE:
			return {"type": "repay_loan", "actor": me, "loan": id, "amount": owed}
		if int(s["days_left"]) <= 1 and gold > 5:
			return {"type": "repay_loan", "actor": me, "loan": id, "amount": mini(owed, gold - 5)}
	return {}


# --- By day: purses ----------------------------------------------------------------------------------------------------

func _pick(sim: Sim) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[me]
	if str(ch.get("location", "")) != "":
		return {"type": "exit_building", "actor": me}
	var here := Life.tile_of(st, me)
	var best := ""
	var best_d := 1 << 20
	var dex := SkillCheck.stat(sim, me, "dexterity")
	for c: String in Festivals._sorted_keys(st.characters):
		if Rogue.pickpocket_reason(sim, me, c) != "":
			continue
		var emp := SkillCheck.stat(sim, c, "empathy")
		if emp > dex:  # a careful novice: not somebody who sees him coming
			continue
		var t := Life.tile_of(st, c)
		var d := Life.dist(here, t) + emp * 2
		if Life.dist(here, t) > SEEK_TILES or d >= best_d or Rogue.guard_in_view(sim, t) != "":
			continue
		best = c
		best_d = d
	if best == "":
		return {}
	if Life.dist(here, Life.tile_of(st, best)) <= int((sim.catalog.rogue.get("pickpocket", {}) as Dictionary).get("range", 1)):
		_picks += 1
		return {"type": "pickpocket", "actor": me, "target": best}
	return _move(sim, Life.tile_of(st, best))


# --- At night: a storage -----------------------------------------------------------------------------------------------

func _burgle(sim: Sim) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[me]
	var here := Life.tile_of(st, me)
	var best := ""
	var best_v := -1
	for b: String in Festivals._sorted_keys(st.buildings):
		if Rogue.burgle_reason(sim, me, b) != "":
			continue
		var door: Array = st.buildings[b].get("door", [])
		if door.size() != 2 or Rogue.guard_in_view(sim, door) != "":
			continue
		var v := _store_value(sim, b) - Rogue.lock_of(sim, b) * 10
		if v > best_v:
			best = b
			best_v = v
	if best == "":
		_burgled_night = _night(sim)  # nothing worth it tonight
		return {}
	if str(ch.get("location", "")) != "":
		return {"type": "exit_building", "actor": me}
	var door: Array = st.buildings[best]["door"]
	if Life.dist(here, door) <= 1:
		_burgled_night = _night(sim)
		return {"type": "burgle", "actor": me, "building": best}
	return _move(sim, door)


## The night of now: the day it began (after midnight, still the night before).
func _night(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]) - 6 * 60)


func _store_value(sim: Sim, b: String) -> int:
	var v := 0
	for s: Dictionary in sim.state.buildings[b].get("inventory", {}).get("stacks", []):
		if not Rogue.is_stolen(str(s["item"])):
			v += int(sim.catalog.item(str(s["item"])).get("base_price", 0)) * mini(int(s["qty"]), 3)
	return v


# --- The den: the fence and the bench ----------------------------------------------------------------------------------

func _carries_stolen(sim: Sim) -> bool:
	for s: Dictionary in sim.state.characters[me].get("inventory", {}).get("stacks", []):
		if Rogue.is_stolen(str(s["item"])):
			return true
	return false


func _at_den(sim: Sim, den: String) -> Array:
	var st := sim.state
	if den == "":
		return []
	var ch: Dictionary = st.characters[me]
	if str(ch.get("location", "")) != den:
		if str(ch.get("location", "")) != "":
			return [{"type": "exit_building", "actor": me}]
		return [{"type": "enter_building", "actor": me, "building": den}]
	for s: Dictionary in ch.get("inventory", {}).get("stacks", []):
		var it := str(s["item"])
		if not Rogue.is_stolen(it):
			continue
		var key := "fence|%s|%d|%d" % [it, int(s["quality"]), _day]
		if _last != key:
			_last = key
			return [{"type": "fence_sell", "actor": me, "item": it, "quality": int(s["quality"]), "qty": int(s["qty"])}]
		if not st.buildings[den].get("laundering") is Dictionary \
				and SkillCheck.stat(sim, me, "dexterity") >= int((sim.catalog.rogue.get("launder", {}) as Dictionary).get("min_dexterity", 5)):
			return [{"type": "launder", "actor": me, "building": den, "item": it, "quality": int(s["quality"])}]
	return []


func _move(sim: Sim, tile: Array) -> Dictionary:
	return {"type": "move_to", "actor": me, "tile": [int(tile[0]), int(tile[1])]}
