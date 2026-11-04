class_name Offices
extends RefCounted
## Public offices (GDD 4.12.3; docs/contratos/h10_cargos.md): the procedural government at the start, the seats and
## their terms, salaries, taxes, the passive effects and the active powers of each office, and the market price
## regulations of the inspector. state.offices[office] = {seats: [{holder, since, until, cooldowns}], settings}; the
## holder's family is the character's. Elections (registering, campaign, vote) live in Elections; this file closes
## the terms on the year change and hands the seats to the winners (take / leave). No randomness.


static func gov(sim: Sim) -> Dictionary:
	return sim.catalog.politics.get("government", {})


static func days_per_year(sim: Sim) -> int:
	return Clock.days_per_year(sim.catalog.time)


static func today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


## The day that starts with the next year change (the day of the next elections).
static func next_year_day(sim: Sim) -> int:
	return (Clock.year(int(sim.state.clock["minute"]), sim.catalog.time) + 1) * days_per_year(sim)


static func has_town_hall(st: WorldState, catalog: Catalog) -> bool:
	return not (catalog.maps().get(st.map_id, {}).get("town_hall", {}) as Dictionary).is_empty()


# --- The procedural government (GDD 4.12.3) -------------------------------------------------------------------------

## Hands out the government once: the household families take their titles (government.household_titles, by family
## id) and each office, from the top of the chart, gets for each seat the oldest adult of a household whose title is
## its min_title (then id; at most one office per person), unless the office is in start_vacant or nobody fits.
## Terms start with the current year. Works on a bare state (NewGame) or a running one (Offices.step).
static func setup(st: WorldState, catalog: Catalog) -> void:
	var g: Dictionary = catalog.politics.get("government", {})
	var titles: Array = g.get("household_titles", [])
	var homes: Array = []
	for f: String in st.families:
		if TownLife.is_household(st, f):
			homes.append(f)
	homes.sort()
	for i: int in homes.size():
		var t := str(titles[i]) if i < titles.size() else "common"
		if catalog.titles().has(t):
			st.families[homes[i]]["title"] = t
	var minute := int(st.clock["minute"])
	var dpy := Clock.days_per_year(catalog.time)
	var year_day := Clock.year(minute, catalog.time) * dpy
	var taken: Dictionary = {}
	st.offices = {}
	for office: String in catalog.office_chart():
		var def: Dictionary = catalog.offices()[office]
		var seats: Array = []
		for n: int in int(def.get("seats", 1)):
			var holder := ""
			if not office in (g.get("start_vacant", []) as Array):
				holder = _pick(st, catalog, homes, str(def.get("min_title", "")), taken)
			if holder != "":
				taken[holder] = true
			seats.append({"holder": holder, "since": year_day if holder != "" else -1,
				"until": year_day + (int(def.get("term_years", 1)) if holder != "" else 1) * dpy, "cooldowns": {}})
		st.offices[office] = {"seats": seats, "settings": {}}
		if office_has_passive(catalog, office, "tax_commission"):
			st.offices[office]["settings"]["tax_percent"] = int(catalog.politics.get("taxes", {}).get("default_percent", 5))
	if OS.is_debug_build():
		var parts: Array = []
		for office: String in catalog.office_chart():
			for s: Dictionary in st.offices[office]["seats"]:
				parts.append("%s=%s" % [office, str(s["holder"]) if str(s["holder"]) != "" else "VACANTE"])
		print("[Offices] gobierno repartido (día %d): %s" % [Clock.day(minute), ", ".join(parts)])


static func _pick(st: WorldState, catalog: Catalog, homes: Array, title: String, taken: Dictionary) -> String:
	var best := ""
	var best_birth := 0
	for f: String in homes:
		if str(st.families[f].get("title", "")) != title:
			continue
		for m: Variant in st.families[f].get("members", []):
			var c := str(m)
			var ch: Dictionary = st.characters.get(c, {})
			if ch.is_empty() or not bool(ch.get("alive", true)) or taken.has(c):
				continue
			var age := Clock.age_years(int(ch.get("birth_day", 0)), int(st.clock["minute"]), catalog.time)
			if age < int(catalog.family.get("life", {}).get("majority_age", 16)):
				continue
			var b := int(ch.get("birth_day", 0))
			if best == "" or b < best_birth or (b == best_birth and c < best):
				best = c
				best_birth = b
	return best


