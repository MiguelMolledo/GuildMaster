class_name BotChaosPlayer
extends BotFullPlayer
## The chaotic twin of the full player (docs/gdd/07_testing.md §7.4): the same game and the same coverage, but it
## picks at random. Its goals (court, duel, travel) are taken at random among the ready ones instead of by utility,
## its cards (incidents, microevents) get a random choice, and every few minutes it gives a random valid order of a
## system chosen with a bias towards the ones it touched least (weight 1 / (1 + uses)): moves, buys and sells, work,
## the queue, staff, upgrades, contracts, courtship, the heir, offices, fabricated accusations, duels, trips,
## caravans, treaties, festivals, debt. "Valid" = built from what exists and, where the rules have a status query,
## one that says yes (a refusal can still happen: that is a finding only if it breaks something). Its purpose is to
## break things: tools/full_player.gd checks that nothing hangs, no gold goes below zero, nobody leaves the map and
## every day's save loads back with the same hash. Its randomness is its own RandomNumberGenerator (seeded with the
## seed), never state.rng: the world's dice stay as in any other game.

const CHAOS_ID: String = "chaos_player"
const CHANCE_PER_MINUTE: float = 0.025  # a random order every ~40 game minutes (more and the head never ends a cycle)
const SYSTEMS: Array[String] = ["move", "market", "work", "queue", "staff", "upgrades", "contracts", "courtship",
	"heir", "offices", "tribunal", "duels", "travel", "caravans", "treaties", "festivals", "debt", "transfer"]

