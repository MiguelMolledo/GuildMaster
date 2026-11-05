class_name BotFullPlayer
extends BotFestive
## The «jugador completo» (docs/gdd/07_testing.md §7.4): plays the whole game as a player with good judgement, every
## system on (life, global events, festivals, travel, duels; the inn, the games and the Forja viva when they are in
## the game), only with the player's orders and the same queries as the UI. It composes the bots that already exist
## instead of re-writing each system:
##   business (BotFestive < BotArtisanExpert < BotArtisanNovice): the debt, the forge by hand, the market, the board's
##             contracts (also the festival ones), employees and their queue, upgrades, titles (asks_titles), minor
##             offices (runs_office), festival sponsoring and the wedding banquet. Once its upgrade plan is done it adds
##             the shop counter (counter_shop) and puts an employee at it.
##   family (BotDynasty): the head courts, proposes and marries; later the heir courts with its own body. It chooses
##             the school stat (craft) and designates the best craftsman as heir.
##   town (BotGuardWatch): it answers every incident card; it resolves its microevents (the doctor for a sick
##             employee, confronting a night thief when it can, holding the price with a haggler when it can win).
##   court: once Citizen it accuses the family of a public fact against it; at a hearing of its own (accused or
##             accuser) it questions every witness and rests.
##   duels (BotDuelist): once Citizen, at most once a season, it challenges the rival when it estimates it wins;
##             it accepts a challenge with a fair chance; it plays the lances by the cue.
##   region (BotMerchant): once travel opens it sends the swords the market will not take by caravan to the capital
##             (with a cart and two employees), and once a year it travels there to open the market, sell what it
##             carries and sign a quota.
## Every DECIDE_EVERY minutes, when the head is free (at home, no trip, no cycle under way), it scores the open goals
## that need the head's body (court, duel, travel) against going on with the business and takes the best one; the
## rest are management orders given at once. Why it left a mechanic alone goes in why_not (the report).
## After the founder's death the next head (or the regent of a minor heir) takes the forge: ACTOR follows the head.

const FULL_ID: String = "full_player"
const DECIDE_EVERY: int = 15          # minutes between two looks at the open goals
const COURT_MAX_MIN: int = 240        # a courting walk gives up after this (the courted one keeps moving)
const DUEL_MAX_MIN: int = 180         # a walk to challenge gives up after this
const COURT_FROM_DAY: int = 7         # courts once the debt is paid, or from this day played (03b: end of year 1)
const DUEL_MIN_CHANCE: float = 0.5    # challenges only when it estimates it wins at least this
const DUEL_ACCEPT_CHANCE: float = 0.4 # accepts a challenge with at least this (the NPC's own bar)
const CITY: String = "capital"
const TRIP_SWORDS: int = 3            # swords it carries on a trip to open the market
const TRIP_SPARE: int = 120           # gold kept at home on top of the reserve before a trip
const TRIP_EVERY_DAYS: int = 8        # a trip to the capital at most once a year
const CARAVAN_SWORDS: int = 4         # swords waiting in the storage before a caravan
const CARAVAN_MIN_PRICE: int = 30     # the caravan's minimum unit price in the capital
const CARAVAN_STAFF: int = 2          # employees it needs to spare one as carter
const CART_SPARE: int = 150           # gold kept after buying a cart
const ACCUSE_EVERY: int = 1440        # one look a day for a fact to accuse with
const UTIL: Dictionary = {"court": 0.7, "travel": 0.5, "duel": 0.4, "business": 0.3}  # utility of each goal

var dyn: BotDynasty = BotDynasty.new()
var guard: BotGuardWatch = BotGuardWatch.new()
var duelist: BotDuelist = BotDuelist.new()
var merchant: BotMerchant = BotMerchant.new()