# --- Queries --------------------------------------------------------------------------------------------------------

static func seats(sim: Sim, office: String) -> Array:
	return sim.state.offices.get(office, {}).get("seats", [])


## The living holders of an office, in seat order.
static func holders(sim: Sim, office: String) -> Array:
	var out: Array = []
	for s: Dictionary in seats(sim, office):
		var h := str(s.get("holder", ""))
		if h != "" and Kin.alive(sim.state, h):
			out.append(h)
	return out


## The office `chr` holds ("" if none).
static func of_character(st: WorldState, chr: String) -> String:
	if chr == "":
		return ""
	for office: String in st.offices:
		for s: Dictionary in st.offices[office].get("seats", []):
			if str(s.get("holder", "")) == chr:
				return office
	return ""


## The seat `chr` holds: {office, index} or {}.
static func seat_of(st: WorldState, chr: String) -> Dictionary:
	for office: String in st.offices:
		var ss: Array = st.offices[office].get("seats", [])
		for i: int in ss.size():
			if str(ss[i].get("holder", "")) == chr:
				return {"office": office, "index": i}
	return {}


## The offices held by members of `fam`: [{office, holder}].
static func of_family(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for office: String in sim.catalog.office_chart():
		for h: String in holders(sim, office):
			if str(sim.state.characters[h].get("family", "")) == fam:
				out.append({"office": office, "holder": h})
	return out


static func office_has_passive(catalog: Catalog, office: String, kind: String) -> bool:
	for p: Dictionary in catalog.offices().get(office, {}).get("passive", []):
		if str(p.get("kind", "")) == kind:
			return true
	return false


## Whether the family's title reaches the office's min_title.
static func title_allows(sim: Sim, fam: String, office: String) -> bool:
	var need := str(sim.catalog.offices().get(office, {}).get("min_title", ""))
	return Titles.rank(sim, Titles.current(sim, fam)) >= Titles.rank(sim, need)


## The day of the next election of `office` if it falls at the next year change (a seat is vacant or its term ends
## then), else -1.
static func election_day(sim: Sim, office: String) -> int:
	var nyd := next_year_day(sim)
	for s: Dictionary in seats(sim, office):
		if str(s.get("holder", "")) == "" or not Kin.alive(sim.state, str(s["holder"])) or int(s.get("until", 0)) <= nyd:
			return nyd
	return -1


## The per cent the family's offices add to its reputation with class `cls` (passive class_reputation).
static func class_percent(sim: Sim, fam: String, cls: String) -> int:
	var pct := 0
	for o: Dictionary in of_family(sim, fam):
		for p: Dictionary in sim.catalog.offices()[str(o["office"])].get("passive", []):
			if str(p.get("kind", "")) == "class_reputation" and str(p.get("class", "")) == cls:
				pct += int(p.get("percent", 0))
	return pct


## The family's reputation with class `cls` (GDD 4.12.1: global + class modifier), with its offices' passives.
static func reputation_with_class(sim: Sim, fam: String, cls: String) -> int:
	var base := Reputation.with_class(sim.state, fam, cls)
	var pct := class_percent(sim, fam, cls)
	return base if pct == 0 else roundi(float(base) * float(100 + pct) / 100.0)


## The tax per cent in force (0 without a tax collector in office).
static func tax_percent(sim: Sim) -> int:
	for office: String in sim.state.offices:
		if office_has_passive(sim.catalog, office, "tax_commission") and not holders(sim, office).is_empty():
			return int(sim.state.offices[office].get("settings", {}).get("tax_percent",
				sim.catalog.politics.get("taxes", {}).get("default_percent", 5)))
	return 0


## H11: the family's tax multiplier: the lowest tax_mult of its businesses (the Secrets «double accounting», GDD 4.8).
static func _tax_mult(sim: Sim, fam: String) -> float:
	var m := 1.0
	for b: String in Titles.business_ids(sim, fam):
		m = minf(m, Upgrades.mult(sim, b, "tax_mult"))
	return m


## The organisation chart (GDD 4.12.4) for the UI: [{office, rank, min_title, salary, term_years, seats: [{holder,
## name, family, family_name, until, years_left, vacant}], election: {} | {id, day, campaign_day, candidates},
## election_day (the next vote if it is at the next year change, else -1)}].
static func chart(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var dpy := days_per_year(sim)
	for office: String in sim.catalog.office_chart():
		var def: Dictionary = sim.catalog.offices()[office]
		var rows: Array = []
		for s: Dictionary in seats(sim, office):
			var h := str(s.get("holder", ""))
			var alive := h != "" and Kin.alive(st, h)
			var fam := str(st.characters.get(h, {}).get("family", "")) if alive else ""
			rows.append({"holder": h if alive else "", "name": str(st.characters.get(h, {}).get("name", "")) if alive else "",
				"family": fam, "family_name": str(st.families.get(fam, {}).get("name", "")), "until": int(s.get("until", 0)),
				"years_left": maxi(0, ceili(float(int(s.get("until", 0)) - today(sim)) / float(dpy))) if alive else 0,
				"vacant": not alive})
		out.append({"office": office, "rank": str(def.get("rank", "")), "min_title": str(def.get("min_title", "")),
			"salary": int(def.get("salary", 0)), "term_years": int(def.get("term_years", 1)), "seats": rows,
			"election": Elections.open_election(st, office), "election_day": election_day(sim, office)})
	return out


# --- Step -----------------------------------------------------------------------------------------------------------

## Hands out the government if missing; deaths free their seats; at the start of winter the campaign notices; at the
## year change the elections and the end of terms; at dawn salaries, taxes, the mayor's reputation, old regulations.
static func step(sim: Sim) -> void:
	var st := sim.state
	if st.offices.is_empty():
		if sim.catalog.offices().is_empty() or not has_town_hall(st, sim.catalog):
			return
		setup(st, sim.catalog)
	var n := sim.events.size()
	for i: int in n:
		var e: Dictionary = sim.events[i]
		match str(e.get("type", "")):
			"character_died":
				_vacate(sim, str(e.get("character", "")), "died")
			"season_changed":
				var seasons: Array = sim.catalog.time.get("seasons", [])
				if not seasons.is_empty() and str(e.get("season", "")) == str(seasons[seasons.size() - 1]):
					Elections.campaign_started(sim)
			"year_changed":
				_year_change(sim)
	if Ledger.is_dawn(sim):
		_dawn(sim)


static func _vacate(sim: Sim, chr: String, reason: String) -> void:
	var where := seat_of(sim.state, chr)
	if where.is_empty():
		return
	var s: Dictionary = sim.state.offices[str(where["office"])]["seats"][int(where["index"])]
	leave(sim, str(where["office"]), int(where["index"]), reason)
	s["until"] = next_year_day(sim)


## The year change: a year of term for every holder that has served one (chronicle office_year), then the elections of
## the seats whose term ends today (or that are vacant).
static func _year_change(sim: Sim) -> void:
	var st := sim.state
	var d := today(sim)
	var dpy := days_per_year(sim)
	for office: String in sim.catalog.office_chart():
		for s: Dictionary in seats(sim, office):
			var h := str(s.get("holder", ""))
			if h != "" and Kin.alive(st, h) and int(s.get("since", d)) <= d - dpy:
				Chronicle.add(st, "office_year", {"family": str(st.characters[h].get("family", "")), "office": office,
					"actor": h})
	for office: String in sim.catalog.office_chart():
		var due: Array = []
		var ss: Array = seats(sim, office)
		for i: int in ss.size():
			var h := str(ss[i].get("holder", ""))
			if h == "" or not Kin.alive(st, h) or int(ss[i].get("until", 0)) <= d:
				due.append(i)
		if not due.is_empty():
			Elections.resolve(sim, office, due)


static func _dawn(sim: Sim) -> void:
	var st := sim.state
	for office: String in sim.catalog.office_chart():
		var def: Dictionary = sim.catalog.offices()[office]
		for h: String in holders(sim, office):
			var fam := str(st.characters[h].get("family", ""))
			Money.change(sim, fam, int(def.get("salary", 0)), Money.OFFICES, "office_" + office, "", h)
			for p: Dictionary in def.get("passive", []):
				if str(p.get("kind", "")) == "reputation_per_day":
					Reputation.change(sim, fam, int(p.get("amount", 0)), "office_" + office)
	_taxes(sim)
	var now := int(st.clock["minute"])
	var keep: Array = []
	for r: Dictionary in st.market.get("regulations", []):
		if int(r.get("until", 0)) > now:
			keep.append(r)
	st.market["regulations"] = keep


## GDD 4.12.3: with a tax collector, every family pays tax_percent of its sales of the day before (ledger taxes); the
## collector's commission (tax_commission) out of what is collected goes to its family (offices).
static func _taxes(sim: Sim) -> void:
	var pct := tax_percent(sim)
	if pct <= 0:
		return
	var st := sim.state
	var cats: Array = sim.catalog.politics.get("taxes", {}).get("categories", [])
	var yday := today(sim) - 1
	var sales: Dictionary = {}
	var entries: Array = st.ledger.get("entries", [])
	var i := entries.size() - 1
	while i >= 0:
		var e: Dictionary = entries[i]
		i -= 1
		var dd := int(e.get("day", 0))
		if dd > yday:
			continue
		if dd < yday:
			break
		if str(e.get("category", "")) in cats and int(e.get("amount", 0)) > 0:
			sales[str(e["family"])] = int(sales.get(str(e["family"]), 0)) + int(e["amount"])
	var total := 0
	var fams: Array = sales.keys()
	fams.sort()
	for f: String in fams:
		var tax := mini(roundi(float(sales[f]) * float(pct) / 100.0 * _tax_mult(sim, f) * Festivals.home_tax_mult(sim,
			yday)), Money.gold(st, f))  # fiestas (4.25.3): the feria franca pays no tax
		if tax > 0 and Money.change(sim, f, -tax, Money.TAXES, "tax_day_%d" % yday):
			total += tax
			sim.events.append({"type": "tax_collected", "family": f, "amount": tax, "sales": int(sales[f]), "percent": pct})
	if total <= 0:
		return
	for office: String in sim.catalog.office_chart():
		for p: Dictionary in sim.catalog.offices()[office].get("passive", []):
			if str(p.get("kind", "")) != "tax_commission":
				continue
			for h: String in holders(sim, office):
				var cut := roundi(float(total) * float(p.get("percent", 0)) / 100.0)
				Money.change(sim, str(st.characters[h].get("family", "")), cut, Money.OFFICES, "tax_commission", "", h)
	if OS.is_debug_build():
		print("[Offices] impuestos del día %d al %d%%: %d de oro (%s)" % [yday + 1, pct, total, sales])


# --- Taking and leaving ---------------------------------------------------------------------------------------------

## `chr` takes seat `index` of `office` today for a whole term: chronicle office_won (dynasty score by rank), the
## reputation of taking an office, office_taken and the notices.
static func take(sim: Sim, office: String, index: int, chr: String) -> void:
	var st := sim.state
	var def: Dictionary = sim.catalog.offices()[office]
	var s: Dictionary = st.offices[office]["seats"][index]
	var d := today(sim)
	s["holder"] = chr
	s["since"] = d
	s["until"] = d + int(def.get("term_years", 1)) * days_per_year(sim)
	s["cooldowns"] = {}
	if office_has_passive(sim.catalog, office, "tax_commission"):
		st.offices[office]["settings"]["tax_percent"] = int(sim.catalog.politics.get("taxes", {}).get("default_percent", 5))
	var fam := str(st.characters[chr].get("family", ""))
	var rank := str(def.get("rank", ""))
	Chronicle.add(st, "office_won", {"family": fam, "office": office, "rank": rank, "actor": chr})
	Reputation.change(sim, fam, int(gov(sim).get("take_reputation", {}).get(rank, 0)), "office_taken")
	sim.events.append({"type": "office_taken", "office": office, "character": chr, "family": fam, "until": s["until"]})
	var params := {"name": str(st.characters[chr].get("name", "")), "family": str(st.families.get(fam, {}).get("name", "")),
		"office": office, "until": int(s["until"]) + 1}
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.INFO, "notice.office_won", params, chr)
	elif str(st.families.get(fam, {}).get("ai_profile", "")) != "":
		for f: String in _humans(st):
			Notices.add(sim, f, Notices.INFO, "notice.rival_office", params, chr)
	if OS.is_debug_build():
		print("[Offices] %s (%s) ocupa %s hasta el día %d" % [chr, fam, office, int(s["until"])])


## The holder of seat `index` of `office` leaves it (reason term | lost | died): office_left; the seat is vacant.
static func leave(sim: Sim, office: String, index: int, reason: String) -> void:
	var st := sim.state
	var s: Dictionary = st.offices[office]["seats"][index]
	var h := str(s.get("holder", ""))
	if h == "":
		return
	var fam := str(st.characters.get(h, {}).get("family", ""))
	s["holder"] = ""
	s["since"] = -1
	s["cooldowns"] = {}
	sim.events.append({"type": "office_left", "office": office, "character": h, "family": fam, "reason": reason})
	if reason == "lost" and str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.WARNING, "notice.office_lost", {"name": str(st.characters[h].get("name", "")),
			"office": office}, h)
	if OS.is_debug_build():
		print("[Offices] %s (%s) deja %s (%s)" % [h, fam, office, reason])


