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
const TRIP_SWORDS: int = 3            # swords it carries on a trip to open the market (the quota's reputation, 3)
const TRIP_SPARE: int = 120           # gold kept at home on top of the reserve before a trip
const TRIP_EVERY_DAYS: int = 8        # a trip to the capital at most once a year
const CARAVAN_SWORDS: int = 4         # swords waiting in the storage before a caravan
const CARAVAN_MIN_PRICE: int = 30     # the caravan's minimum unit price in the capital
const CARAVAN_STAFF: int = 2          # employees it needs to spare one as carter
const CART_SPARE: int = 150           # gold kept after buying a cart
const ACCUSE_EVERY: int = 1440        # one look a day for a fact to accuse with
const INN_SPARE: int = 200           # gold kept on top of the reserve after buying the Taberna-Posada
const BET_STAKE: int = 5              # a bet at a festival's competition: the smallest stake (data/games.json stakes)
const BET_SPARE: int = 100            # gold kept on top of the reserve before a bet
const ENTER_EDGE: float = 1.2         # enters a festival competition when its chance beats the field's mean by this
const ODDS_SAMPLES: int = 30          # automatic games of the estimate (Games.win_odds)
const UTIL: Dictionary = {"court": 0.7, "travel": 0.5, "duel": 0.4, "business": 0.3}  # utility of each goal

var dyn: BotDynasty = BotDynasty.new()
var guard: BotGuardWatch = BotGuardWatch.new()
var duelist: BotDuelist = BotDuelist.new()
var merchant: BotMerchant = BotMerchant.new()
var inn: BotInnkeeper = null          # posada (04f §4.27): the Taberna-Posada, run by a family member (the spouse)
var _keeper: String = ""
var _spectacles: Dictionary = {}      # "<festival>|<spectacle>" -> looked at (enter or bet decided)
var _calls: Dictionary = {}           # festival matches it was called to and played

var goals: int = 1                    # trials (BOT_VARS=goals=0): 0 = never leaves the business for a goal
var quota_caravans: int = 1          # equilibrio (BOT_VARS=quota_caravans=0): 0 = signs and breaks the quota, as before
var builds: int = 1                   # H6 (BOT_VARS=builds=0): 0 = never opens a second workshop on a plot, as before
var facades: int = 1                  # Barón (BOT_VARS=facades=0): 0 = never buys the facades (+10/+20/+30 reputation)
var bonuses_all: int = 1              # Barón (BOT_VARS=bonuses_all=0): 0 = bonuses only at the forge, as before
var branch_mix: int = 1               # Barón (d) (BOT_VARS=branch_mix=0): 0 = the second workshop loops one recipe, as before
const FACADES: Array = ["forge_facade_1", "forge_facade_2", "forge_facade_3"]
const FACADE_SPARE: int = 300         # gold kept on top of the reserve and the facade's price
var branch: BotBranch = BotBranch.new()  # H6: the second workshop (a forge on a free plot) when it pays
var titles_early: int = 1             # Equilibrio 3 (BOT_VARS=titles_early=0): 0 = asks Citizen after the plan, as before
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
var _quota_hold: int = 0             # swords kept for the quota's caravan this season (normal ones first)
var _trip_hold: bool = false          # Equilibrio 7: keeps swords for the first trip (the market at home takes them all)


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
	out.append_array(_cards(sim))
	var lf := _live(sim)
	if not lf.is_empty():
		out.append(lf)
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
	out.append_array(_festival_games(sim))
	out.append_array(_inn(sim))
	if builds == 1 and _business(sim):  # H6: the second workshop, built when it pays and run by its own employee
		var had := branch.bld
		branch.raw = RAW
		branch.mix = branch_mix == 1
		var tavern_done := inn != null and str(st.buildings.get(inn._tavern, {}).get("owner", "")) == _fam_id \
			or str(why_not.get("tavern", "")) == "none_for_sale"
		out.append_array(branch.manage(sim, ACTOR, _fam_id, FORGE, _reserve(sim), tavern_done))
		if branch.bld != "" and had == "":
			_use("plots")
		elif branch.bld == "" and branch.why_not != "":
			why_not["plots"] = branch.why_not
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
	if quota_caravans == 1:
		var qo := _quota_caravan(sim)
		if not qo.is_empty() or _quota_hold > 0:
			return qo
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