var goals: int = 1                    # trials (BOT_VARS=goals=0): 0 = never leaves the business for a goal
var focus: String = "business"        # what the head's body does: business | court | duel | travel
var why_not: Dictionary = {}          # mechanic -> why it did not use it the last time it looked
var used: Dictionary = {}             # mechanic -> times it went for it
var focus_minutes: Dictionary = {}    # focus -> minutes
var decisions: Array = []             # [{day, minute, what, detail}] the focus changes and key choices (report)
var heads: Array = []                 # every character that played the forge, in order
var _fam_id: String = ""
var _focus_since: int = 0
var _next_look: int = -1
var _duel_season: int = -1000
var _duel_why: String = ""           # the season's verdict on a challenge ("" = it went)
var _last_trip_day: int = -1000
var _trip_stage: String = ""          # travel: "" | "pack" | "out"
var _answered: Dictionary = {}
var _mev_done: Dictionary = {}
var _next_accuse: int = -1
var _next_family: int = -1
var _start_day: int = -1


func _init() -> void:
	runs_office = 1


func orders(sim: Sim) -> Array:
	var st := sim.state
	if _fam_id == "":
		_fam_id = Life.player_family(st)
		dyn.fam = _fam_id
		_start_day = Clock.day(_now(sim))
	var out: Array = []
	for o: Dictionary in guard.orders(sim):  # reads the step's events every minute; answers the incident cards
		var who := str(o.get("actor", ""))
		if Region.is_away(st, who):  # the head is away: whoever is at home answers (else the card waits)
			who = _home_adult(sim)
			if who == "":
				continue
			o["actor"] = who
		out.append(o)
	dyn._watch(sim)
	if _fam_id == "" or not st.ending.is_empty():
		return out
	_sync_actor(sim)
	if not Kin.alive(st, ACTOR):
		return out
	focus_minutes[focus] = int(focus_minutes.get(focus, 0)) + 1
	out.append_array(_always(sim))
	for o: Dictionary in out:
		if str(o.get("type", "")) == "resolve_microevent":  # a card answered may sell or move what the body would
			_watch(sim)                                     # carry this same minute: the body waits a minute
			return out
	if Region.is_away(st, ACTOR):
		_watch(sim)
		out.append_array(_away(sim))
		return out
	if _trip_stage == "out":  # back home: the trip is over
		_end_focus(sim, "travel", "back home")
	if Duels.holds(st, ACTOR):  # called to the ground or fighting: nothing else for the head
		_watch(sim)
		return out
	if focus == "business" and goals == 1 and _now(sim) >= _next_look and _free(sim):
		_next_look = _now(sim) + DECIDE_EVERY
		_decide(sim)
	var body: Array = []
	match focus:
		"court":
			body = _court_step(sim)
		"duel":
			body = _duel_step(sim)
		"travel":
			body = _travel_step(sim)
	if focus == "business":
		out.append_array(super.orders(sim))
	else:
		_watch(sim)  # the festive counters read every step
		out.append_array(body)
	return out


## Who plays the forge: the head, or the regent while the heir is a minor.
func _sync_actor(sim: Sim) -> void:
	var st := sim.state
	var h := Kin.head(st, _fam_id)
	var who := h
	if h != "" and not Kin.is_adult(sim, h):
		var regent := str(st.families[_fam_id].get("regent", ""))
		if regent != "" and Kin.alive(st, regent):
			who = regent
	if heads.is_empty():
		heads.append(ACTOR)
	if who == "" or who == ACTOR or not Kin.alive(st, who):
		return
	_note(sim, "new_head", "%s -> %s" % [ACTOR, who])
	ACTOR = who
	heads.append(who)
	_trip = []
	_idle_until = -1
	focus = "business"
	_trip_stage = ""


# --- Every minute: management that needs no walk -------------------------------------------------------------------