static func _humans(st: WorldState) -> Array:
	var out: Array = []
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(f)
	out.sort()
	return out


# --- Powers (GDD 4.12.3, active actions) ----------------------------------------------------------------------------

static func power_def(sim: Sim, office: String, power: String) -> Dictionary:
	for p: Dictionary in sim.catalog.offices().get(office, {}).get("powers", []):
		if str(p.get("id", "")) == power:
			return p
	return {}


## The powers of the office `actor` holds: [{power, office, ready, cooldown_minutes, reason}] (reason "" = usable
## now with valid args; else why not, without args: power_not_ready, power_cooldown).
static func powers(sim: Sim, actor: String) -> Array:
	var out: Array = []
	var office := of_character(sim.state, actor)
	if office == "":
		return out
	for p: Dictionary in sim.catalog.offices()[office].get("powers", []):
		var id := str(p.get("id", ""))
		out.append({"power": id, "office": office, "ready": p.get("ready", true) is bool and bool(p["ready"]),
			"from": str(p.get("ready", "")), "cooldown_minutes": cooldown_left(sim, actor, id),
			"reason": power_status(sim, actor, id, {}, false)})
	return out


static func cooldown_left(sim: Sim, actor: String, power: String) -> int:
	var where := seat_of(sim.state, actor)
	if where.is_empty():
		return 0
	var s: Dictionary = sim.state.offices[str(where["office"])]["seats"][int(where["index"])]
	return maxi(0, int(s.get("cooldowns", {}).get(power, 0)) - int(sim.state.clock["minute"]))


