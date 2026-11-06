class_name Hostility
extends RefCounted
## H13 (04c 4.21.8-4.21.10): the rivalry between the families and the attacks of the AI families, only on the maps of
## data/ai.json hostility_maps (Bellcaire); everywhere else (Vilarrasa and its targets) nothing here runs and the AI is
## the one of always. Sim.step calls step() after the tribunal, so it reads the events of the step.
##
## Rivalry (4.21.8.1): a directed value 0-100, what family A feels towards B, kept in town.rivalry.values["A|B"] (only
## the AI families feel it; towards the player and towards the other AI families). At dawn, with the market sales of
## the last market_days days (kept by family and item from the market_sold events): +market_rise when B sold more than
## market_share of an item A also sold; +relation_low_rise when the heads' relation is under relation_low; −decay on a
## day with no rise (P3) and −relation_high_drop when their relation is over relation_high. At the moment: +trial_rise
## to the accused family towards its accuser when found guilty; +attack_rise to the victim of a detected sabotage.
##
## Attack gate (4.21.8.2): at dawn, each AI family in its own minute (dawn + stagger_minutes × its place) looks at its
## targets (rivalry over its effective threshold = the profile's rivalry_threshold + the difficulty's
## threshold_offset), if its cooldown (attack_cooldown_days) has passed, it is not the first year (first_days), it has
## no attack under way and, against the player, the common gap (player_attack_gap_days, P4) has passed. Candidates (the
## closed list, 4.21.9.1, what exists today): price_war (an item it makes that the target sold), accuse (the profile's
## accuse_rule, against the player only: RivalAI gives the order) and sabotage (the target's workshop, at night). The
## utility = attack_bias × hostile_weight × (0.5 + aggression) × rivalry/100 + noise (difficulty noise, a hash of the
## family's day: P6, no draw of the world's rng); the best over u_min is announced (presage) and done when its time
## comes, if still valid (else it is dropped and spends no cooldown).
##   price_war: presage_minutes before, the family keeps the item (stops selling it) and the target hears the rumour;
##              then for season_days it sells it down to min_demand while its gold is over its reserve (RivalAI).
##   accuse:    the accusation is its own presage (public); RivalAI's task accuse gives it (04c, H11).
##   sabotage:  the night before, the target hears that somebody was seen round its building; the next night the
##              building is damaged for repair_days (no work there), unless its Security stops it (security_cut by
##              security upgrades); detected (detect), the target learns who: a fact to accuse with and +attack_rise.
## Every attack goes to town.rivalry.attacks (the measures of the targets) and to the debug log with its reason.

const NIGHT: String = "night"


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.ai_rules


static func on(sim: Sim) -> bool:
	return sim.state.map_id in (cfg(sim).get("hostility_maps", []) as Array)


static func dcfg(sim: Sim) -> Dictionary:
	return sim.catalog.difficulty_levels(sim.state.difficulty).get("ai", {})


## town.rivalry: {values: {"A|B": n}, sales: {day: {fam: {item: qty}}}, rose: {"A|B": day}, attacks: [...],
## player_attacked_day}. Created the first time.
static func book(st: WorldState) -> Dictionary:
	if not st.town.get("rivalry") is Dictionary:
		st.town["rivalry"] = {"values": {}, "sales": {}, "rose": {}, "attacks": [], "player_attacked_day": -100000}
	return st.town["rivalry"]


static func value(st: WorldState, a: String, b: String) -> int:
	if not st.town.get("rivalry") is Dictionary:
		return 0
	return int((st.town["rivalry"]["values"] as Dictionary).get(a + "|" + b, 0))


## 0 Cordial, 1 Neutral, 2 Tensa, 3 Hostil, 4 Enemiga (4.21.8.1).
static func band(sim: Sim, v: int) -> int:
	var b := 0
	for edge: Variant in cfg(sim).get("rivalry", {}).get("bands", [20, 40, 60, 80]):
		if v >= int(edge):
			b += 1
	return b