func _always(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var mine := Duels.of_character(st, ACTOR)
	if not mine.is_empty():
		if str(mine["status"]) == Duels.FIGHTING and int(mine["player_side"]) >= 0:
			out.append(duelist._lance(sim, mine, ACTOR))
		elif str(mine["status"]) == Duels.PENDING and str(mine["challenged"]) == ACTOR \
				and not _answered.has(str(mine["id"])):
			_answered[str(mine["id"])] = true
			var p := Duels.win_chance(sim, ACTOR, str(mine["challenger"]), str(mine["id"]), str(mine["kind"]))
			var ans := "accept" if p >= DUEL_ACCEPT_CHANCE and not Region.is_away(st, ACTOR) else "refuse"
			_note(sim, "duel_answer", "%s (%.2f)" % [ans, p])
			out.append({"type": "duel_answer", "actor": ACTOR, "duel": str(mine["id"]), "answer": ans})
	if Region.is_away(st, ACTOR):
		return out
	out.append_array(_microevents(sim))
	if _now(sim) >= _next_family:
		_next_family = _now(sim) + 60
		out.append_array(_family(sim))
	if _now(sim) >= _next_accuse:
		_next_accuse = _now(sim) + ACCUSE_EVERY
		var o := _accuse(sim)
		if not o.is_empty():
			out.append(o)
	var suitor := dyn._suitor(sim)
	if suitor != "" and suitor != ACTOR and not Region.is_away(st, suitor):  # the heir courts with its own body
		for o: Dictionary in dyn.orders(sim):
			if str(o.get("type", "")) == "court_talk" and int((st.relationships.get(Ids.pair_key(suitor,
					str(o["target"])), {}) as Dictionary).get("talk_day", -1)) == _today(sim):  # a read: never relation()
				continue  # they already talked today (in the town's own life): the order would be refused
			out.append(o)
	if _business(sim) and focus != "travel":  # packing for a trip takes the same swords: no caravan meanwhile
		var c := _caravan(sim)
		if not c.is_empty():
			out.append(c)
		if counter_shop == 0 and _plan_done(sim):
			counter_shop = 1  # the H5 plan is done: the shop counter comes next (forge_commerce_1, an employee at it)
			_note(sim, "counter", "plan done: the counter is next")
	return out


## The cards of its microevents, answered like a careful player (the default is what the timeout would do).
func _microevents(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	for m: Dictionary in Microevents.active_for(sim, _fam_id):
		var id := str(m["id"])
		if _mev_done.has(id):
			continue
		_mev_done[id] = true
		var choices: Array = m.get("choices", [])
		var pick := str(m.get("default", ""))
		var stats: Dictionary = st.characters[ACTOR].get("stats", {})
		match str(m["def"]):
			"sick_employee":
				pick = "doctor" if Money.gold(st, _fam_id) >= _reserve(sim) + 10 else "day_off"
			"night_thief":
				pick = "confront" if int(stats.get("martial", 0)) >= 5 else "let"
			"haggling_customer":
				pick = "hold" if int(stats.get("charisma", 0)) >= 6 else "accept"
		if not pick in choices:
			pick = str(choices[0]) if not choices.is_empty() else ""
		if pick == "":
			continue
		_use("microevents")
		out.append({"type": "resolve_microevent", "actor": ACTOR, "microevent": id, "choice": pick})
	return out


## School choice (craft: the heir will forge) and the heir: the best craftsman among those who can inherit.
func _family(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var h := Kin.head(st, _fam_id)
	for m: Variant in st.families[_fam_id].get("members", []):
		var c := str(m)
		if Kin.alive(st, c) and str(st.characters[c].get("life", {}).get("school", "")) == "pending":
			_use("school")
			out.append({"type": "school_choice", "actor": ACTOR, "child": c, "stat": "craft"})
	if h == "":
		return out
	var best := ""
	var key: Array = []
	for d: String in Kin.descendants(st, h):
		if not Kin.can_inherit(sim, h, d):
			continue
		var k := [0 if Kin.is_adult(sim, d) else 1, -int(st.characters[d].get("stats", {}).get("craft", 0)),
			int(st.characters[d].get("birth_day", 0))]
		if best == "" or BotDynasty._before(k, key):
			best = d
			key = k
	if best != "" and str(st.families[_fam_id].get("heir", "")) != best:
		_use("heir")
		_note(sim, "heir", best)
		out.append({"type": "designate_heir", "actor": ACTOR, "heir": best})
	return out


## Once Citizen: a public fact against another family is a case (the trial costs it nothing if it loses).
func _accuse(sim: Sim) -> Dictionary:
	var st := sim.state
	if not Tribunal.of_family(sim, _fam_id).is_empty() or not Tribunal.of_family(sim, _fam_id, true).is_empty():
		return {}
	var fams: Array = st.families.keys()
	fams.sort()
	var seen := false
	for f: String in fams:
		if f == _fam_id:
			continue
		for fa: Dictionary in Tribunal.facts_against(sim, f):
			seen = true
			var target := Kin.head(st, f)
			var why := Tribunal.accuse_status(sim, ACTOR, target, str(fa["id"]), "", false)
			if why == "":
				_use("tribunal")
				_note(sim, "accuse", "%s (%s)" % [f, fa.get("kind", "")])
				return {"type": "accuse", "actor": ACTOR, "target": target, "fact": str(fa["id"])}
			why_not["tribunal"] = why
	if not seen:
		why_not["tribunal"] = "no_fact"
	return {}


## The expert's hearing hook, for any trial of its family (accused or accuser): question every witness, then rest.
func _court(sim: Sim) -> Dictionary:
	for t: Dictionary in [Tribunal.of_family(sim, _fam(sim)), Tribunal.of_family(sim, _fam(sim), true)]:
		if t.is_empty() or str(t["status"]) != "hearing":
			continue
		for w: Dictionary in t["witnesses"]:
			if Tribunal.cross_status(sim, ACTOR, str(t["id"]), str(w["character"])) == "":
				_use("tribunal")
				return {"type": "trial_cross", "actor": ACTOR, "trial": str(t["id"]), "witness": str(w["character"])}
		if Tribunal.hearing_status(sim, ACTOR, str(t["id"])) == "":
			return {"type": "trial_rest", "actor": ACTOR, "trial": str(t["id"])}
	return {}


## Swords the town market does not take go to the capital by caravan (a cart once there are spare swords).
func _caravan(sim: Sim) -> Dictionary:
	var st := sim.state
	if _now(sim) % 30 != 0:
		return {}
	if Travel.unlock_reason(sim, _fam_id) != "":
		why_not["caravans"] = "title_needed"
		return {}
	var spare := _spare_swords(sim)
	var cart_price := int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
	if Caravans.carts(sim, _fam_id) == 0:
		if spare < CARAVAN_SWORDS:
			why_not["caravans"] = "market_takes_them"
			return {}
		if Money.gold(st, _fam_id) < cart_price + CART_SPARE + _reserve(sim):
			why_not["caravans"] = "cart_too_dear"
			return {}
		_use("caravans")
		_note(sim, "buy_cart", "%d swords spare" % spare)
		return {"type": "buy_cart", "actor": ACTOR}
	if Caravans.busy_carts(sim, _fam_id) >= Caravans.carts(sim, _fam_id) or spare < CARAVAN_SWORDS:
		return {}
	var staff := _active_staff(sim)
	if staff.size() < CARAVAN_STAFF:
		why_not["caravans"] = "no_spare_carter"
		return {}
	staff.sort()
	var o := {"type": "caravan_send", "actor": ACTOR, "driver": str(staff[-1]), "building": FORGE, "city": CITY,
		"cargo": [{"item": "sword", "quality": Inventory.NORMAL, "qty": spare, "min_price": CARAVAN_MIN_PRICE}],
		"buy": [], "escort": false}
	var why := Caravans.can_send(sim, o)
	if why != "":
		why_not["caravans"] = why
		return {}
	_use("caravans")
	_note(sim, "caravan", "%d swords to %s" % [spare, CITY])
	return o


## Normal swords in the storage the market would not take now (demand below the expert's bar), less the contracts'.
func _spare_swords(sim: Sim) -> int:
	if Market.demand(sim, "sword") >= EXPERT_MIN_DEMAND:
		return 0
	var n := Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword", Inventory.NORMAL)
	return maxi(0, n - int(_reserved(sim).get("sword|%d" % Inventory.NORMAL, 0)))


## The novice's check reads deadline_days, but a festival contract falls due when its feast ends (due_at): with the
## days rounded up it accepted pieces it could not make in time (BUG of the bots' habit, 07 §7.4). Here the hours
## left are the real ones, and the employees' hands do not count (their queue never takes festival pieces).
func _can_make_in_time(sim: Sim, c: Dictionary) -> bool:
	if int(c.get("due_at", -1)) < 0:
		return super._can_make_in_time(sim, c)
	var rid := _recipe_for(sim, str(c["item"]))
	if rid == "" or _status(sim, ANVIL, rid) == "locked":
		return false
	var hours := _contract_hours(sim, c)
	for a: Dictionary in Contracts.accepted_of(sim, _fam(sim)):
		hours += _contract_hours(sim, a)
	var left := float(int(c["due_at"]) - _now(sim)) / 60.0
	if hours > left * 0.6:
		why_not["festival_contracts"] = "no_time"
		return false
	return true


## The expert's counter trial puts its least skilled hand at the counter even when it is the only one: the queue then
## stands still (measured: 67 gold of counter sales in six days against a wage of 20 a day). The full player serves at
## the counter only with two or more employees.
func _roles(sim: Sim) -> Dictionary:
	var keep := counter_shop
	if _active_staff(sim).size() < 2:
		counter_shop = 0
		if keep == 1:
			why_not["counter"] = "one_employee"
	var o := super._roles(sim)
	counter_shop = keep
	if str(o.get("role", "")) == "counter":
		_use("counter")
	return o


# --- The head's body: what it goes for ---------------------------------------------------------------------------

## Free for an errand of its own: at home, no trip of the business, no cycle under way, nothing queued nor walking.
func _free(sim: Sim) -> bool:
	var ch: Dictionary = sim.state.characters[ACTOR]
	return _trip.is_empty() and not _busy(sim) and (ch.get("order_queue", []) as Array).is_empty() \
		and (ch.get("path", []) as Array).is_empty() and str(ch.get("location", "")) == FORGE \
		and Clock.phase(_now(sim), sim.catalog.time) == "day"


## Scores the goals that need the head and takes the best one over the business.
func _decide(sim: Sim) -> void:
	var best := "business"
	var score := float(UTIL["business"])
	for g: String in ["court", "travel", "duel"]:
		var why := ""
		match g:
			"court":
				why = _court_ready(sim)
			"travel":
				why = _travel_ready(sim)
			"duel":
				why = _duel_ready(sim)
		var mech := {"court": "courtship", "travel": "travel", "duel": "duels"}[g] as String
		if why != "":
			why_not[mech] = why
			continue
		if float(UTIL[g]) > score:
			score = float(UTIL[g])
			best = g
	if best != "business":
		focus = best
		_focus_since = _now(sim)
		_trip_stage = ""
		_note(sim, "focus", best)


func _end_focus(sim: Sim, what: String, why: String) -> void:
	if focus == what:
		_note(sim, "focus_end", "%s: %s" % [what, why])
	focus = "business"
	_trip_stage = ""
	_idle_until = -1


## "" if the head should court now: single without heir, someone to court, once a day, after the debt (or late).
func _court_ready(sim: Sim) -> String:
	var suitor := dyn._suitor(sim)
	if suitor == "":
		return "married" if not Kin.is_single(sim.state, ACTOR) else "no_suitor"
	if suitor != ACTOR:
		return "heir_courts"
	if int(dyn.talked.get(suitor, -1)) == _today(sim):
		return "talked_today"
	if not _business(sim) and _played(sim) < COURT_FROM_DAY:
		return "debt_first"
	if _active_staff(sim).is_empty() and _played(sim) < COURT_FROM_DAY:
		return "forge_needs_the_head"  # alone, every hour away is an hour the forge stands still
	if Money.gold(sim.state, _fam_id) < _reserve(sim) + int(Upkeep.due_next_dawn(sim, _fam_id)["total"]):
		return "gold_short"  # the forge first: courting with an empty purse stops the raw materials
	if dyn._target(sim, suitor) == "":
		return "no_candidate"
	return ""


func _court_step(sim: Sim) -> Array:
	if _now(sim) - _focus_since > COURT_MAX_MIN:
		why_not["courtship"] = "gave_up_walking"
		_end_focus(sim, "court", "too long")
		return []
	if dyn._suitor(sim) != ACTOR or int(dyn.talked.get(ACTOR, -1)) == _today(sim):
		_end_focus(sim, "court", "talked")
		return []
	var pack := _pack_gift(sim)
	if not pack.is_empty():
		return [pack]
	var o := dyn.orders(sim)
	for x: Dictionary in o.duplicate():
		if str(x["type"]) in ["court_talk", "propose"]:
			_use("courtship")
		if str(x["type"]) == "court_talk":  # one gift a visit: the piece of its bag worth the most affinity
			var g := _gift(sim, str(x["target"]))
			if not g.is_empty():
				o.append(g)
	return o


## Before setting out to court: one finished piece from the storage into the bag (the one worth most affinity), if
## the bag has none and an accepted contract does not need it.
func _pack_gift(sim: Sim) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	if str(ch.get("location", "")) != FORGE or _now(sim) - _focus_since > 5:
		return {}
	for s: Dictionary in ch["inventory"].get("stacks", []):
		if str(sim.catalog.item(str(s["item"])).get("market_stall", "")) == ARMORY_STALL:
			return {}
	var keep := _reserved(sim)
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var best := {}
	var key := [0, 0]
	for s: Dictionary in inv.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		if str(sim.catalog.item(item).get("market_stall", "")) != ARMORY_STALL \
				or Inventory.count(inv, item, q) <= int(keep.get("%s|%d" % [item, q], 0)) \
				or not Inventory.can_add(ch["inventory"], sim.catalog, item, q, 1):
			continue
		var val := Market.price(sim, item, q, "sell")
		var k := [-_gift_points(sim, val), val]
		if best.is_empty() or BotDynasty._before(k, key):
			key = k
			best = {"type": "transfer", "actor": ACTOR, "from": FORGE, "to": ACTOR, "item": item, "quality": q, "qty": 1}
	return best


func _gift_points(sim: Sim, value: int) -> int:
	var cfg: Dictionary = sim.catalog.family.get("courtship", {}).get("gift", {})
	return clampi(roundi(float(value) / maxf(1.0, float(cfg.get("gold_per_point", 2)))), int(cfg.get("min", 5)),
		int(cfg.get("max", 15)))


## The gift of a visit: the item of the bag that gives the most affinity (the gift's value / gold_per_point within
## [min, max] of data/family.json), the cheaper on a tie; never what an accepted contract needs. {} if none.
func _gift(sim: Sim, target: String) -> Dictionary:
	var cfg: Dictionary = sim.catalog.family.get("courtship", {}).get("gift", {})
	var keep := _reserved(sim)
	var best := {}
	var best_pts := 0
	var best_val := 0
	for s: Dictionary in sim.state.characters[ACTOR]["inventory"].get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		if int(keep.get("%s|%d" % [item, q], 0)) > 0 or item in RAW:
			continue  # the raw materials are the forge's; contract pieces are promised
		var val := Market.price(sim, item, q, "sell")
		var pts := clampi(roundi(float(val) / maxf(1.0, float(cfg.get("gold_per_point", 2)))), int(cfg.get("min", 5)),
			int(cfg.get("max", 15)))
		if pts > best_pts or (pts == best_pts and val < best_val):
			best = {"type": "court_gift", "actor": ACTOR, "target": target, "item": item, "quality": q}
			best_pts = pts
			best_val = val
	if not best.is_empty():
		_use("courtship_gift")
	return best


## "" if a challenge is worth it: Citizen (03b), once a season, a rival it has a cause against and beats.
func _duel_ready(sim: Sim) -> String:
	if Titles.rank(sim, Titles.current(sim, _fam_id)) < Titles.rank(sim, "citizen"):
		return "title_needed"
	var season := _today(sim) / int(sim.catalog.time.get("days_per_season", 2))
	if season == _duel_season:
		return _duel_why if _duel_why != "" else "this_season"
	_duel_season = season  # one estimate a season (win_chance plays samples of duels): its verdict holds the season
	var target := duelist._target(sim, ACTOR)
	_duel_why = ""
	if target == "":
		_duel_why = "no_cause"
	else:
		var p := Duels.win_chance(sim, ACTOR, target, "fp_%d" % season, "first_blood")
		if p < DUEL_MIN_CHANCE:
			_duel_why = "low_chance_%.2f" % p
	return _duel_why


func _duel_step(sim: Sim) -> Array:
	if not Duels.of_character(sim.state, ACTOR).is_empty():
		_use("duels")
		_end_focus(sim, "duel", "challenged")
		return []
	if _now(sim) - _focus_since > DUEL_MAX_MIN:
		why_not["duels"] = "gave_up_walking"
		_end_focus(sim, "duel", "too long")
		return []
	return duelist.orders(sim)


## "" if a trip to the capital is worth it now: travel open, a reason (open its market or sign a quota), swords to
## carry or a quota to sign, gold for the road on top of the reserve, no contract due at home soon, once a year.
func _travel_ready(sim: Sim) -> String:
	var why := Travel.can_travel(sim, ACTOR, CITY)
	if why != "":
		return why
	if not _business(sim):
		return "debt_first"
	if _today(sim) - _last_trip_day < TRIP_EVERY_DAYS:
		return "went_this_year"
	merchant._hero = ACTOR
	merchant._forge = FORGE
	if not merchant._wants_trip(sim, _fam_id):
		return "nothing_to_do_there"
	var first := int((Region.ensure(sim)["stats"] as Dictionary).get(_fam_id, {}).get("arrivals", 0)) == 0
	var swords := Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword", Inventory.NORMAL) \
		- int(_reserved(sim).get("sword|%d" % Inventory.NORMAL, 0))
	if first and swords < TRIP_SWORDS:
		return "no_swords_to_carry"
	if Money.gold(sim.state, _fam_id) < _reserve(sim) + TRIP_SPARE:
		return "gold_for_the_road"
	for c: Dictionary in _contracts_by_due(sim):
		if int(c["due"]) - _now(sim) < 2 * Clock.MINUTES_PER_DAY:
			return "contract_due"
	return ""


func _travel_step(sim: Sim) -> Array:
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	if _trip_stage == "":
		_trip_stage = "pack"
	if _now(sim) - _focus_since > 120 and _trip_stage == "pack":
		why_not["travel"] = "could_not_leave"
		_end_focus(sim, "travel", "could not leave")
		return []
	if str(ch.get("location", "")) != FORGE:
		return [{"type": "enter_building", "actor": ACTOR, "building": FORGE}] if str(ch.get("location", "")) == "" \
			else [{"type": "exit_building", "actor": ACTOR}]
	if Production.job_zone(sim, ACTOR, FORGE) != "":
		return [{"type": "stop_work", "actor": ACTOR}]
	var spare := Inventory.count(st.buildings[FORGE]["inventory"], "sword", Inventory.NORMAL) \
		- int(_reserved(sim).get("sword|%d" % Inventory.NORMAL, 0))
	var n := mini(TRIP_SWORDS, Inventory.fit_count(ch["inventory"], sim.catalog, "sword", Inventory.NORMAL, maxi(spare, 0)))
	if n > 0 and Inventory.count(ch["inventory"], "sword", Inventory.NORMAL) < TRIP_SWORDS:
		return [{"type": "transfer", "actor": ACTOR, "from": FORGE, "to": ACTOR, "item": "sword",
			"quality": Inventory.NORMAL, "qty": n}]
	var why := Travel.can_travel(sim, ACTOR, CITY)
	if why != "":
		why_not["travel"] = why
		_end_focus(sim, "travel", why)
		return []
	_trip_stage = "out"
	_last_trip_day = _today(sim)
	_use("travel")
	_note(sim, "travel", CITY)
	return [{"type": "travel", "actor": ACTOR, "to": CITY}]


## Away from home: on the road nothing; in the capital deliver, sell, take only a contract it can deliver at once,
## sign the quota, and back.
func _away(sim: Sim) -> Array:
	var st := sim.state
	if Travel.in_city(st, ACTOR) != CITY:
		return []
	if (st.characters[ACTOR].get("order_queue", []) as Array).size() > 0:
		return []
	var inv: Dictionary = st.characters[ACTOR]["inventory"]
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == _fam_id and str(a["city"]) == CITY and Inventory.count(inv, str(a["item"])) >= int(a["qty"]):
			return [{"type": "city_deliver", "actor": ACTOR, "contract": a["id"]}]
	for off: Dictionary in Region.city(sim, CITY)["board"]:
		if Inventory.count(inv, str(off["item"])) >= int(off["qty"]) and not _city_contract(sim):
			_use("city_contracts")
			return [{"type": "city_accept", "actor": ACTOR, "contract": off["id"]}]
	var swords := Inventory.count(inv, "sword", Inventory.NORMAL)
	if swords > 0:
		_use("city_market")
		return [{"type": "city_sell", "actor": ACTOR, "item": "sword", "quality": Inventory.NORMAL, "qty": swords}]
	if Treaties.quota_of(sim, CITY, _fam_id, "sword").is_empty():
		var why := Treaties.can_sign(sim, _fam_id, CITY, "quota", "sword")
		if why == "":
			_use("treaties")
			_note(sim, "treaty", "quota sword " + CITY)
			return [{"type": "sign_treaty", "actor": ACTOR, "kind": "quota", "item": "sword"}]
		why_not["treaties"] = why
	if Travel.can_travel(sim, ACTOR, Region.home(sim)) == "":
		return [{"type": "return", "actor": ACTOR}]
	return []


## An adult of the family's group at home (not away), "" if none.
func _home_adult(sim: Sim) -> String:
	for c: String in Kin.group(sim.state, _fam_id):
		if Kin.is_adult(sim, c) and not Region.is_away(sim.state, c):
			return c
	return ""


func _city_contract(sim: Sim) -> bool:
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == _fam_id:
			return true
	return false


# --- Bookkeeping for the report -----------------------------------------------------------------------------------

func _use(mech: String) -> void:
	used[mech] = int(used.get(mech, 0)) + 1
	why_not.erase(mech)


func _note(sim: Sim, what: String, detail: String) -> void:
	if decisions.size() < 400:
		decisions.append({"day": _played(sim), "minute": Clock.minute_of_day(_now(sim)), "what": what, "detail": detail})
	if OS.is_debug_build():
		print("[BotFull] día %d %s: %s (oro=%d)" % [_played(sim), what, detail, Money.gold(sim.state, _fam_id)])


func _played(sim: Sim) -> int:
	return _today(sim) - _start_day + 1


func measures(sim: Sim) -> Dictionary:
	var m := super.measures(sim)
	m.merge(dyn.measures(sim))
	m.merge(guard.measures(sim))
	for f: String in focus_minutes:
		m["focus_%s_minutes" % f] = int(focus_minutes[f])
	m["heads"] = heads.size()
	return m


## What the report needs that is not a number: the reasons, the uses, the decisions, the heads.
func report(_sim: Sim) -> Dictionary:
	return {"why_not": why_not.duplicate(), "used": used.duplicate(), "decisions": decisions.duplicate(true),
		"heads": heads.duplicate(), "focus_minutes": focus_minutes.duplicate()}