## The refusal of use_office_power (with `check_args`, also the args), "" if it would work.
static func power_status(sim: Sim, actor: String, power: String, args: Dictionary, check_args: bool = true) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not Kin.alive(st, actor):
		return "dead"
	var office := of_character(st, actor)
	if office == "":
		return "not_office_holder"
	var p := power_def(sim, office, power)
	if p.is_empty():
		return "unknown_power"
	if not (p.get("ready", true) is bool and bool(p["ready"])):
		return "power_not_ready"
	if cooldown_left(sim, actor, power) > 0:
		return "power_cooldown"
	if not check_args:
		return ""
	if power in ["arrest", "investigate", "pardon", "preside_trial"]:  # H11: the court's powers
		return Tribunal.power_reason(sim, actor, power, args)
	var reg: Dictionary = sim.catalog.politics.get("regulation", {})
	match power:
		"regulate_price":
			var item := str(args.get("item", ""))
			var pct := int(args.get("percent", 0))
			if sim.catalog.item(item).is_empty() or RivalAI.stall_for(sim, item) == "":
				return "bad_args"
			if absi(pct) != int(reg.get("percent", 10)):
				return "bad_args"
			if regulation(sim, item) != 0:
				return "already_regulated"
		"fine_merchant":
			var fam := str(args.get("family", ""))
			if not st.families.has(fam) or fam == str(st.characters[actor].get("family", "")):
				return "bad_args"
			if Titles.businesses(sim, fam) < 1:
				return "not_a_merchant"
		"set_tax":
			var tx: Dictionary = sim.catalog.politics.get("taxes", {})
			var pct := int(args.get("percent", -1))
			if pct < int(tx.get("min", 5)) or pct > int(tx.get("max", 15)):
				return "bad_args"
		"declare_event":  # H13: the mayor declares a declarable global event (GDD 4.12.3, 4.13)
			var ev := str(args.get("event", ""))
			if not ev in WorldEvents.declarable(sim):
				return "bad_args"
			return WorldEvents.can_start(sim, ev)
		"organize_festival":  # fiestas (04f 4.25.5): bulls or a joust in a feast
			return Festivals.organize_reason(sim, actor, args)
	return ""