## Equilibrio 7 (a quota signed): this season's swords for the capital are gathered (kept from the market, the normal
## ones first; the good ones still go there by the trip's premium) and sent by caravan with an employee as carter (one
## is enough: the quota pays 1,2 × the base price, no tariff); a cart is bought for it. {} while gathering.
func _quota_caravan(sim: Sim) -> Dictionary:
	var st := sim.state
	_quota_hold = 0
	var q := Treaties.quota_of(sim, CITY, _fam_id, "sword")
	if q.is_empty():
		return {}
	var left := int(q["qty"]) - int(q.get("delivered", 0))
	if left <= 0 or Caravans.busy_carts(sim, _fam_id) > 0:
		return {}  # delivered this season, or the cart is already on the road with them
	_quota_hold = left
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var held := _quota_hold
	_quota_hold = 0
	var keep := _reserved(sim)
	_quota_hold = held
	var cargo: Array = []
	var have := 0
	for qu: int in [Inventory.NORMAL, Inventory.GOOD, Inventory.EXCELLENT]:
		var n := mini(left - have, maxi(0, Inventory.count(inv, "sword", qu) - int(keep.get("sword|%d" % qu, 0))))
		if n > 0:
			cargo.append({"item": "sword", "quality": qu, "qty": n, "min_price": 0})
			have += n
	if have < left:
		why_not["caravans"] = "gathering_quota"
		return {}
	if Caravans.carts(sim, _fam_id) == 0:
		var cart_price := int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
		if Money.gold(st, _fam_id) < cart_price + super._reserve(sim):  # the cart is the reserve's part
			why_not["caravans"] = "cart_too_dear"
			return {}
		_use("caravans")
		_note(sim, "buy_cart", "quota")
		return {"type": "buy_cart", "actor": ACTOR}
	var staff := _active_staff(sim)
	if staff.is_empty():
		why_not["caravans"] = "no_spare_carter"
		return {}
	staff.sort()
	var o := {"type": "caravan_send", "actor": ACTOR, "driver": str(staff[-1]), "building": FORGE, "city": CITY,
		"cargo": cargo, "buy": [], "escort": false}
	var why := Caravans.can_send(sim, o)
	if why != "":
		why_not["caravans"] = why
		return {}
	_quota_hold = 0
	_use("caravans")
	_note(sim, "caravan", "quota: %d swords to %s" % [left, CITY])
	return o


## Whether the family can serve a quota (Equilibrio 7): a cart or the gold for one, and an employee to drive it.
func _can_serve_quota(sim: Sim) -> bool:
	if _active_staff(sim).is_empty():
		return false
	var cart_price := int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
	return Caravans.carts(sim, _fam_id) > 0 or Money.gold(sim.state, _fam_id) >= cart_price + _reserve(sim)


## Normal swords in the storage the market would not take now (demand below the expert's bar), less the contracts'.
func _spare_swords(sim: Sim) -> int:
	if Market.demand(sim, "sword") >= EXPERT_MIN_DEMAND:
		return 0
	var n := Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword", Inventory.NORMAL)
	return maxi(0, n - int(_reserved(sim).get("sword|%d" % Inventory.NORMAL, 0)))


## Equilibrio 3: Citizen opens travel, the duel and the joust (03b §3b.4, year 2), so a player with good judgment asks
## for it as soon as the town hall would grant it and the reserve holds, not after the whole upgrade plan (the expert's
## habit, kept there for the H5 targets of days 9-24).
func _wants_title(sim: Sim) -> bool:
	if titles_early != 1 or Titles.rank(sim, Titles.current(sim, _fam(sim))) >= Titles.rank(sim, "citizen"):
		return super._wants_title(sim)
	return asks_titles == 1 and _business(sim) and Titles.ready(sim, _fam(sim), _reserve(sim))


