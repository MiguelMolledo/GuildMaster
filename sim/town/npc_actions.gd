class_name NpcActions
extends RefCounted
## The player's actions on an NPC (GDD 4.11.5, the NPC's panel): talk, give a gift, flatter, insult, threaten. Orders
## npc_talk, npc_gift, npc_flatter, npc_insult, npc_threaten {actor, target[, item, quality]}. Any family can give them
## (the same orders for the AI). They change the permanent relation between the two characters and may start an
## emotion of the target towards the actor's family. Contract: docs/contratos/h7_ciudad.md. Figures: data/town.json
## "actions" (and "skill_check").
## Memory of "once per day" per pair: relationships[pair] gets talk_npc_day / flatter_day (JSON fields of the entry).

const ACTIONS: Array[String] = ["talk", "gift", "flatter", "insult", "threaten"]


static func order(sim: Sim, o: Dictionary, action: String) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := status(sim, actor, target, action)
	if why != "":
		return Orders.fail(why)
	var cfg: Dictionary = sim.catalog.town.get("actions", {}).get(action, {})
	var fam := str(sim.state.characters[actor].get("family", ""))
	var today := Clock.day(int(sim.state.clock["minute"]))
	var rel := Courtship.relation(sim.state, actor, target)
	var ok := true
	match action:
		"talk":
			rel["talk_npc_day"] = today
			Emotions.change_relation(sim, actor, target, int(cfg.get("relation", 2)), "talk")
		"gift":
			var item := str(o.get("item", ""))
			var q := int(o.get("quality", Inventory.NORMAL))
			var inv: Dictionary = sim.state.characters[actor]["inventory"]
			if Inventory.count(inv, item, q) < 1:
				return Orders.fail("no_item")
			Inventory.remove(inv, item, q, 1)
			var tinv: Dictionary = sim.state.characters[target].get("inventory", {})
			if not tinv.is_empty():
				Inventory.add(tinv, sim.catalog, item, q, 1)  # what does not fit is lost: it was given
			var value := Market.price(sim, item, q, "sell")
			if value > int(cfg.get("grateful_min_value", 50)):
				Emotions.add(sim, target, "grateful", fam)
			else:
				var pts := mini(int(cfg.get("max_relation", 10)), floori(float(value) / maxf(1.0, float(cfg.get("gold_per_point", 5)))))
				Emotions.change_relation(sim, actor, target, maxi(1, pts), "gift")
		"flatter":
			rel["flatter_day"] = today
			var r := SkillCheck.roll(sim, "flatter|%s|%s|%d" % [actor, target, int(sim.state.clock["minute"])],
				SkillCheck.stat(sim, actor, str(cfg.get("actor_stat", "charisma"))),
				SkillCheck.stat(sim, target, str(cfg.get("target_stat", "empathy"))))
			ok = bool(r["success"])
			Emotions.change_relation(sim, actor, target, int(cfg.get("success_relation" if ok else "fail_relation", 0)),
				"flatter")
		"insult":
			Emotions.change_relation(sim, actor, target, int(cfg.get("relation", -10)), "insult")
			Emotions.add(sim, target, str(cfg.get("emotion", "offended")), fam)
		"threaten":
			var r := SkillCheck.roll(sim, "threaten|%s|%s|%d" % [actor, target, int(sim.state.clock["minute"])],
				SkillCheck.stat(sim, actor, str(cfg.get("actor_stat", "martial"))),
				SkillCheck.stat(sim, target, str(cfg.get("target_stat", "martial"))))
			ok = bool(r["success"])
			Emotions.change_relation(sim, actor, target, int(cfg.get("success_relation" if ok else "fail_relation", -5)),
				"threaten")
			Emotions.add(sim, target, str(cfg.get("success_emotion" if ok else "fail_emotion", "")), fam)
	sim.events.append({"type": "npc_action", "actor": actor, "target": target, "action": action, "ok": ok})
	if OS.is_debug_build():
		print("[NpcActions] %s -> %s: %s (%s, relación=%d)" % [actor, target, action, "bien" if ok else "mal",
			Emotions.relation(sim.state, actor, target)])
	return Orders.ok()