const SPENDING: Array[String] = ["market", "staff", "upgrades", "offices", "travel", "caravans", "treaties",
	"festivals", "debt"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var chaos_uses: Dictionary = {}   # system -> random orders given


func _init(s: int = 1) -> void:
	super()
	rng.seed = hash("chaos_%d" % s)


func orders(sim: Sim) -> Array:
	var out: Array = super.orders(sim)
	for o: Dictionary in out:  # its cards get a random answer among the card's choices
		if str(o.get("type", "")) == "resolve_incident":
			var inc := Incidents.find(sim.state, str(o.get("incident", "")))
			var ch: Array = inc.get("card", {}).get("choices", []) if not inc.is_empty() else []
			if not ch.is_empty():
				o["choice"] = str(ch[rng.randi_range(0, ch.size() - 1)])
	if _fam_id != "" and sim.state.ending.is_empty() and Kin.alive(sim.state, ACTOR) and rng.randf() < CHANCE_PER_MINUTE:
		var o := _random_order(sim)
		if not o.is_empty():
			out.append(o)
	return out


## Random goals: any ready one, or the business, with the same odds.
func _decide(sim: Sim) -> void:
	var ready: Array = ["business"]
	if _court_ready(sim) == "":
		ready.append("court")
	if _travel_ready(sim) == "":
		ready.append("travel")
	if _duel_ready(sim) == "":
		ready.append("duel")
	var pick := str(ready[rng.randi_range(0, ready.size() - 1)])
	if pick != "business":
		focus = pick
		_focus_since = _now(sim)
		_trip_stage = ""
		_note(sim, "focus", pick + " (al azar)")


func _microevents(sim: Sim) -> Array:
	var out: Array = []
	for m: Dictionary in Microevents.active_for(sim, _fam_id):
		var id := str(m["id"])
		if _mev_done.has(id):
			continue
		_mev_done[id] = true
		var choices: Array = m.get("choices", [])
		if choices.is_empty():
			continue
		_use("microevents")
		out.append({"type": "resolve_microevent", "actor": ACTOR, "microevent": id,
			"choice": str(choices[rng.randi_range(0, choices.size() - 1)])})
	return out


## One random valid order of a system picked with weight 1 / (1 + uses); {} if that system has nothing to do now.
func _random_order(sim: Sim) -> Dictionary:
	var total := 0.0
	var w: Array = []
	for sname: String in SYSTEMS:
		var x := 1.0 / (1.0 + float(chaos_uses.get(sname, 0)))
		if sname in SPENDING and not _business(sim):
			x = 0.0  # year 1 has no gold to spare: until the start debt is paid, only orders that spend nothing
		w.append(x)
		total += x
	var r := rng.randf() * total
	var pick := SYSTEMS[SYSTEMS.size() - 1]
	for i: int in SYSTEMS.size():
		r -= float(w[i])
		if r <= 0.0:
			pick = SYSTEMS[i]
			break
	var o := _order_of(sim, pick)
	if not o.is_empty():
		chaos_uses[pick] = int(chaos_uses.get(pick, 0)) + 1
	return o


func _order_of(sim: Sim, system: String) -> Dictionary:
	var st := sim.state
	var me := ACTOR
	var ch: Dictionary = st.characters[me]
	var away := Region.is_away(st, me)
	match system:
		"move":
			if away:
				return {}
			var who := _any(Kin.group(st, _fam_id).filter(func(c: String) -> bool: return Kin.is_adult(sim, c) \
				and not Region.is_away(st, c) and (c != me or rng.randf() < 0.3)))
			if who == "":
				return {}
			if str(st.characters[who].get("location", "")) != "":
				return {"type": "exit_building", "actor": who}
			var blds: Array = _sorted(st.buildings.keys())
			var b := _any(blds)
			if rng.randf() < 0.5 and b != "":
				return {"type": "enter_building", "actor": who, "building": b}
			var size: Array = sim.catalog.maps().get(st.map_id, {}).get("size", [10, 10])
			return {"type": "move_to", "actor": who, "tile": [rng.randi_range(0, int(size[0]) - 1),
				rng.randi_range(0, int(size[1]) - 1)]}
		"market":
			if away:
				var c := Travel.in_city(st, me)
				if c == "":
					return {}
				var items: Array = []
				for s: Dictionary in ch["inventory"].get("stacks", []):
					items.append(s)
				if not items.is_empty() and rng.randf() < 0.6:
					var s: Dictionary = items[rng.randi_range(0, items.size() - 1)]
					return {"type": "city_sell", "actor": me, "item": str(s["item"]), "quality": int(s["quality"]),
						"qty": rng.randi_range(1, int(s["qty"]))}
				return {"type": "city_buy", "actor": me, "item": _any(["iron", "coal", "wood", "leather"]),
					"qty": rng.randi_range(1, 3), "max_price": 0}
			var stall := Market.stall_at(sim, me)
			if stall == "":
				var stalls: Array = _sorted((sim.catalog.market.get("stalls", {}) as Dictionary).keys())
				var pickst := _any(stalls)
				if pickst == "" or str(ch.get("location", "")) != "":
					return {} if pickst == "" else {"type": "exit_building", "actor": me}
				return {"type": "move_to", "actor": me, "tile": _service(sim, pickst)}
			var sells: Array = (sim.catalog.market["stalls"][stall].get("sells", []) as Array)
			var buyable: Array = []
			for it: String in _sorted(sim.catalog.items().keys()):
				if str(sim.catalog.item(it).get("market_stall", "")) in sells \
						and not bool(sim.catalog.item(it).get("to_order", false)):
					buyable.append(it)
			if rng.randf() < 0.5:
				for s: Dictionary in ch["inventory"].get("stacks", []):
					if str(sim.catalog.item(str(s["item"])).get("market_stall", "")) in sells:
						return {"type": "sell", "actor": me, "stall": stall, "item": str(s["item"]),
							"quality": int(s["quality"]), "qty": 1}
			var it := _any(buyable)
			if it == "":
				return {}
			var n := Market.max_buy(sim, me, stall, it, Inventory.NORMAL)
			if n <= 0:
				return {}
			return {"type": "buy", "actor": me, "stall": stall, "item": it, "quality": Inventory.NORMAL,
				"qty": rng.randi_range(1, mini(n, 4))}
		"work":
			var loc := str(ch.get("location", ""))
			if loc == "" or not st.buildings.has(loc):
				return {}
			if Production.job_zone(sim, me, loc) != "":
				if rng.randf() < 0.1:
					return {"type": "stop_work", "actor": me}
				return {}  # a cycle under way: it lets it end (cutting every cycle is a game nobody plays)
			var zones: Array = _sorted((st.buildings[loc].get("zones", {}) as Dictionary).keys())
			var z := _any(zones)
			if z == "":
				return {}
			var ok: Array = []
			for opt: Dictionary in Production.recipe_options(sim, me, loc, z):
				if str(opt["status"]) == "ok":
					ok.append(str(opt["recipe"]))
			var rid := _any(ok)
			if rid == "":
				return {}
			var modes: Array = _sorted((sim.catalog.production.get("modes", {}) as Dictionary).keys())
			return {"type": "work_at", "actor": me, "building": loc, "zone": z, "recipe": rid, "mode": _any(modes)}
		"queue":
			var q: Dictionary = st.buildings[FORGE].get("queue", {})
			var entries: Array = []
			for e: Dictionary in q.get("entries", []):
				entries.append(str(e.get("id", "")))
			var roll := rng.randf()
			if roll < 0.4 or entries.is_empty():
				var recs: Array = []
				for rid: String in _sorted(sim.catalog.recipes().keys()):
					var rec: Dictionary = sim.catalog.recipes()[rid]
					if str(rec.get("building", "")) == "forge" and str(rec.get("kind", "craft")) != "commission":
						recs.append(rid)
				return {"type": "queue_add", "actor": me, "building": FORGE, "recipe": _any(recs),
					"qty": [1, 2, 3, 5, -1][rng.randi_range(0, 4)]}
			var e := _any(entries)
			if roll < 0.6:
				return {"type": "queue_remove", "actor": me, "building": FORGE, "entry": e}
			if roll < 0.75:
				return {"type": "queue_move", "actor": me, "building": FORGE, "entry": e, "to": rng.randi_range(0, entries.size() - 1)}
			if roll < 0.9:
				return {"type": "queue_pause", "actor": me, "building": FORGE, "entry": e, "on": rng.randf() < 0.5}
			return {"type": "queue_loop", "actor": me, "building": FORGE, "entry": e, "on": rng.randf() < 0.5}
		"staff":
			var emps: Array = Staff.employees_of(st, FORGE)
			var roll := rng.randf()
			if roll < 0.35:
				var cands: Array = []
				for c: Dictionary in Staff.candidates(sim, me, FORGE):
					if str(c["status"]) == "ok":
						cands.append(str(c["character"]))
				var c := _any(cands)
				return {} if c == "" else {"type": "hire", "actor": me, "building": FORGE, "candidate": c}
			if emps.is_empty():
				return {}
			var e := _any(_sorted(emps))
			if roll < 0.45:
				return {"type": "fire", "actor": me, "employee": e}
			if roll < 0.65:
				return {"type": "bonus", "actor": me, "employee": e}
			if roll < 0.8:
				for x: Dictionary in Staff.employees(sim, FORGE):
					if bool(x["promotion_offered"]):
						return {"type": "promote", "actor": me, "employee": str(x["character"]), "accept": rng.randf() < 0.5}
				return {}
			var roles: Array = ["any"] + _sorted((st.buildings[FORGE].get("zones", {}) as Dictionary).keys()).filter(
				func(z: String) -> bool: return (sim.catalog.employees.get("roles", {}) as Dictionary).has(z))
			return {"type": "set_role", "actor": me, "employee": e, "role": _any(roles)}
		"upgrades":
			var ok: Array = []
			for u: String in _sorted(sim.catalog.upgrades().keys()):
				if Upgrades.status_of(sim, me, FORGE, u) == "available":
					ok.append(u)
			var u := _any(ok)
			return {} if u == "" else {"type": "buy_upgrade", "actor": me, "building": FORGE, "upgrade": u}
		"contracts":
			var view := Contracts.board_view(sim, me)
			if rng.randf() < 0.2:
				var acc: Array = []
				for c: Dictionary in view.get("accepted", []):
					acc.append(str(c["id"]))
				var a := _any(acc)
				return {} if a == "" else {"type": "abandon_contract", "actor": me, "contract": a}
			for c: Dictionary in view.get("open", []):
				if str(c["status"]) == "ok" and rng.randf() < 0.5:
					return {"type": "accept_contract", "actor": me, "contract": str(c["id"])}
			if not Contracts.at_board(sim, me) and not away:
				return {"type": "exit_building", "actor": me} if str(ch.get("location", "")) != "" \
					else {"type": "move_to", "actor": me, "tile": Contracts.board_service(sim)}
			return {}
		"courtship":
			var near: Array = []
			for c: Dictionary in Courtship.candidates(sim, me):
				if str(c["status"]) == "":
					near.append(str(c["character"]))
			var t := _any(near)
			if t == "":
				return {}
			var kinds: Array = ["court_talk", "court_talk", "propose"]
			if not (ch["inventory"].get("stacks", []) as Array).is_empty():
				var s: Dictionary = ch["inventory"]["stacks"][0]
				if rng.randf() < 0.3:
					return {"type": "court_gift", "actor": me, "target": t, "item": str(s["item"]), "quality": int(s["quality"])}
			return {"type": _any(kinds), "actor": me, "target": t}
		"heir":
			var h := Kin.head(st, _fam_id)
			var ok: Array = [""]
			for d: String in Kin.descendants(st, h):
				if Kin.can_inherit(sim, h, d):
					ok.append(d)
			return {"type": "designate_heir", "actor": me, "heir": _any(ok)}
		"offices":
			var levels: Array = _sorted((sim.catalog.politics.get("elections", {}).get("levels", {}) as Dictionary).keys())
			var offs: Array = _sorted(sim.catalog.offices().keys())
			for i: int in 4:
				var off := _any(offs)
				var lv := _any(levels)
				if off != "" and lv != "" and Elections.run_status(sim, me, off, lv) == "":
					return {"type": "run_for_office", "actor": me, "office": off, "level": lv}
			return {}
		"tribunal":
			var fams: Array = _sorted(st.families.keys()).filter(func(f: String) -> bool: return f != _fam_id)
			var f := _any(fams)
			if f == "":
				return {}
			var target := Kin.head(st, f)
			var charges: Array = _sorted((Tribunal.cfg(sim).get("charges", {}) as Dictionary).keys())
			var c := _any(charges)
			if target == "" or c == "" or Tribunal.accuse_status(sim, me, target, "", c, true) != "":
				return {}
			return {"type": "accuse", "actor": me, "target": target, "charge": c, "fabricate": true}
		"duels":
			var mine := Duels.of_character(st, me)
			if not mine.is_empty():
				if str(mine["status"]) == Duels.PENDING and str(mine["challenger"]) == me and rng.randf() < 0.3:
					return {"type": "duel_withdraw", "actor": me, "duel": str(mine["id"])}
				return {}
			var people: Array = []
			for c: String in _sorted(st.characters.keys()):
				if Duels.challenge_status(sim, me, c, "", "first_blood", true) == "":
					people.append(c)
			var t := _any(people)
			if t == "":
				return {}
			var cs: Array = Duels.causes(sim, me, t)
			return {"type": "duel_challenge", "actor": me, "target": t, "cause": str(cs[0]["cause"]) if not cs.is_empty() else "",
				"kind": "first_blood"}
		"travel":
			if Region.is_away(st, me) and Travel.in_city(st, me) == "":
				return {}
			var ok: Array = []
			for s: Dictionary in Region.settlements(sim):
				if Travel.can_travel(sim, me, str(s.get("id", ""))) == "":
					ok.append(str(s["id"]))
			if Travel.in_city(st, me) != "" and rng.randf() < 0.5:
				return {"type": "return", "actor": me}
			var to := _any(ok)
			return {} if to == "" else {"type": "travel", "actor": me, "to": to}
		"caravans":
			if away:
				return {}
			if Caravans.carts(sim, _fam_id) == 0:
				var price := int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
				if Travel.unlock_reason(sim, _fam_id) != "" or not Money.can_pay(st, _fam_id, price):
					return {}
				return {"type": "buy_cart", "actor": me}
			var staff: Array = _sorted(Staff.employees_of(st, FORGE))
			var drv := _any(staff)
			var stacks: Array = st.buildings[FORGE]["inventory"].get("stacks", [])
			if drv == "" or stacks.is_empty():
				return {}
			var s: Dictionary = stacks[rng.randi_range(0, stacks.size() - 1)]
			var cities: Array = []
			for x: Dictionary in Region.settlements(sim):
				if Region.is_city(sim, str(x.get("id", ""))):
					cities.append(str(x["id"]))
			var o := {"type": "caravan_send", "actor": me, "driver": drv, "building": FORGE, "city": _any(cities),
				"cargo": [{"item": str(s["item"]), "quality": int(s["quality"]), "qty": rng.randi_range(1, int(s["qty"])),
				"min_price": 0}], "buy": [], "escort": rng.randf() < 0.5}
			return o if Caravans.can_send(sim, o) == "" else {}
		"treaties":
			var c := Travel.in_city(st, me)
			if c == "":
				return {}
			var kinds: Array = _sorted((sim.catalog.trade.get("treaties", {}).get("kinds", {}) as Dictionary).keys())
			var k := _any(kinds)
			var item := _any(["sword", "nails", "iron_ingot", "horseshoe"])
			if k == "" or Treaties.can_sign(sim, _fam_id, c, k, item) != "":
				return {}
			return {"type": "sign_treaty", "actor": me, "kind": k, "item": item}
		"festivals":
			for inst: Dictionary in Festivals.announced(sim) + Festivals.active(sim):
				var parts: Array = Festivals.sponsor_parts(sim, inst)
				var p := _any(parts.filter(func(x: String) -> bool:
					return not x in (inst.get("sponsors", {}).get(_fam_id, []) as Array) and Money.can_pay(st, _fam_id,
						int(Festivals.rules(sim).get("sponsor", {}).get("parts", {}).get(x, {}).get("gold", 0)))))
				if p != "" and bool(inst.get("announced", false)):
					return {"type": "festival_sponsor", "actor": me, "festival": str(inst["id"]), "part": p}
			return {}
		"debt":
			for id: String in Loans.of_family(sim, _fam_id):
				var s := Loans.status(sim, id)
				if str(s["state"]) in ["active", "extended"] and Money.gold(st, _fam_id) > 0:
					return {"type": "repay_loan", "actor": me, "loan": id,
						"amount": rng.randi_range(1, mini(int(s["outstanding"]), Money.gold(st, _fam_id)))}
			return {}
		"transfer":
			var loc := str(ch.get("location", ""))
			if loc == "" or not st.buildings.has(loc) or not Buildings.owns(st, me, loc):
				return {}
			var from_b := rng.randf() < 0.5
			var inv: Dictionary = st.buildings[loc]["inventory"] if from_b else ch["inventory"]
			var stacks: Array = inv.get("stacks", [])
			if stacks.is_empty():
				return {}
			var s: Dictionary = stacks[rng.randi_range(0, stacks.size() - 1)]
			return {"type": "transfer", "actor": me, "from": loc if from_b else me, "to": me if from_b else loc,
				"item": str(s["item"]), "quality": int(s["quality"]), "qty": rng.randi_range(1, int(s["qty"]))}
	return {}


func _any(a: Array) -> String:
	if a.is_empty():
		return ""
	return str(a[rng.randi_range(0, a.size() - 1)])


func _sorted(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(str(x))
	out.sort()
	return out


func report(sim: Sim) -> Dictionary:
	var r := super.report(sim)
	r["chaos_uses"] = chaos_uses.duplicate()
	return r