static func add(sim: Sim, a: String, b: String, n: int, why: String) -> void:
	if n == 0 or a == b:
		return
	var bk := book(sim.state)
	var key := a + "|" + b
	var vals: Dictionary = bk["values"]
	var v := clampi(int(vals.get(key, 0)) + n, 0, int(cfg(sim).get("rivalry", {}).get("max", 100)))
	if v == 0:
		vals.erase(key)
	else:
		vals[key] = v
	if n > 0:
		bk["rose"][key] = _today(sim)
	if OS.is_debug_build():
		print("[Hostility] rivalidad %s -> %s %+d (%s) = %d" % [a, b, n, why, v])


static func _today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


static func _ai_families(st: WorldState) -> Array:
	var out: Array = []
	for f: String in st.families:
		var fd: Dictionary = st.families[f]
		if str(fd.get("controlled_by", "")) == "ai" and str(fd.get("ai_profile", "")) != "":
			out.append(f)
	out.sort()
	return out


## The families a rival looks at: the AI ones with a profile and the players'.
static func _rivals(st: WorldState) -> Array:
	var out: Array = _ai_families(st)
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(f)
	out.sort()
	return out


static func _human(st: WorldState, f: String) -> bool:
	return str(st.families.get(f, {}).get("controlled_by", "")) == "human"


static func _profile(sim: Sim, f: String) -> Dictionary:
	return sim.catalog.ai_profiles().get(str(sim.state.families.get(f, {}).get("ai_profile", "")), {})


static func _mem(sim: Sim, f: String) -> Dictionary:
	var fd: Dictionary = sim.state.families[f]
	if not fd.get("ai_state") is Dictionary:
		fd["ai_state"] = {}
	if not (fd["ai_state"] as Dictionary).get("hostility") is Dictionary:
		fd["ai_state"]["hostility"] = {"last_attack_day": -100000}
	return fd["ai_state"]["hostility"]


# --- Step ------------------------------------------------------------------------------------------------------------

static func step(sim: Sim) -> void:
	if not on(sim):
		return
	var st := sim.state
	var bk := book(st)
	var now := int(st.clock["minute"])
	var today := _today(sim)
	var dawn := false
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"market_sold":
				var f := str(e.get("family", ""))
				if f != "":
					var sales: Dictionary = bk["sales"]
					var dk := str(today)
					if not sales.has(dk):
						sales[dk] = {}
					if not (sales[dk] as Dictionary).has(f):
						sales[dk][f] = {}
					var it := str(e.get("item", ""))
					sales[dk][f][it] = int(sales[dk][f].get(it, 0)) + int(e.get("qty", 1))
			"trial_verdict":
				_on_verdict(sim, e)
			"phase_changed":
				if str(e.get("phase", "")) == "dawn":
					dawn = true
	if dawn:
		_daily(sim, today)
	var fams := _ai_families(st)
	var dawn_at := _phase_start(sim, today, "dawn")
	var stagger := int(cfg(sim).get("attack", {}).get("stagger_minutes", 3))
	var deciding := now >= dawn_at and now <= dawn_at + stagger * fams.size()
	for k: int in fams.size():
		var f: String = fams[k]
		var ai: Variant = st.families[f].get("ai_state")
		var hv: Variant = (ai as Dictionary).get("hostility") if ai is Dictionary else null
		if not deciding and not (hv is Dictionary and ((hv as Dictionary).has("presage") or (hv as Dictionary).has("price_war"))):
			continue  # nothing to decide nor to carry out this minute
		var m := _mem(sim, f)
		if now == dawn_at + stagger * k:
			_decide(sim, f, m, today)
		_run(sim, f, m, now)


static func _phase_start(sim: Sim, day: int, phase: String) -> int:
	var time: Dictionary = sim.catalog.time
	var season := Clock.season(day * Clock.MINUTES_PER_DAY, time)
	return day * Clock.MINUTES_PER_DAY + int(time["phase_starts"][season][phase])


# --- Rivalry ---------------------------------------------------------------------------------------------------------

