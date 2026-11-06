class_name LiveForge
extends RefCounted
## Forja viva (docs/gdd/03b_diversion_y_ritmo.md §3b.2, O-D1, O-D4): a piece forged by hand as three decisions
## (heat, strikes, quench) taken while its cycle runs. Figures in data/live_forge.json (Catalog.live_forge).
##
## A cycle in mode "live" (work_at with mode "live", only whoever the player controls and only recipes of
## live_forge.recipes) keeps its decisions in job.live:
##   {stage: heat | strike | quench | done, heat: colour | "", strikes: [kind], quench: medium | "", played: bool,
##    verdicts: {heat, strikes, quench: right | near | wrong | ""}, spec: {} (§3b.3: the contract's variant)}
## The order live_forge {actor, building, zone, step: heat | strike | quench | skip | stop, choice} takes one decision;
## skip («Resolver sin jugar») ends them with what was decided; stop interrupts the piece (D11: its inputs back), what
## «Cerrar» does with the piece the forge started on its own after a result (a management order: it applies at once,
## also given in pause, unlike stop_work, which waits behind the work in the actor's queue). The quality is rolled as in mode normal (the same rolls of
## state.rng in the same order, Production.roll_quality) and then moved by the verdicts: without decisions, exactly the
## quality of mode normal. Only after it, and only with the three right, the masterwork roll (one more rng draw).
## A cycle that ends with decisions left waits grace_hours for them. What a family learns (the right colour, the
## template, the quench of each recipe) stays in state.masterworks.learned; the named masterworks in
## state.masterworks.pieces and the chronicle (kind "masterwork").

const MODE: String = "live"
const STEPS: Array[String] = ["heat", "strike", "quench", "skip", "stop"]


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.live_forge


## The live definition of a recipe ({} if it cannot be forged live).
static func recipe_def(sim: Sim, recipe_id: String) -> Dictionary:
	return (cfg(sim).get("recipes", {}) as Dictionary).get(recipe_id, {})


## The mode "live" as Production sees it (duration and craft like normal, no master touch).
static func mode_def(sim: Sim) -> Dictionary:
	return {"duration_mult": float(cfg(sim).get("duration_mult", 1.0)), "craft_delta": 0, "master_touch": false,
		"live": true}


## "" if `actor` may forge `recipe_id` live, else the reason (no_live_forge: the recipe has none; not_by_hand: only
## the characters the player controls forge live, GDD 4.4.5 / §3b.2).
static func start_reason(sim: Sim, actor: String, recipe_id: String) -> String:
	if recipe_def(sim, recipe_id).is_empty():
		return "no_live_forge"
	if str(sim.state.characters.get(actor, {}).get("controlled_by", "")) != "human":
		return "not_by_hand"
	return ""


## The decisions part of a new live job. `spec` (§3b.3): {contract, length, guard, temper} or {}.
static func new_part(spec: Dictionary = {}) -> Dictionary:
	return {"stage": "heat", "heat": "", "strikes": [], "quench": "", "played": false,
		"verdicts": {"heat": "", "strikes": "", "quench": ""}, "spec": spec.duplicate(true)}


