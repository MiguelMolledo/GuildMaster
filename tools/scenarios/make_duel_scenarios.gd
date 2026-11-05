extends SceneTree
## Builds the duel scenario (docs/gdd/04e_combate.md, docs/contratos/duelo.md) from a real new game
## (artisan_blacksmith, normal, fixed cast, seed 1), so it is reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_duel_scenarios.gd
## Same code + same data = same files. Re-run after changing the start or data/combat.json causes.
##   duel_ready  day 1, 10:00: Hugo and the rival smith in the street by the plaza, a step apart; the rival has just
##               insulted Hugo (offended). Hugo can challenge him for the insult or for the rivalry of the trade (the
##               tutorial's chapter «Duelo», the bot duelist, the smoke script duel).
##   duel_challenged  the same place and hour; Hugo has insulted the rival smith and the rival has just challenged him:
##               the challenge waits for Hugo's answer (the card Aceptar / Rechazar, verificación A5).

const OUT: String = "res://data/scenarios"
const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_duel_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _ready_scenario() and _challenged_scenario() else 1)


func _ready_scenario() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_duel_scenarios: new game: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.clock["minute"] = 10 * 60
	for chr: String in [HERO, RIVAL]:
		var ch: Dictionary = st.characters[chr]
		ch["location"] = ""
		ch["path"] = []
		ch["move_progress"] = 0
		ch["order_queue"] = []
	st.characters[HERO]["position"] = [18, 18]
	st.characters[RIVAL]["position"] = [20, 18]
	sim.events = []
	NpcActions.order(sim, {"actor": RIVAL, "target": HERO}, "insult")
	if Duels.causes(sim, HERO, RIVAL).is_empty():
		print("make_duel_scenarios: Hugo has no cause against the rival")
		return false
	return _save(sim, "duel_ready", "Duelo: el rival te ha insultado",
		"Día 1, 10:00. Hugo y el herrero rival en la calle junto a la plaza; el rival acaba de insultar a Hugo. Se le " +
		"puede retar por la ofensa o por la rivalidad del oficio (capítulo «Duelo», bot duelista, --smoke-script=duel).")


func _challenged_scenario() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.clock["minute"] = 10 * 60
	for chr: String in [HERO, RIVAL]:
		var ch: Dictionary = st.characters[chr]
		ch["location"] = ""
		ch["path"] = []
		ch["move_progress"] = 0
		ch["order_queue"] = []
	st.characters[HERO]["position"] = [18, 18]
	st.characters[RIVAL]["position"] = [20, 18]
	sim.events = []
	NpcActions.order(sim, {"actor": HERO, "target": RIVAL}, "insult")
	var res := Orders.apply(sim, {"type": "duel_challenge", "actor": RIVAL, "target": HERO, "cause": "offense",
		"kind": "first_blood"})
	if not bool(res["ok"]):
		print("make_duel_scenarios: the rival cannot challenge Hugo: %s" % res)
		return false
	sim.events = []
	return _save(sim, "duel_challenged", "Duelo: el rival te reta",
		"Día 1, 10:00. Hugo ha insultado al herrero rival y este le acaba de retar a duelo por la ofensa: el reto espera " +
		"la respuesta de Hugo (la carta Aceptar / Rechazar; sin respuesta, se rechaza a su hora).")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_duel_scenarios.gd"}
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_duel_scenarios: %s -> %s" % [id, error_string(e)])
	return e == OK