static func _daily(sim: Sim, today: int) -> void:
	var st := sim.state
	var bk := book(st)
	var rc: Dictionary = cfg(sim).get("rivalry", {})
	var days := int(rc.get("market_days", 2))
	var sales: Dictionary = bk["sales"]
	for dk: String in sales.keys():  # keep the window
		if int(dk) < today - days:
			sales.erase(dk)
	var sold := {}  # fam -> {item: qty} over the window (yesterday and before, not today)
	var total := {}
	for dk: String in sales:
		if int(dk) >= today:
			continue
		for f: String in sales[dk]:
			if not sold.has(f):
				sold[f] = {}
			for it: String in sales[dk][f]:
				sold[f][it] = int(sold[f].get(it, 0)) + int(sales[dk][f][it])
				total[it] = int(total.get(it, 0)) + int(sales[dk][f][it])
	var share := float(rc.get("market_share", 0.5))
	var rivals := _rivals(st)
	for a: String in _ai_families(st):
		var ha := Kin.head(st, a)
		for b: String in rivals:
			if b == a:
				continue
			var rose := false
			for it: String in (sold.get(a, {}) as Dictionary):
				var tot := int(total.get(it, 0))
				if tot > 0 and float((sold.get(b, {}) as Dictionary).get(it, 0)) / float(tot) > share:
					add(sim, a, b, int(rc.get("market_rise", 1)), "cuota de %s" % it)
					rose = true
					break
			var hb := Kin.head(st, b)
			var rel := Emotions.relation(st, ha, hb) if ha != "" and hb != "" else 0
			if rel < int(rc.get("relation_low", -30)):
				add(sim, a, b, int(rc.get("relation_low_rise", 1)), "relación %d" % rel)
				rose = true
			var key := a + "|" + b
			if not rose and int(bk["rose"].get(key, -1)) < today and value(st, a, b) > 0:
				add(sim, a, b, -int(rc.get("decay", 1)), "erosión")
			if rel > int(rc.get("relation_high", 30)) and value(st, a, b) > 0:
				add(sim, a, b, -int(rc.get("relation_high_drop", 1)), "buena relación")
	# a sabotaged building is repaired when its days are over
	for bid: String in st.buildings:
		var bld: Dictionary = st.buildings[bid]
		if bld.has("sabotaged_until") and int(bld["sabotaged_until"]) <= int(st.clock["minute"]):
			bld.erase("sabotaged_until")
			if str(bld.get("state", "")) == "damaged" and int(bld.get("upkeep_debt", 0)) <= 0:
				bld["state"] = "normal"
				sim.events.append({"type": "building_repaired", "building": bid})
				if OS.is_debug_build():
					print("[Hostility] %s reparado tras el sabotaje" % bid)


static func _on_verdict(sim: Sim, e: Dictionary) -> void:
	if str(e.get("verdict", "")) != "guilty":
		return
	var t := Tribunal.trial(sim.state, str(e.get("trial", "")))
	var accused := str(e.get("family", ""))
	var accuser := Money.family_of(sim.state, str(t.get("accuser", "")))
	if accused != "" and accuser != "" and str(sim.state.families.get(accused, {}).get("controlled_by", "")) == "ai":
		add(sim, accused, accuser, int(cfg(sim).get("rivalry", {}).get("trial_rise", 15)), "juicio perdido")


# --- Deciding an attack ------------------------------------------------------------------------------------------------

static func _threshold(sim: Sim, prof: Dictionary) -> int:
	return clampi(int(prof.get("rivalry_threshold", 60)) + int(dcfg(sim).get("threshold_offset", 0)), 20, 95)