## The real hours of a festival contract (due_at) are the novice's own check since Equilibrio 11; here only the
## reason is noted for the report.
func _can_make_in_time(sim: Sim, c: Dictionary) -> bool:
	if not bool(c.get("race", false)) and int(c.get("due_at", -1)) < 0:
		return super._can_make_in_time(sim, c)
	# a festival contract: the real hours left and only the head's hands (the employees' queue never takes festival
	# pieces), plus the novice's other checks (recipe open, inputs paid)
	if not super._can_make_in_time(sim, c):
		why_not["festival_contracts"] = "no_time"
		return false
	var hours := _contract_hours(sim, c)
	for a: Dictionary in Contracts.accepted_of(sim, _fam(sim)):
		hours += _contract_hours(sim, a)
	var left := float(int(c.get("due_at", 0)) - _now(sim)) / 60.0
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
	if Courtship.gifted_today(sim.state, ACTOR, target):
		return {}  # Equilibrio 1: a second gift today would not count
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
	_trip_hold = false  # set again below only while it gathers the swords of the first trip
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
	if first and _trip_swords(sim) < TRIP_SWORDS:
		_trip_hold = true  # Equilibrio 7: gathers them, the best first (the capital pays the quality)
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
	var carried := 0
	for q: int in Inventory.QUALITIES:
		carried += Inventory.count(ch["inventory"], "sword", q)
	if carried < TRIP_SWORDS:  # Equilibrio 7: the best swords first (the capital's quality premium)
		var held := _trip_hold
		_trip_hold = false
		var keep := _reserved(sim)
		_trip_hold = held
		for q: int in [Inventory.EXCELLENT, Inventory.GOOD, Inventory.NORMAL]:
			var spare := Inventory.count(st.buildings[FORGE]["inventory"], "sword", q) - int(keep.get("sword|%d" % q, 0))
			var n := mini(TRIP_SWORDS - carried, Inventory.fit_count(ch["inventory"], sim.catalog, "sword", q, maxi(spare, 0)))
			if n > 0:
				return [{"type": "transfer", "actor": ACTOR, "from": FORGE, "to": ACTOR, "item": "sword", "quality": q,
					"qty": n}]
	var why := Travel.can_travel(sim, ACTOR, CITY)
	if why != "":
		why_not["travel"] = why
		_end_focus(sim, "travel", why)
		return []
	_trip_stage = "out"
	_trip_hold = false
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
	for q: int in Inventory.QUALITIES:  # every quality (Equilibrio 7: the good ones fetch the capital's premium)
		var swords := Inventory.count(inv, "sword", q)
		if swords > 0:
			_use("city_market")
			return [{"type": "city_sell", "actor": ACTOR, "item": "sword", "quality": q, "qty": swords}]
	if Treaties.quota_of(sim, CITY, _fam_id, "sword").is_empty():
		var why := Treaties.can_sign(sim, _fam_id, CITY, "quota", "sword")
		if why == "" and quota_caravans == 1 and not _can_serve_quota(sim):
			why = "cannot_serve_quota"  # equilibrio: a quota it cannot deliver would only break
		if why == "":
			_use("treaties")
			_note(sim, "treaty", "quota sword " + CITY)
			return [{"type": "sign_treaty", "actor": ACTOR, "kind": "quota", "item": "sword"}]
		why_not["treaties"] = why
	if Travel.can_travel(sim, ACTOR, Region.home(sim)) == "":
		return [{"type": "return", "actor": ACTOR}]
	return []