## Why `actor` cannot do `action` on `target` now ("" if it can): the UI greys the button with it.
static func status(sim: Sim, actor: String, target: String, action: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.characters.has(target):
		return "unknown_target"
	if actor == target or not Kin.alive(st, target) or not Kin.alive(st, actor):
		return "unknown_target"
	var fa := str(st.characters[actor].get("family", ""))
	if fa != "" and fa == str(st.characters[target].get("family", "")):
		return "same_family"
	if not Kin.is_adult(sim, target):
		return "too_young"
	var today := Clock.day(int(st.clock["minute"]))
	var rel: Variant = st.relationships.get(Ids.pair_key(actor, target))
	var r: Dictionary = rel if rel is Dictionary else {}
	match action:
		"talk":
			if Emotions.refuses_talk(sim, target, fa):
				return "refuses_talk"
			if int(r.get("talk_npc_day", -1)) == today:
				return "already_today"
		"flatter":
			if int(r.get("flatter_day", -1)) == today:
				return "already_today"
		"gift", "insult", "threaten":
			pass
		_:
			return "unknown_order"
	if not in_range(sim, actor, target):
		return "too_far"
	return ""


## Range (actions.range_tiles): inside the same building, or on the map within range of the target (or of the door
## of the building it is in).
static func in_range(sim: Sim, actor: String, target: String) -> bool:
	var st := sim.state
	var a: Dictionary = st.characters[actor]
	var la := str(a.get("location", ""))
	var lt := str(st.characters[target].get("location", ""))
	if la != "":
		return la == lt
	var spot := Courtship.spot(st, target)
	var pa: Array = a.get("position", [0, 0])
	var rng := int(sim.catalog.town.get("actions", {}).get("range_tiles", 3))
	return maxi(absi(int(pa[0]) - int(spot[0])), absi(int(pa[1]) - int(spot[1]))) <= rng


## hail {actor, target} (verificación A8): `target` stops where it is and waits for `actor`, who is walking to it to
## talk, court or challenge. state.town.holds[target] = {by, until}. Released by step_holds when `actor` has nothing
## left to do (it arrived and acted, or its orders were replaced), when actions.hail.wait_minutes run out, or when
## either is dead. A management order: it applies at once, also in pause, and never waits in the actor's queue.
static func order_hail(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	if not st.characters.has(actor) or not st.characters.has(target):
		return Orders.fail("unknown_actor")
	if actor == target:
		return Orders.fail("bad_target")
	if not bool(st.characters[target].get("alive", true)):
		return Orders.fail("dead")
	var mins := int((sim.catalog.town.get("actions", {}).get("hail", {}) as Dictionary).get("wait_minutes", 90))
	var now := int(st.clock["minute"])
	holds(st)[target] = {"by": actor, "until": now + mins, "since": now}
	sim.events.append({"type": "hailed", "actor": actor, "target": target, "until": now + mins})
	if OS.is_debug_build():
		print("[NpcActions] %s llama a %s: le espera hasta el minuto %d" % [actor, target, now + mins])
	return Orders.ok()


static func holds(st: WorldState) -> Dictionary:
	if not st.town.has("holds"):
		st.town["holds"] = {}
	return st.town["holds"]


## Whether `chr` is waiting for somebody now (Movement does not walk it).
static func held(st: WorldState, chr: String) -> bool:
	return (st.town.get("holds", {}) as Dictionary).has(chr)


## Releases the waits that are over (called every step by Movement, before walking).
static func step_holds(sim: Sim) -> void:
	var st := sim.state
	var h: Dictionary = st.town.get("holds", {})
	if h.is_empty():
		return
	var now := int(st.clock["minute"])
	for target: String in h.keys():
		var w: Dictionary = h[target]
		var by := str(w.get("by", ""))
		var a: Dictionary = st.characters.get(by, {})
		var busy := not (a.get("path", []) as Array).is_empty() or not (a.get("order_queue", []) as Array).is_empty()
		var why := ""
		if now >= int(w.get("until", 0)):
			why = "time"
		elif a.is_empty() or not bool(a.get("alive", true)) or not bool(st.characters.get(target, {}).get("alive", true)):
			why = "gone"
		elif not busy and now > int(w.get("since", now)):
			why = "done"
		if why != "":
			h.erase(target)
			sim.events.append({"type": "hail_released", "actor": by, "target": target, "why": why})
			if OS.is_debug_build():
				print("[NpcActions] %s deja de esperar a %s (%s)" % [target, by, why])