static func _decide(sim: Sim, f: String, m: Dictionary, today: int) -> void:
	var st := sim.state
	var prof := _profile(sim, f)
	var ac: Dictionary = cfg(sim).get("attack", {})
	if prof.is_empty() or float(prof.get("aggression", 0.0)) <= 0.0 or m.get("presage") is Dictionary:
		return
	if today < int(ac.get("first_days", 8)):
		return
	if today < int(m.get("last_attack_day", -100000)) + int(dcfg(sim).get("attack_cooldown_days", 8)):
		return
	if (m.get("price_war") is Dictionary) and int(m["price_war"].get("until", 0)) > int(st.clock["minute"]):
		return
	var thr := _threshold(sim, prof)
	var targets: Array = []
	for b: String in _rivals(st):
		if b != f and value(st, f, b) >= thr:
			targets.append(b)
	targets.sort_custom(func(x: String, y: String) -> bool:
		return value(st, f, x) > value(st, f, y) or (value(st, f, x) == value(st, f, y) and x < y))
	targets = targets.slice(0, int(ac.get("targets", 2)))
	var gap := int(dcfg(sim).get("player_attack_gap_days", 2))
	var cands: Array = []
	for b: String in targets:
		if _human(st, b) and today < int(book(st).get("player_attacked_day", -100000)) + gap:
			continue
		for c: Dictionary in _candidates(sim, f, b, prof):
			cands.append(c)
	if cands.is_empty():
		return
	var bias: Dictionary = prof.get("attack_bias", {})
	var hw := float(dcfg(sim).get("hostile_weight", 1.0))
	var sigma := float(dcfg(sim).get("noise", 0.1))
	for c: Dictionary in cands:
		var r := float(value(st, f, str(c["target"]))) / 100.0
		var noise := (Kin.roll(st, "ai|h|%s|%d|%s|%s" % [f, today, c["kind"], c["target"]]) * 2.0 - 1.0) * sigma
		c["u"] = float(bias.get(str(c["kind"]), 0.0)) * hw * (0.5 + float(prof.get("aggression", 0.0))) * r + noise
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["u"]) > float(y["u"]) or (float(x["u"]) == float(y["u"]) and _ck(x) < _ck(y)))
	if OS.is_debug_build():
		var shown: Array = []
		for c: Dictionary in cands.slice(0, 3):
			shown.append("%s→%s u=%.2f" % [c["kind"], c["target"], float(c["u"])])
		print("[Hostility] %s piensa en atacar (umbral %d): %s" % [f, thr, shown])
	var best: Dictionary = cands[0]
	if float(best["u"]) < float(ac.get("u_min", 0.2)):
		return
	_presage(sim, f, m, best)


static func _ck(c: Dictionary) -> String:
	return "%s|%s|%s" % [c["kind"], c["target"], c.get("item", c.get("building", ""))]


## The attacks `f` can make on `b` now (4.21.9.1): [{kind, target, item?, building?}].
static func _candidates(sim: Sim, f: String, b: String, prof: Dictionary) -> Array:
	var st := sim.state
	var out: Array = []
	var bias: Dictionary = prof.get("attack_bias", {})
	if float(bias.get("price_war", 0.0)) > 0.0:
		var item := _war_item(sim, f, b)
		if item != "":
			out.append({"kind": "price_war", "target": b, "item": item})
	if float(bias.get("accuse", 0.0)) > 0.0 and _human(st, b):
		var actor := Kin.head(st, f)
		if actor != "" and not RivalAI.accusation(sim, f, actor, prof).is_empty():
			out.append({"kind": "accuse", "target": b})
	if float(bias.get("sabotage", 0.0)) > 0.0:
		var bld := _workshop_of(st, b)
		if bld != "":
			out.append({"kind": "sabotage", "target": b, "building": bld})
	return out


## The item of a price war of `f` on `b`: one that `f`'s workshop makes and `b` sold in the window (the most sold).
static func _war_item(sim: Sim, f: String, b: String) -> String:
	var home := _workshop_of(sim.state, f)
	if home == "":
		return ""
	var makes := {}
	var btype := str(sim.state.buildings[home].get("type", ""))
	for rid: String in sim.catalog.recipes():
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == btype:
			makes[str(r.get("output", {}).get("item", ""))] = true
	var sold := {}
	for dk: String in book(sim.state)["sales"]:
		for it: String in (book(sim.state)["sales"][dk] as Dictionary).get(b, {}):
			sold[it] = int(sold.get(it, 0)) + int(book(sim.state)["sales"][dk][b][it])
	var best := ""
	for it: String in sold:
		if makes.has(it) and RivalAI.stall_for(sim, it) != "" and (best == "" or int(sold[it]) > int(sold[best])
				or (int(sold[it]) == int(sold[best]) and it < best)):
			best = it
	return best


## The family's first workshop (not a house), sorted by id; "" if none.
static func _workshop_of(st: WorldState, f: String) -> String:
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bd: Dictionary = st.buildings[b]
		if str(bd.get("owner", "")) == f and str(bd.get("type", "")) != "house":
			return b
	return ""


# --- Presage and attack ----------------------------------------------------------------------------------------------