## {"type": "live_forge", "actor", "building", "zone", "step": heat | strike | quench | skip, "choice"}.
static func order(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld_id := str(o.get("building", ""))
	var zone := str(o.get("zone", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld_id):
		return Orders.fail("unknown_building")
	var zones: Dictionary = st.buildings[bld_id].get("zones", {})
	if not zones.has(zone):
		return Orders.fail("unknown_station")
	if str(st.characters[actor].get("location", "")) != bld_id or str(st.characters[actor].get("station", "")) != zone:
		return Orders.fail("not_at_station")
	var job: Variant = zones[zone].get("job")
	if not job is Dictionary or str(job["actor"]) != actor or job.get("result") is Dictionary:
		return Orders.fail("not_working")
	var part: Variant = (job as Dictionary).get("live")
	if not part is Dictionary:
		return Orders.fail("not_live")
	var p: Dictionary = part
	var step := str(o.get("step", ""))
	if not step in STEPS:
		return Orders.fail("unknown_step")
	if str(p["stage"]) == "done":
		return Orders.fail("live_done")
	if step == "stop":   # «Cerrar» after a result: the piece the forge started on its own is stopped (D11)
		var returned := Production.interrupt(sim, bld_id, zone)
		sim.events.append({"type": "live_forge_step", "actor": actor, "building": bld_id, "zone": zone, "step": step,
			"choice": "", "verdict": "", "stage": "stopped"})
		if OS.is_debug_build():
			print("[LiveForge] %s para la pieza en %s/%s (devuelto=%s)" % [actor, bld_id, zone, returned])
		return Orders.ok()
	var rdef := recipe_def(sim, str(job["recipe"]))
	var choice := str(o.get("choice", ""))
	var c := cfg(sim)
	var verdict := ""
	match step:
		"skip":
			p["stage"] = "done"
		"heat":
			if str(p["stage"]) != "heat":
				return Orders.fail("wrong_step")
			if not choice in (c.get("heat_colors", []) as Array):
				return Orders.fail("unknown_choice")
			p["heat"] = choice
			verdict = heat_verdict(sim, rdef, choice)
			p["verdicts"]["heat"] = verdict
			p["stage"] = "strike"
		"strike":
			if str(p["stage"]) != "strike":
				return Orders.fail("wrong_step")
			if not choice in (c.get("strike_kinds", []) as Array):
				return Orders.fail("unknown_choice")
			var strikes: Array = p["strikes"]
			var template: Array = template_of(sim, rdef, p)
			verdict = "right" if strikes.size() < template.size() and str(template[strikes.size()]) == choice else "wrong"
			strikes.append(choice)
			if strikes.size() >= template.size():
				p["verdicts"]["strikes"] = strikes_verdict(template, strikes)
				p["stage"] = "quench"
		"quench":
			if str(p["stage"]) != "quench":
				return Orders.fail("wrong_step")
			if not choice in (c.get("quench_media", []) as Array):
				return Orders.fail("unknown_choice")
			p["quench"] = choice
			verdict = "right" if choice == wanted_quench(rdef, p) else "wrong"
			p["verdicts"]["quench"] = verdict
			p["stage"] = "done"
			p["played"] = true
	_learn(sim, actor, str(job["recipe"]), p, step)
	sim.events.append({"type": "live_forge_step", "actor": actor, "building": bld_id, "zone": zone, "step": step,
		"choice": choice, "verdict": verdict, "stage": str(p["stage"])})
	if OS.is_debug_build():
		print("[LiveForge] %s %s=%s en %s/%s (veredicto=%s, etapa=%s)" % [actor, step, choice, bld_id, zone, verdict,
			p["stage"]])
	return Orders.ok()


## right | near | wrong for a pulled colour: the recipe's one is right; a neighbour (not burnt) is near.
static func heat_verdict(sim: Sim, rdef: Dictionary, colour: String) -> String:
	var colours: Array = cfg(sim).get("heat_colors", [])
	if colour == str(rdef.get("heat", "")):
		return "right"
	if colour == str(cfg(sim).get("burnt", "")):
		return "wrong"
	var d := absi(colours.find(colour) - colours.find(str(rdef.get("heat", ""))))
	return "near" if d == 1 else "wrong"


## right (all equal), near (one off) or wrong.
static func strikes_verdict(template: Array, strikes: Array) -> String:
	var off := absi(template.size() - strikes.size())
	for i: int in mini(template.size(), strikes.size()):
		if str(template[i]) != str(strikes[i]):
			off += 1
	return "right" if off == 0 else ("near" if off == 1 else "wrong")


## The strike template of a recipe for a job (the variant of §3b.3 may add strikes: LiveForge.variant_strikes).
static func template_of(sim: Sim, rdef: Dictionary, part: Dictionary) -> Array:
	var t: Array = (rdef.get("strikes", []) as Array).duplicate()
	t.append_array(variant_strikes(sim, part.get("spec", {})))
	return t


## Extra strikes of the variant chosen (§3b.3, data/live_forge.json variants), [] without one.
static func variant_strikes(sim: Sim, spec: Variant) -> Array:
	var out: Array = []
	if not spec is Dictionary:
		return out
	var variants: Dictionary = cfg(sim).get("variants", {})
	for axis: String in ["length", "guard"]:
		var v := str((spec as Dictionary).get(axis, ""))
		if v != "":
			out.append_array(((variants.get(axis, {}) as Dictionary).get(v, {}) as Dictionary).get("strikes_add", []))
	return out


## The quench that is right: the spec's temper (a contract asks for it) or the recipe's.
static func wanted_quench(rdef: Dictionary, part: Dictionary) -> String:
	var t := str((part.get("spec", {}) as Dictionary).get("temper", ""))
	return t if t != "" else str(rdef.get("quench", ""))


## Production.step: a live cycle that reached its end with decisions left waits grace_hours for them.
static func waiting(sim: Sim, job: Dictionary, now: int) -> bool:
	var p: Variant = job.get("live")
	if not p is Dictionary or str((p as Dictionary)["stage"]) == "done":
		return false
	var grace := roundi(float(cfg(sim).get("grace_hours", 0.0)) * 60.0)
	return now < int(job["end"]) + grace


## The steps the verdicts move the quality (+steps_all_right, -steps_wrong or 0).
static func steps_of(sim: Sim, verdicts: Dictionary) -> int:
	var right := 0
	var wrong := 0
	for k: String in ["heat", "strikes", "quench"]:
		match str(verdicts.get(k, "")):
			"right":
				right += 1
			"wrong":
				wrong += 1
	if right == 3:
		return int(cfg(sim).get("steps_all_right", 1))
	if wrong >= int(cfg(sim).get("wrong_for_penalty", 2)):
		return -int(cfg(sim).get("steps_wrong", 1))
	return 0


## Production.step, after rolling `base` as mode normal: the final quality, traits and masterwork of a live job.
## Returns {quality, base, steps, traits: [id], masterwork: mw id | ""}.
static func resolve(sim: Sim, actor: String, bld_id: String, job: Dictionary, base: int) -> Dictionary:
	var p: Dictionary = job["live"]
	var verdicts: Dictionary = p.get("verdicts", {})
	var steps := steps_of(sim, verdicts)
	var q := clampi(base + steps, 0, Inventory.EXCELLENT)
	var traits: Array = []
	var tids: Dictionary = cfg(sim).get("traits", {})
	if str(verdicts.get("quench", "")) == "right" and tids.has("quench_" + str(p["quench"])):
		traits.append(str(tids["quench_" + str(p["quench"])]))
	if str(verdicts.get("strikes", "")) == "right" and tids.has("strikes_right"):
		traits.append(str(tids["strikes_right"]))
	var mw := ""
	var all_right := steps > 0 and str(verdicts.get("heat", "")) == "right"
	var mcfg: Dictionary = cfg(sim).get("masterwork", {})
	var craft := int(sim.state.characters.get(actor, {}).get("stats", {}).get("craft", 0))
	if all_right and tids.has("all_right"):
		traits.append(str(tids["all_right"]))
	# Equilibrio (03b §3b.2, 2026-11-05): a masterwork asks for practice too: the family must have made `practice`
	# perfect pieces of this recipe before (masterworks.practice[fam][recipe], counted here); the rng is drawn only
	# then, so a game before the threshold rolls the same dice as without masterworks
	var practiced := _practice(sim, actor, str(job["recipe"]), all_right)
	if all_right and craft >= int(mcfg.get("min_craft", 99)) and practiced >= int(mcfg.get("practice", 0)) \
			and sim.state.rng.randf() < float(mcfg.get("chance", 0.0)):
		q = Inventory.EXCELLENT
		mw = _masterwork(sim, actor, bld_id, job, traits)
	sim.events.append({"type": "live_forge_done", "actor": actor, "building": bld_id, "recipe": str(job["recipe"]),
		"quality": q, "base": base, "steps": steps, "traits": traits.duplicate(), "masterwork": mw,
		"played": bool(p.get("played", false)), "spec": (p.get("spec", {}) as Dictionary).duplicate(true)})
	if OS.is_debug_build():
		print("[LiveForge] %s termina %s: base=%d pasos=%+d calidad=%d rasgos=%s obra=%s" % [actor, job["recipe"], base,
			steps, q, traits, mw])
	return {"quality": q, "base": base, "steps": steps, "traits": traits, "masterwork": mw}


## The mode the next cycle repeats in: live only if this one was played to the end (the quench); else normal.
static func next_mode(job: Dictionary) -> String:
	var p: Variant = job.get("live")
	if p is Dictionary:
		return MODE if bool((p as Dictionary).get("played", false)) else "normal"
	return str(job.get("mode", "normal"))


## The spec a repeated cycle keeps (a contract's variant, §3b.3).
static func spec_of(job: Dictionary) -> Dictionary:
	var p: Variant = job.get("live")
	return ((p as Dictionary).get("spec", {}) as Dictionary).duplicate(true) if p is Dictionary else {}


static func _masterwork(sim: Sim, actor: String, bld_id: String, job: Dictionary, traits: Array) -> String:
	var st := sim.state
	_ensure(st)
	var patrons: Array = cfg(sim).get("patrons", [])
	var patron := str(patrons[st.rng.randi() % patrons.size()]) if not patrons.is_empty() else ""
	var id := Ids.next(st, "mw")
	var fam := str(st.characters.get(actor, {}).get("family", ""))
	var item := str(sim.catalog.recipes().get(str(job["recipe"]), {}).get("output", {}).get("item", ""))
	var piece := {"id": id, "item": item, "recipe": str(job["recipe"]), "maker": actor, "family": fam,
		"building": bld_id, "minute": int(st.clock["minute"]), "patron": patron,
		"family_name": str(st.families.get(fam, {}).get("name", "")), "traits": traits.duplicate(), "status": "kept"}
	(st.masterworks["pieces"] as Array).append(piece)
	Chronicle.add(st, "masterwork", {"family": fam, "actor": actor, "masterwork": id, "item": item, "patron": patron,
		"family_name": piece["family_name"]})
	sim.events.append({"type": "masterwork_made", "family": fam, "actor": actor, "masterwork": id, "item": item,
		"patron": patron})
	Notices.add(sim, fam, Notices.INFO, "notice.masterwork", {"item": item, "patron": patron,
		"family_name": piece["family_name"]})
	if OS.is_debug_build():
		print("[LiveForge] obra maestra %s: %s de %s de los %s" % [id, item, patron, piece["family_name"]])
	return id


## What the family learns from a decision that came out right (the recipe sheet remembers it, §3b.2).
static func _learn(sim: Sim, actor: String, recipe_id: String, p: Dictionary, step: String) -> void:
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	if fam == "":
		return
	var v: Dictionary = p.get("verdicts", {})
	var put := {}
	if step == "heat" and str(v.get("heat", "")) == "right":
		put["heat"] = str(p["heat"])
	elif step == "strike" and str(v.get("strikes", "")) == "right" and (p.get("spec", {}) as Dictionary).is_empty():
		put["strikes"] = (p["strikes"] as Array).duplicate()
	elif step == "quench" and str(v.get("quench", "")) == "right" and str((p.get("spec", {}) as Dictionary).get(
			"temper", "")) == "":
		put["quench"] = str(p["quench"])
	if put.is_empty():
		return
	_ensure(sim.state)
	var learned: Dictionary = sim.state.masterworks["learned"]
	if not learned.get(fam) is Dictionary:
		learned[fam] = {}
	if not (learned[fam] as Dictionary).get(recipe_id) is Dictionary:
		learned[fam][recipe_id] = {}
	(learned[fam][recipe_id] as Dictionary).merge(put, true)
	sim.events.append({"type": "live_forge_learned", "family": fam, "recipe": recipe_id, "what": put.keys()[0]})


## The perfect pieces (the three decisions right) of `recipe_id` the actor's family made before this one; counts this
## one when `perfect`. State: masterworks.practice {fam: {recipe: n}} (read with defaults: no save version).
static func _practice(sim: Sim, actor: String, recipe_id: String, perfect: bool) -> int:
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	_ensure(sim.state)
	if not sim.state.masterworks.get("practice") is Dictionary:
		sim.state.masterworks["practice"] = {}
	var pr: Dictionary = sim.state.masterworks["practice"]
	if not pr.get(fam) is Dictionary:
		pr[fam] = {}
	var before := int((pr[fam] as Dictionary).get(recipe_id, 0))
	if perfect:
		pr[fam][recipe_id] = before + 1
	return before


static func _ensure(st: WorldState) -> void:
	if not st.masterworks.get("pieces") is Array:
		st.masterworks["pieces"] = []
	if not st.masterworks.get("learned") is Dictionary:
		st.masterworks["learned"] = {}


# --- Queries (UI) ----------------------------------------------------------------------------------------------------

## What the family of `actor` knows of a recipe: {heat, strikes, quench} (only what it learned).
static func learned(sim: Sim, actor: String, recipe_id: String) -> Dictionary:
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var l: Variant = (sim.state.masterworks.get("learned", {}) as Dictionary).get(fam, {})
	return ((l as Dictionary).get(recipe_id, {}) as Dictionary).duplicate(true) if l is Dictionary else {}


## The live job at a station for the screen: {} or {actor, recipe, stage, heat, strikes, quench, verdicts, played,
## template_size, template (the strikes the player may see: all with template_craft or learned, else ""), near_heat
## (the colour one before the right one when craft >= hint_craft, else ""), learned, hint_key, spec, wanted_temper
## (the spec's, "" if none), progress 0..1, waiting (the cycle ended and waits for the decisions)}.
static func view(sim: Sim, bld_id: String, zone: String) -> Dictionary:
	var job: Variant = sim.state.buildings.get(bld_id, {}).get("zones", {}).get(zone, {}).get("job")
	if not job is Dictionary or not (job as Dictionary).get("live") is Dictionary:
		return {}
	var j: Dictionary = job
	var p: Dictionary = j["live"]
	var actor := str(j["actor"])
	var rdef := recipe_def(sim, str(j["recipe"]))
	var c := cfg(sim)
	var craft := int(sim.state.characters.get(actor, {}).get("stats", {}).get("craft", 0))
	var know := learned(sim, actor, str(j["recipe"]))
	var template := template_of(sim, rdef, p)
	var shown: Array = []
	var see_all := craft >= int(c.get("template_craft", 99)) or (know.has("strikes") and (p["spec"] as Dictionary).is_empty())
	for i: int in template.size():
		shown.append(str(template[i]) if see_all else "")
	var near := ""
	var colours: Array = c.get("heat_colors", [])
	var right_i := colours.find(str(rdef.get("heat", "")))
	if craft >= int(c.get("hint_craft", 99)) and right_i > 0:
		near = str(colours[right_i - 1])
	var now := int(sim.state.clock["minute"])
	var span := maxi(1, int(j["end"]) - int(j["start"]))
	return {"actor": actor, "recipe": str(j["recipe"]), "stage": str(p["stage"]), "heat": str(p["heat"]),
		"strikes": (p["strikes"] as Array).duplicate(), "quench": str(p["quench"]),
		"verdicts": (p["verdicts"] as Dictionary).duplicate(), "played": bool(p.get("played", false)),
		"template_size": template.size(), "template": shown, "near_heat": near, "learned": know,
		"hint_key": str(rdef.get("hint_key", "")), "spec": (p["spec"] as Dictionary).duplicate(true),
		"wanted_temper": str((p["spec"] as Dictionary).get("temper", "")),
		"progress": clampf(float(now - int(j["start"])) / span, 0.0, 1.0), "waiting": now >= int(j["end"])}


## The named masterworks of a family (or all with fam ""), oldest first.
static func masterworks_of(state: WorldState, fam: String) -> Array:
	var out: Array = []
	for m: Variant in state.masterworks.get("pieces", []):
		if m is Dictionary and (fam == "" or str((m as Dictionary).get("family", "")) == fam):
			out.append((m as Dictionary).duplicate(true))
	return out


# --- Contracts with specs (§3b.3, O-D5) ------------------------------------------------------------------------------
## Some random contracts of a table with `specs` ask for a variant: contract.spec = {id, length?, guard?, temper?}
## (what the client wants, in words on the board: spec.<id>), contract.spec_pay (the extra for every piece made to it),
## contract.made = [{quality, qty, building}] (the pieces made to it, kept apart for the client). Making to a spec:
## work_at with "contract" and "variant" {length, guard, temper (only out of live: in live the quench decides)}. A
## piece that matches (the axes the client names, and its quality >= the minimum) goes to contract.made, not to the
## storage; one that does not goes to the storage like any other. Delivering takes contract.made first (spec_pay per
## piece of it) and the rest from the bag: a contract can always be delivered the plain way (no penalty, §3b.5.5).
## Attaching a spec uses an RNG of its own seeded with the world seed and the contract id: state.rng does not move.

const AXES: Array[String] = ["length", "guard"]


## The axes a recipe's variant may choose (data/live_forge.json recipe_axes), temper apart.
static func axes_of(sim: Sim, recipe_id: String) -> Array:
	return ((cfg(sim).get("recipe_axes", {}) as Dictionary).get(recipe_id, []) as Array).duplicate()


## work_at: "" or why a "contract" + "variant" cannot be made.
static func spec_reason(sim: Sim, actor: String, recipe_id: String, o: Dictionary) -> String:
	var cid := str(o.get("contract", ""))
	if cid == "":
		return ""
	var c := accepted_contract(sim, actor, cid)
	if c.is_empty():
		return "not_your_contract"
	if not c.get("spec") is Dictionary or (c["spec"] as Dictionary).is_empty():
		return "no_spec"
	var out := str(sim.catalog.recipes().get(recipe_id, {}).get("output", {}).get("item", ""))
	if out != str(c.get("item", "")):
		return "wrong_item"
	if recipe_def(sim, recipe_id).is_empty():
		return "no_live_forge"
	var variant: Variant = o.get("variant", {})
	if not variant is Dictionary:
		return "bad_variant"
	var axes := axes_of(sim, recipe_id)
	var variants: Dictionary = cfg(sim).get("variants", {})
	for k: String in (variant as Dictionary).keys():
		var v := str((variant as Dictionary)[k])
		if k == "temper":
			if v != "" and not v in (cfg(sim).get("quench_media", []) as Array):
				return "bad_variant"
		elif not k in axes or (v != "" and not (variants.get(k, {}) as Dictionary).has(v)):
			return "bad_variant"
	return ""


## The spec of a work_at already validated (spec_reason): {} or {contract, length, guard, temper, want}.
static func order_spec(sim: Sim, o: Dictionary) -> Dictionary:
	var cid := str(o.get("contract", ""))
	if cid == "":
		return {}
	var c := accepted_contract(sim, str(o.get("actor", "")), cid)
	var variant: Dictionary = o.get("variant", {}) if o.get("variant") is Dictionary else {}
	var spec := {"contract": cid, "want": (c.get("spec", {}) as Dictionary).duplicate(true)}
	for k: String in AXES + ["temper"]:
		spec[k] = str(variant.get(k, ""))
	if str(o.get("mode", "normal")) == MODE:
		spec["temper"] = ""  # in live the quench decides
	return spec


## The duration multiplier of a spec's variant (data/live_forge.json variants.<axis>.<value>.duration_mult).
static func spec_duration_mult(sim: Sim, spec: Dictionary) -> float:
	var m := 1.0
	var variants: Dictionary = cfg(sim).get("variants", {})
	for axis: String in AXES:
		var v := str(spec.get(axis, ""))
		if v != "":
			m *= float(((variants.get(axis, {}) as Dictionary).get(v, {}) as Dictionary).get("duration_mult", 1.0))
	return m


## The contract `cid` accepted by the family of `actor` (a reference into the state), {} if none.
static func accepted_contract(sim: Sim, actor: String, cid: String) -> Dictionary:
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	for c: Dictionary in sim.state.contracts.get("accepted", []):
		if str(c.get("id", "")) == cid and fam != "" and str(c.get("family", "")) == fam:
			return c
	return {}


static func job_spec(job: Dictionary) -> Dictionary:
	var p: Variant = job.get("live")
	if p is Dictionary:
		return (p as Dictionary).get("spec", {})
	return job.get("spec", {}) if job.get("spec") is Dictionary else {}


## Whether the finished piece of `job` matches its contract's want: {match: bool, why: "" | axis}.
static func spec_match(job: Dictionary) -> Dictionary:
	var spec := job_spec(job)
	var want: Dictionary = spec.get("want", {})
	for axis: String in AXES:
		if want.has(axis) and str(want[axis]) != str(spec.get(axis, "")):
			return {"match": false, "why": axis}
	if want.has("temper"):
		var t := str(spec.get("temper", ""))
		var p: Variant = job.get("live")
		if p is Dictionary:
			t = str((p as Dictionary).get("quench", ""))
		if t != str(want["temper"]):
			return {"match": false, "why": "temper"}
	return {"match": true, "why": ""}


## Production.step: a piece made to a contract's spec that matches goes to contract.made (true); else false (the
## storage takes it as always). Emits spec_piece {actor, contract, match, why, quality}.
static func contract_takes(sim: Sim, bld_id: String, job: Dictionary, res: Dictionary) -> bool:
	var spec := job_spec(job)
	if spec.is_empty() or bool(job.get("spec_done", false)):
		return false
	job["spec_done"] = true  # judged once (a blocked job retries every minute)
	var actor := str(job["actor"])
	var c := accepted_contract(sim, actor, str(spec.get("contract", "")))
	var m := spec_match(job)
	var why := str(m["why"])
	if c.is_empty():
		why = "contract_gone"
	elif int(res["quality"]) < int(c.get("min_quality", 0)):
		why = "quality"
	elif crate_units(c, -1) >= int(c.get("qty", 1)):
		why = "full"
	var ok := why == "" and bool(m["match"])
	if ok:
		if not c.get("made") is Array:
			c["made"] = []
		(c["made"] as Array).append({"quality": int(res["quality"]), "qty": int(res["qty"]), "building": bld_id})
	sim.events.append({"type": "spec_piece", "actor": actor, "contract": str(spec.get("contract", "")),
		"match": ok, "why": why, "quality": int(res["quality"]), "item": str(res["item"])})
	if OS.is_debug_build():
		print("[LiveForge] pieza para %s: %s (motivo=%s)" % [spec.get("contract", ""), "apartada" if ok else "al almacén",
			why])
	return ok


## The spec a repeated cycle keeps: the job's while its contract still wants pieces, else {}.
static func repeat_spec(sim: Sim, job: Dictionary) -> Dictionary:
	var spec := job_spec(job).duplicate(true)
	if spec.is_empty():
		return {}
	var c := accepted_contract(sim, str(job["actor"]), str(spec.get("contract", "")))
	if c.is_empty() or crate_units(c, -1) >= int(c.get("qty", 1)):
		return {}
	return spec


## Units kept in contract.made with quality >= min_q (-1: all).
static func crate_units(c: Dictionary, min_q: int) -> int:
	var n := 0
	for m: Variant in c.get("made", []):
		if m is Dictionary and int((m as Dictionary).get("quality", 0)) >= min_q:
			n += int((m as Dictionary).get("qty", 0))
	return n


## The extra a delivery of `units` pieces made to the spec earns: spec_pay × units / qty, rounded.
static func spec_bonus(c: Dictionary, units: int) -> int:
	if units <= 0:
		return 0
	return roundi(float(c.get("spec_pay", 0)) * float(units) / float(maxi(1, int(c.get("qty", 1)))))


## Contracts.order_deliver: takes up to `units` pieces from contract.made (best kept first is not needed: they are
## all >= min quality). Returns how many it took.
static func take_crate(c: Dictionary, units: int) -> int:
	var left := units
	var made: Array = c.get("made", [])
	for i: int in range(made.size() - 1, -1, -1):
		if left == 0:
			break
		var m: Dictionary = made[i]
		if int(m.get("quality", 0)) < int(c.get("min_quality", 0)):
			continue
		var t := mini(left, int(m.get("qty", 0)))
		m["qty"] = int(m["qty"]) - t
		left -= t
		if int(m["qty"]) <= 0:
			made.remove_at(i)
	return units - left


## A contract that closes with pieces still kept (failed, or delivered with extra): they go back to the storage of the
## building where they were made, or to its first station's floor if they do not fit.
static func return_crate(sim: Sim, c: Dictionary) -> void:
	if not c.has("made"):
		return
	var item := str(c.get("item", ""))
	for m: Variant in c.get("made", []):
		if not m is Dictionary or int((m as Dictionary).get("qty", 0)) <= 0:
			continue
		var b := str((m as Dictionary).get("building", ""))
		if not sim.state.buildings.has(b):
			continue
		var q := int(m["quality"])
		var n := int(m["qty"])
		var bld: Dictionary = sim.state.buildings[b]
		if Inventory.add(bld["inventory"], sim.catalog, item, q, n):
			continue
		var zones: Array = (bld.get("zones", {}) as Dictionary).keys()
		zones.sort()
		if zones.is_empty():
			continue
		var z: Dictionary = bld["zones"][str(zones[0])]
		if not z.get("floor") is Array:
			z["floor"] = []
		(z["floor"] as Array).append({"item": item, "quality": q, "qty": n})
	c["made"] = []


## Contracts.post_random: maybe gives the contract just posted one of its table's specs (spec_chance), with an RNG of
## its own (the world seed and the contract id), so state.rng and every other draw stay as they were.
static func attach_spec(sim: Sim, cid: String, table: Dictionary) -> void:
	var specs: Array = []
	var c: Dictionary = {}
	for k: Dictionary in sim.state.contracts.get("board", []):
		if str(k.get("id", "")) == cid:
			c = k
	if c.is_empty():
		return
	for s: Variant in table.get("specs", []):
		if s is Dictionary and str((s as Dictionary).get("item", "")) == str(c.get("item", "")):
			specs.append(s)
	if specs.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%s" % [str(sim.state.world_seed), cid])
	if r.randf() >= float(table.get("spec_chance", 0.0)):
		return
	var s: Dictionary = specs[r.randi_range(0, specs.size() - 1)]
	var want: Dictionary = (s.get("want", {}) as Dictionary).duplicate(true)
	want["id"] = str(s.get("id", ""))
	c["spec"] = want
	c["spec_pay"] = roundi(float(c.get("pay", 0)) * float(table.get("spec_bonus", 0.0)))
	c["made"] = []
	sim.events.append({"type": "contract_spec", "contract": cid, "spec": str(want["id"])})
	if OS.is_debug_build():
		print("[LiveForge] el encargo %s pide variante %s (+%d)" % [cid, want, int(c["spec_pay"])])