## {"type": "use_office_power", "actor", "power", "args"}: a power of the actor's office (management). Reasons:
## unknown_actor, dead, not_office_holder, unknown_power, power_not_ready, power_cooldown, bad_args,
## already_regulated, not_a_merchant; H13 declare_event {event}: event_active, event_excluded, too_many_events.
static func order_power(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var power := str(o.get("power", ""))
	var args: Dictionary = o.get("args", {}) if o.get("args", {}) is Dictionary else {}
	var why := power_status(sim, actor, power, args)
	if why != "":
		if OS.is_debug_build():
			print("[Offices] %s no puede usar %s: %s" % [actor, power, why])
		return Orders.fail(why)
	var st := sim.state
	var where := seat_of(st, actor)
	var office := str(where["office"])
	var s: Dictionary = st.offices[office]["seats"][int(where["index"])]
	var now := int(st.clock["minute"])
	var fam := str(st.characters[actor].get("family", ""))
	var reg: Dictionary = sim.catalog.politics.get("regulation", {})
	var params := {"name": str(st.characters[actor].get("name", "")), "family": str(st.families.get(fam, {}).get("name", ""))}
	match power:
		"regulate_price":
			var item := str(args["item"])
			var until := now + int(reg.get("days", 2)) * Clock.MINUTES_PER_DAY
			(st.market["regulations"] as Array).append({"item": item, "percent": int(args["percent"]), "until": until,
				"by": actor, "family": fam})
			sim.events.append({"type": "price_regulated", "item": item, "percent": int(args["percent"]), "until": until})
			params.merge({"item": item, "percent": "%+d" % int(args["percent"])})
			for f: String in _humans(st):
				Notices.add(sim, f, Notices.INFO, "notice.price_regulated", params, actor)
		"fine_merchant":
			var target := str(args["family"])
			var amount := mini(int(reg.get("fine_gold", 20)), Money.gold(st, target))
			Money.change(sim, target, -amount, Money.FINES, "fine_" + office, "", actor)
			params.merge({"gold": amount})
			if str(st.families[target].get("controlled_by", "")) == "human":
				Notices.add(sim, target, Notices.WARNING, "notice.fined", params, actor)
		"arrest", "investigate", "pardon", "preside_trial":  # H11
			Tribunal.use_power(sim, actor, power, args)
		"declare_event":  # H13: starts now; WorldEvents gives the notices
			WorldEvents.start(sim, str(args["event"]), actor)
		"organize_festival":  # fiestas (04f 4.25.5)
			Festivals.organize(sim, actor, args)
		"set_tax":
			st.offices[office]["settings"]["tax_percent"] = int(args["percent"])
			params.merge({"percent": int(args["percent"])})
			for f: String in _humans(st):
				Notices.add(sim, f, Notices.INFO, "notice.tax_set", params, actor)
	var cd := int(power_def(sim, office, power).get("cooldown_days", 0)) * Clock.MINUTES_PER_DAY
	s["cooldowns"][power] = now + cd
	sim.events.append({"type": "office_power", "office": office, "power": power, "actor": actor, "args": args.duplicate()})
	if OS.is_debug_build():
		print("[Offices] %s (%s) usa %s %s (enfriamiento hasta el minuto %d)" % [actor, office, power, args, now + cd])
	return Orders.ok()


## The per cent the inspector's regulation in force moves `item`'s market price (0 = none).
static func regulation(sim: Sim, item: String) -> int:
	var now := int(sim.state.clock["minute"])
	for r: Variant in sim.state.market.get("regulations", []):
		if r is Dictionary and str(r.get("item", "")) == item and int(r.get("until", 0)) > now:
			return int(r.get("percent", 0))
	return 0