static func _presage(sim: Sim, f: String, m: Dictionary, c: Dictionary) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var today := _today(sim)
	var p := c.duplicate()
	p.erase("u")
	match str(c["kind"]):
		"price_war":
			p["at"] = now + int(cfg(sim).get("price_war", {}).get("presage_minutes", 720))
			if _human(st, str(c["target"])):
				Notices.add(sim, str(c["target"]), Notices.WARNING, "notice.ai_presage_price_war",
					{"family": _name(st, f), "item": str(c["item"])}, "")
		"accuse":
			p["at"] = now  # the accusation is public: its own presage
		"sabotage":
			p["notice_at"] = _phase_start(sim, today, NIGHT)
			p["at"] = _phase_start(sim, today + 1, NIGHT) + 30
	m["presage"] = p
	sim.events.append({"type": "ai_presage", "family": f, "kind": str(c["kind"]), "target": str(c["target"])})
	if OS.is_debug_build():
		print("[Hostility] %s anuncia %s contra %s (rivalidad %d): %s" % [f, c["kind"], c["target"],
			value(st, f, str(c["target"])), p])


static func _name(st: WorldState, f: String) -> String:
	return str(st.families.get(f, {}).get("name", ""))


## Each minute: the notice of a sabotage's presage at nightfall, the attack when its time comes (if still valid),
## the end of a price war.
static func _run(sim: Sim, f: String, m: Dictionary, now: int) -> void:
	var st := sim.state
	if m.get("price_war") is Dictionary and int(m["price_war"].get("until", 0)) <= now:
		if OS.is_debug_build():
			print("[Hostility] %s termina su guerra de precios de %s" % [f, m["price_war"].get("item", "")])
		m.erase("price_war")
	if not m.get("presage") is Dictionary:
		return
	var p: Dictionary = m["presage"]
	if p.has("notice_at") and now >= int(p["notice_at"]):
		p.erase("notice_at")
		if _human(st, str(p["target"])):
			Notices.add(sim, str(p["target"]), Notices.WARNING, "notice.ai_presage_sabotage",
				{"building": str(p["building"])}, str(p["building"]))
	if now < int(p["at"]):
		return
	m.erase("presage")
	if not _still_valid(sim, f, p):
		if OS.is_debug_build():
			print("[Hostility] %s deja %s contra %s: ya no se puede" % [f, p["kind"], p["target"]])
		return
	match str(p["kind"]):
		"price_war":
			m["price_war"] = {"item": str(p["item"]), "target": str(p["target"]),
				"until": now + int(cfg(sim).get("price_war", {}).get("season_days", 2)) * Clock.MINUTES_PER_DAY}
			if _human(st, str(p["target"])):
				Notices.add(sim, str(p["target"]), Notices.WARNING, "notice.ai_price_war",
					{"family": _name(st, f), "item": str(p["item"])}, "")
		"accuse":
			var ai: Dictionary = st.families[f]["ai_state"]
			ai["accuse_now"] = true
			var plan: Array = ai.get("plan", [])
			if plan.is_empty() or str(plan[0]) != "accuse":
				plan.push_front("accuse")
				ai["plan"] = plan
		"sabotage":
			_sabotage(sim, f, p)
	_record(sim, f, p)


static func _still_valid(sim: Sim, f: String, p: Dictionary) -> bool:
	var st := sim.state
	match str(p["kind"]):
		"price_war":
			return _war_item(sim, f, str(p["target"])) == str(p["item"]) or _makes(sim, f, str(p["item"]))
		"accuse":
			var actor := Kin.head(st, f)
			return actor != "" and not RivalAI.accusation(sim, f, actor, _profile(sim, f)).is_empty()
		"sabotage":
			var bld: Dictionary = st.buildings.get(str(p["building"]), {})
			return not bld.is_empty() and str(bld.get("owner", "")) == str(p["target"])
	return false


static func _makes(sim: Sim, f: String, item: String) -> bool:
	var home := _workshop_of(sim.state, f)
	if home == "":
		return false
	var btype := str(sim.state.buildings[home].get("type", ""))
	for rid: String in sim.catalog.recipes():
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == btype and str(r.get("output", {}).get("item", "")) == item:
			return true
	return false