## Swords of any quality in the forge's storage beyond what the contracts need (the trip's), Equilibrio 7.
func _trip_swords(sim: Sim) -> int:
	var held := _trip_hold
	_trip_hold = false
	var keep := _reserved(sim)
	_trip_hold = held
	var n := 0
	for q: int in Inventory.QUALITIES:
		n += maxi(0, Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword", q) - int(keep.get("sword|%d" % q, 0)))
	return n


## While gathering swords for the first trip (Equilibrio 7), up to TRIP_SWORDS of them, the best first, are kept from
## the market like a contract's.
## With a quota in force and no cart yet (Equilibrio 7), the cart's price stays in the reserve: the quota is served by
## caravan, and a season without the cart breaks it.
## H6: at a stall anyway, after its own forge's purchases, an errand of what the second workshop lacks.
func _buy_raw(sim: Sim) -> Dictionary:
	var o := super._buy_raw(sim)
	if not o.is_empty() or builds != 1:
		return o
	return branch.supply(sim, ACTOR, _fam_id, _reserve(sim))


func _reserve(sim: Sim) -> int:
	var r := super._reserve(sim)
	if Caravans.carts(sim, _fam_id) == 0 and not Treaties.quota_of(sim, CITY, _fam_id, "sword").is_empty():
		r += int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
	return r


func _reserved(sim: Sim) -> Dictionary:
	var out := super._reserved(sim)
	if _quota_hold > 0:  # the quota's swords (Equilibrio 7), the normal ones first
		var qleft := _quota_hold
		var qinv: Dictionary = sim.state.buildings[FORGE]["inventory"]
		for q: int in [Inventory.NORMAL, Inventory.GOOD, Inventory.EXCELLENT]:
			var key := "sword|%d" % q
			var take := mini(qleft, maxi(0, Inventory.count(qinv, "sword", q) - int(out.get(key, 0))))
			if take > 0:
				out[key] = int(out.get(key, 0)) + take
				qleft -= take
	if not _trip_hold:
		return out
	var left := TRIP_SWORDS
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	for q: int in [Inventory.EXCELLENT, Inventory.GOOD, Inventory.NORMAL]:
		var key := "sword|%d" % q
		var free := Inventory.count(inv, "sword", q) - int(out.get(key, 0))
		var take := mini(left, maxi(free, 0))
		if take > 0:
			out[key] = int(out.get(key, 0)) + take
			left -= take
	return out


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


# --- Forja viva and the unlocks (03b §3b.2-§3b.4) -------------------------------------------------------------

## Every unlock card not read yet (unlock_seen, like the pacing bot): the player reads them as they come.
func _cards(sim: Sim) -> Array:
	var out: Array = []
	var reader := ACTOR if not Region.is_away(sim.state, ACTOR) else _home_adult(sim)
	if reader == "":
		return out  # everybody away: the cards wait (an order from the road would be refused, «away»)
	for e: Dictionary in Unlocks.list(sim, _fam_id):
		if not bool(e.get("seen", false)):
			_use("unlocks")
			out.append({"type": "unlock_seen", "actor": reader, "unlock": str(e["id"]), "what": "card"})
	return out


## Whether a panel of the UI is open for the family (data/unlocks.json `ui`): what a player cannot reach yet, the bot
## does not use either (hiring before «staff», upgrades before «upgrades»).
func _ui(sim: Sim, ui: String) -> bool:
	return Unlocks.ui_open(sim, _fam_id, ui)


func _hire(sim: Sim) -> Dictionary:
	if not _ui(sim, "staff"):
		why_not["staff"] = "not_unlocked"
		return {}
	if why_not.get("staff", "") == "not_unlocked":
		why_not.erase("staff")
	return super._hire(sim)


func _next_upgrade(sim: Sim) -> String:
	if not _ui(sim, "upgrades"):
		why_not["upgrades"] = "not_unlocked"
		return ""
	if why_not.get("upgrades", "") == "not_unlocked":
		why_not.erase("upgrades")
	var id := super._next_upgrade(sim)
	if id != "" or facades != 1 or not _plan_done(sim):
		return id
	if Upgrades.under_works(sim.state, FORGE) or _now(sim) < _works_end + WORKS_GAP_DAYS * Clock.MINUTES_PER_DAY:
		return ""
	# Barón (the manager's decision, 2026-11-07): with the plan done and gold to spare, the facades (reputation)
	for f: String in FACADES:
		var s := Upgrades.status_of(sim, ACTOR, FORGE, f)
		if s == "owned":
			continue
		if s in ["available", "missing_materials", "not_enough_gold"] \
				and Money.gold(sim.state, _fam_id) >= _reserve(sim) + _upgrade_gold(sim, f) + FACADE_SPARE:
			return f
		return ""
	return ""


## Barón (the manager's decision, 2026-11-07): the bonus keeps every employee of the family loyal (>= LOYAL), the
## tavern's and the second workshop's too (their rumours cost reputation, data/employees.json bands); the forge's
## first, as before.
func _bonus(sim: Sim) -> Dictionary:
	var o := super._bonus(sim)
	if not o.is_empty() or bonuses_all != 1:
		return o
	var st := sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if b == FORGE or str(st.buildings[b].get("owner", "")) != _fam_id:
			continue
		for e: Dictionary in Staff.employees(sim, b):
			var c := str(e["character"])
			if not bool(e["active"]) or int(e["loyalty"]) >= LOYAL or int(_bonus_day.get(c, -1)) == _today(sim):
				continue
			if Money.gold(st, _fam_id) < RESERVE + int(sim.catalog.employees.get("bonus_gold", 5)):
				return {}
			_bonus_day[c] = _today(sim)
			return {"type": "bonus", "actor": ACTOR, "employee": c}
	return {}


## The next decision of the head's live cycle, played well (as BotPacing): the recipe's colour, its template (with the
## variant's strikes), and the quench the contract asks for (else the recipe's).
func _live(sim: Sim) -> Dictionary:
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	if zone == "":
		return {}
	var v := LiveForge.view(sim, FORGE, zone)
	if v.is_empty() or str(v["actor"]) != ACTOR or str(v["stage"]) == "done":
		return {}
	var rdef := LiveForge.recipe_def(sim, str(v["recipe"]))
	var part: Dictionary = sim.state.buildings[FORGE]["zones"][zone]["job"]["live"]
	var o := {"type": "live_forge", "actor": ACTOR, "building": FORGE, "zone": zone}
	match str(v["stage"]):
		"heat":
			o["step"] = "heat"
			o["choice"] = str(rdef.get("heat", ""))
		"strike":
			o["step"] = "strike"
			o["choice"] = str(LiveForge.template_of(sim, rdef, part)[(v["strikes"] as Array).size()])
		"quench":
			o["step"] = "quench"
			var want := str((part.get("spec", {}).get("want", {}) as Dictionary).get("temper", ""))
			o["choice"] = want if want != "" else LiveForge.wanted_quench(rdef, part)
		_:
			return {}
	_use("live_forge")
	return o


## Hand work at an anvil goes in Forja viva when the recipe has it (as BotPacing).
func _make(sim: Sim, rid: String, mode: String) -> Dictionary:
	var w := super._make(sim, rid, mode)
	if not w.is_empty() and Upgrades.zone_kind(sim, FORGE, str(w.get("zone", ""))) == ANVIL \
			and LiveForge.start_reason(sim, ACTOR, str(w["recipe"])) == "":
		w["mode"] = LiveForge.MODE
	return w


## A contract piece of a contract that asks for a variant (03b §3b.3) is made to it: work_at with the contract and
## the variant's axes the client wants (the temper goes in the live quench).
func _work(sim: Sim) -> Dictionary:
	var o := super._work(sim)
	if str(o.get("type", "")) != "work_at" or str(o.get("mode", "")) != LiveForge.MODE:
		return o
	var item := _output(sim, str(o["recipe"]))
	for c: Dictionary in _contracts_by_due(sim):
		var want: Variant = c.get("spec")
		if str(c["item"]) != item or not want is Dictionary or (want as Dictionary).is_empty():
			continue
		if LiveForge.crate_units(c, int(c.get("min_quality", 0))) >= int(c["qty"]):
			continue  # its pieces made to the spec are there
		var variant := {}
		for axis: Variant in LiveForge.axes_of(sim, str(o["recipe"])):
			if (want as Dictionary).has(str(axis)):
				variant[str(axis)] = str(want[str(axis)])
		o["contract"] = str(c["id"])
		o["variant"] = variant
		_use("variant_contracts")
		break
	return o


# --- The second business and the games -------------------------------------------------------------------------

## Posada (04f §4.27): once the forge runs as a business, with an adult of the family free to keep it (the spouse)
## and gold for the price on top of the reserve, it buys the Taberna-Posada for sale and gives it to that member
## (assign_building); from then on BotInnkeeper runs it with the keeper as its hero (management, the bar at dusk, the
## beds, the kitchen's queue, the upgrades and the licence).
func _inn(sim: Sim) -> Array:
	var st := sim.state
	if inn != null:
		if not st.buildings.has(inn._tavern) or str(st.buildings[inn._tavern].get("owner", "")) != _fam_id:
			inn = null
			return []
		if _keeper == "" or not Kin.alive(st, _keeper) or Region.is_away(st, _keeper) or _keeper == ACTOR:
			_keeper = _free_adult(sim)
			if _keeper == "":
				why_not["tavern"] = "no_keeper"
				return []
			inn._hero = _keeper
			_note(sim, "innkeeper", _keeper)
			return [{"type": "assign_building", "actor": ACTOR, "character": _keeper, "building": inn._tavern}]
		inn._hero = _keeper
		inn.kept = _reserve(sim) - super._reserve(sim)  # the quota's cart (Equilibrio 7b): the tavern does not spend it
		var o: Array = []
		var loc := str(st.characters[_keeper].get("location", ""))
		for x: Dictionary in inn.orders(sim):
			# BotInnkeeper's keeper starts in the tavern (innkeeper_start); this one may be at home: out first
			if str(x.get("type", "")) == "enter_building" and str(x.get("actor", "")) == _keeper and loc != "" \
					and loc != str(x.get("building", "")):
				x = {"type": "exit_building", "actor": _keeper}
			if str(x.get("type", "")) == "buy_upgrade" and Money.gold(st, _fam_id) < int(sim.catalog.upgrade(
					str(x.get("upgrade", ""))).get("cost", {}).get("gold", 0)) + _reserve(sim) + INN_SPARE:
				continue  # the tavern's upgrades never eat the forge's reserve (the purse is the family's)
			o.append(x)
		if not o.is_empty():
			_use("tavern")
		return o
	if _now(sim) % 60 != 0:
		return []
	if not _business(sim):
		why_not["tavern"] = "debt_first"
		return []
	if Titles.rank(sim, Titles.current(sim, _fam_id)) < Titles.rank(sim, "citizen"):
		why_not["tavern"] = "title_needed"  # 03b §3b.4: the second business comes with Citizen (bought before, measured:
		return []                           # the year 2 net falls to −52/day and Citizen never comes in 3 years)
	var sale := ""
	for b: String in _sorted_ids(st.buildings.keys()):
		if bool(st.buildings[b].get("for_sale", false)) and str(st.buildings[b].get("owner", "")) == "" and Inn.is_inn(sim, b):
			sale = b
			break
	if sale == "":
		why_not["tavern"] = "none_for_sale"
		return []
	var keeper := _free_adult(sim)
	if keeper == "":
		why_not["tavern"] = "no_keeper"
		return []
	if Money.gold(st, _fam_id) < Inn.sale_price(sim, sale) + _reserve(sim) + INN_SPARE:
		why_not["tavern"] = "gold_short"
		return []
	inn = BotInnkeeper.new()
	inn._tavern = sale
	inn._fam = _fam_id
	inn._hero = keeper
	_keeper = keeper
	_use("tavern")
	_note(sim, "buy_inn", "%s for %d, kept by %s" % [sale, Inn.sale_price(sim, sale), keeper])
	return [{"type": "buy_building", "actor": ACTOR, "building": sale},
		{"type": "assign_building", "actor": ACTOR, "character": keeper, "building": sale}]


## An adult of the family's group other than the one who plays the forge, not employed, at home: the spouse first.
func _free_adult(sim: Sim) -> String:
	var st := sim.state
	var sp := str(st.characters.get(ACTOR, {}).get("spouse", ""))
	var list: Array = ([sp] if sp != "" else []) + Kin.group(st, _fam_id)
	for c: Variant in list:
		var id := str(c)
		if id != ACTOR and Kin.alive(st, id) and Kin.is_adult(sim, id) and str(st.characters[id].get("family", "")) == _fam_id \
				and not st.characters[id].get("job") is Dictionary and not Region.is_away(st, id):
			return id
	return ""


## Juegos (04f §4.26) at the festivals: within the last day before a competition of a feast (FestivalGames), it enters
## it when its chance beats the field's mean by ENTER_EDGE (Games.win_odds, the bookmaker's own estimate) and it meets
## the title and the fee; else it bets BET_STAKE on the favourite while it has gold to spare. Called to its match, it
## plays it («Resolver sin jugar»: game_play with auto).
func _festival_games(sim: Sim) -> Array:
	var st := sim.state
	var out: Array = []
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "festival_game_call" and str(e.get("family", "")) == _fam_id \
				and not _calls.has(str(e.get("match", ""))):
			_calls[str(e["match"])] = true
			_use("games")
			out.append({"type": "game_play", "actor": str(e["actor"]), "game": str(e["game"]),
				"opponents": e.get("opponents", []), "stake": 0, "opts": {"event": str(e["festival"])},
				"match": str(e["match"]), "auto": true})
	if _now(sim) % 15 != 0:
		return out
	for sp: Dictionary in Festivals.spectacles(sim):
		var key := "%s|%s" % [sp["festival"], sp["spectacle"]]
		if _spectacles.has(key) or not FestivalGames.is_game(sim, str(sp["spectacle"])):
			continue
		var left := int(sp["at"]) - _now(sim)
		if left <= 0 or left > Clock.MINUTES_PER_DAY:
			continue
		_spectacles[key] = true
		var inst := Festivals.find(sim, str(sp["festival"]))
		if inst.is_empty():
			continue
		var game := str(FestivalGames.spectacle_cfg(sim, str(sp["spectacle"])).get("game", ""))
		var c: Dictionary = sim.catalog.games.get(game, {})
		var why := ""
		var title := str(c.get("requires", {}).get("title", ""))
		if title != "" and Titles.rank(sim, Titles.current(sim, _fam_id)) < Titles.rank(sim, title):
			why = "title_needed"
		elif Money.gold(st, _fam_id) < int(c.get("entry_fee", 0)) + _reserve(sim):
			why = "gold_short"
		else:
			var spec := FestivalGames.spec_for(sim, inst, str(sp["spectacle"]), ACTOR)
			spec["match"] = str(spec["match"]) + "|fp"  # its own estimate's keys: the real match's dice stay unseen
			var p := float(Games.win_odds(sim.catalog.games, spec, ODDS_SAMPLES).get(0, 0.0))
			if p * float((spec["players"] as Array).size()) < ENTER_EDGE:
				why = "low_chance_%.2f" % p
		if why == "":
			_note(sim, "game_enter", key)
			out.append({"type": "game_enter", "actor": ACTOR, "festival": str(sp["festival"]),
				"spectacle": str(sp["spectacle"])})
			continue
		why_not["games"] = why
		if Money.gold(st, _fam_id) < _reserve(sim) + BET_SPARE + BET_STAKE:
			why_not["bets"] = "gold_short"
			continue
		var fspec := FestivalGames.spec_for(sim, inst, str(sp["spectacle"]))
		fspec["match"] = str(fspec["match"]) + "|fp"
		var ch := Games.win_odds(sim.catalog.games, fspec, ODDS_SAMPLES)
		var fav := 0
		for k: Variant in ch:
			if int(k) >= 0 and float(ch[k]) > float(ch.get(fav, 0.0)):
				fav = int(k)
		_use("bets")
		out.append({"type": "game_bet", "actor": ACTOR, "festival": str(sp["festival"]), "spectacle": str(sp["spectacle"]),
			"on": fav, "stake": BET_STAKE})
	return out


func _sorted_ids(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(str(x))
	out.sort()
	return out


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
	if inn != null:  # posada: the innkeeper's own measures (inn_net_day, inn_fame, inn_bed_share...)
		m.merge(inn.measures(sim))
	return m


## What the report needs that is not a number: the reasons, the uses, the decisions, the heads.
func report(_sim: Sim) -> Dictionary:
	return {"why_not": why_not.duplicate(), "used": used.duplicate(), "decisions": decisions.duplicate(true),
		"heads": heads.duplicate(), "focus_minutes": focus_minutes.duplicate()}