static func _sabotage(sim: Sim, f: String, p: Dictionary) -> void:
	var st := sim.state
	var sc: Dictionary = cfg(sim).get("sabotage", {})
	var bid := str(p["building"])
	var bld: Dictionary = st.buildings[bid]
	var now := int(st.clock["minute"])
	var day := _today(sim)
	var guard := 0.0
	var cuts: Array = sc.get("security_cut", [0.2, 0.4, 0.6])
	var n := _security_level(sim, bid)
	if n > 0:
		guard = float(cuts[mini(n, cuts.size()) - 1])
	var stopped := Kin.roll(st, "ai|sab|%s|%s|%d" % [f, bid, day]) < guard
	var seen := Kin.roll(st, "ai|seen|%s|%s|%d" % [f, bid, day]) < float(sc.get("detect", 0.35))
	p["done"] = not stopped
	if not stopped:
		if str(bld.get("state", "normal")) == "normal":
			bld["state"] = "damaged"
		bld["sabotaged_until"] = now + int(sc.get("repair_days", 2)) * Clock.MINUTES_PER_DAY
		sim.events.append({"type": "building_damaged", "building": bid, "reason": "sabotage"})
		if _human(st, str(p["target"])):
			Notices.add(sim, str(p["target"]), Notices.URGENT, "notice.ai_sabotage", {"building": bid}, bid)
	if seen:
		var who := Kin.head(st, f)
		Tribunal.add_fact(sim, "sabotage", f, who, str(sc.get("charge", "brawl")))
		add(sim, str(p["target"]), f, int(cfg(sim).get("rivalry", {}).get("attack_rise", 30)), "sabotaje visto")
		if _human(st, str(p["target"])):
			Notices.add(sim, str(p["target"]), Notices.URGENT, "notice.ai_sabotage_seen",
				{"building": bid, "family": _name(st, f), "name": str(st.characters.get(who, {}).get("name", ""))}, who)
	if OS.is_debug_build():
		print("[Hostility] %s sabotea %s de %s: %s%s (seguridad %d)" % [f, bid, p["target"],
			"frenado" if stopped else "dañado", ", visto" if seen else "", n])


## The building's finished upgrades of the security branch.
static func _security_level(sim: Sim, bid: String) -> int:
	var n := 0
	for u: Variant in Upgrades.owned(sim.state, bid):
		if str(sim.catalog.upgrade(str(u)).get("branch", "")) == "security":
			n += 1
	return n


static func _record(sim: Sim, f: String, p: Dictionary) -> void:
	var st := sim.state
	var day := _today(sim)
	var bk := book(st)
	var m := _mem(sim, f)
	m["last_attack_day"] = day
	var rec := {"day": day, "minute": int(st.clock["minute"]), "family": f, "kind": str(p["kind"]),
		"target": str(p["target"]), "player": _human(st, str(p["target"]))}
	(bk["attacks"] as Array).append(rec)
	if _human(st, str(p["target"])):
		bk["player_attacked_day"] = day
	sim.events.append({"type": "ai_attack", "family": f, "kind": str(p["kind"]), "target": str(p["target"])})
	if OS.is_debug_build():
		print("[Hostility] ATAQUE %s: %s contra %s (día %d, rivalidad %d)" % [f, p["kind"], p["target"], day,
			value(st, f, str(p["target"]))])


# --- What RivalAI asks ---------------------------------------------------------------------------------------------------

## A price war of `f` on `item`: the demand down to which it sells it now (-1 = none). While its presage runs it keeps
## the item (returns a demand it never reaches).
static func sell_floor(sim: Sim, f: String, item: String) -> float:
	if not on(sim):
		return -1.0
	var m: Dictionary = sim.state.families[f].get("ai_state", {}).get("hostility", {})
	var p: Variant = m.get("presage")
	if p is Dictionary and str((p as Dictionary).get("kind", "")) == "price_war" and str(p.get("item", "")) == item:
		return 99.0
	var w: Variant = m.get("price_war")
	if w is Dictionary and str((w as Dictionary).get("item", "")) == item \
			and int(w.get("until", 0)) > int(sim.state.clock["minute"]):
		return float(cfg(sim).get("price_war", {}).get("min_demand", 0.5))
	return -1.0


## Whether RivalAI may accuse now: anywhere but the hostility maps as always; there, only when an accuse attack asks.
static func may_accuse(sim: Sim, f: String) -> bool:
	if not on(sim):
		return true
	return bool(sim.state.families[f].get("ai_state", {}).get("accuse_now", false))
