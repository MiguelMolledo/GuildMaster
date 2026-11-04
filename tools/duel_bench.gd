extends SceneTree
## Measures the duel «a tres tiempos» (docs/gdd/04e_combate.md §2.8; data/combat.json): win / loss / draw of the
## challenger and the lances played for a set of matchups, the automatic way against a player who follows the gesture,
## one who chooses at random and the fixed policies. Pure rules, no world.
##   godot --headless --path . -s tools/duel_bench.gd [-- --n=2000 --kind=first_blood --set=<path>=<json>]
## --set changes a figure of the table for this run only (e.g. --set=read.step=0.07, --set=weapons.sword.touch=10).

var cfg: Dictionary = {}
var n: int = 2000
var kind: String = "first_blood"


func _init() -> void:
	var cat := Catalog.load_from()
	cfg = cat.combat.duplicate(true)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = a.substr(4).to_int()
		elif a.begins_with("--kind="):
			kind = a.substr(7)
		elif a.begins_with("--set="):
			var kv := a.substr(6).split("=", true, 1)
			var path := kv[0].split(".")
			var node: Dictionary = cfg
			for i in path.size() - 1:
				node = node[path[i]]
			node[path[path.size() - 1]] = JSON.parse_string(kv[1])
			print("[DuelBench] --set %s = %s" % [kv[0], kv[1]])
	Duel.verbose = false
	print("[DuelBench] %d duelos por fila, tipo %s" % [n, kind])
	print("| Duelo (retador vs retado) | Gana | Pierde | Tablas | Lances | Sin nada |")
	print("|---|---|---|---|---|---|")
	var plain := {"martial": 3, "empathy": 3, "constitution": 5}
	_row("Iguales (3/3, puños)", _f(plain), _f(plain))
	var weak := {"martial": 3, "empathy": 3, "constitution": 3}
	_row("Iguales con Constitución 3 (el arenero)", _f(weak), _f(weak))
	_row("Arte Marcial 5 vs 3", _f(plain, {"martial": 5}), _f(plain))
	_row("Arte Marcial 7 vs 3", _f(plain, {"martial": 7}), _f(plain))
	_row("Empatía 7 vs 3", _f(plain, {"empathy": 7}), _f(plain))
	_row("Constitución 9 vs 5", _f(plain, {"constitution": 9}), _f(plain))
	for w: String in ["sword", "tool", "dagger", "staff"]:
		_row("%s vs puños" % w, _f(plain, {}, w), _f(plain))
	_row("Espada vs espada y armadura", _f(plain, {}, "sword"), _f(plain, {}, "sword", true))
	_row("Herido vs sano", _f(plain, {}, "fists", false, true), _f(plain))
	_row("Herrero (AM 3, Emp 3, martillo) vs noble (AM 6, Emp 5, espada)",
		_f({"martial": 3, "empathy": 3, "constitution": 5}, {}, "tool"),
		_f({"martial": 6, "empathy": 5, "constitution": 5}, {}, "sword"))
	_row("Pícaro (AM 7, Emp 5, espada) vs vecino (AM 3, Emp 4, Con 4)",
		_f({"martial": 7, "empathy": 5, "constitution": 5}, {}, "sword"), _f({"martial": 3, "empathy": 4, "constitution": 4}))
	_row("Pícaro vs guardia (AM 6, Emp 5, Con 6, espada, armadura)",
		_f({"martial": 7, "empathy": 5, "constitution": 5}, {}, "sword"),
		_f({"martial": 6, "empathy": 5, "constitution": 6}, {}, "sword", true))
	print("")
	print("| Jugador (iguales 3/3) contra la IA | Gana | Pierde | Tablas | Lances | Sin nada |")
	print("|---|---|---|---|---|---|")
	var a := _f(plain)
	var b := _f(plain)
	_row("Resolver sin jugar", a, b)
	_row("Sigue la pista", a, b, "follow")
	_row("Al azar", a, b, "random")
	for act: String in CombatRules.ACTIONS:
		_row("Siempre %s" % act, a, b, act)
	quit(0)


func _f(base: Dictionary, over: Dictionary = {}, weapon: String = "fists", armor: bool = false,
		wounded: bool = false) -> Dictionary:
	var s := base.duplicate()
	s.merge(over, true)
	return CombatRules.fighter("x", s, weapon, armor, wounded)


func _row(label: String, a: Dictionary, b: Dictionary, policy: String = "") -> void:
	var w := 0
	var l := 0
	var lances := 0
	var even := 0
	for s in n:
		var du: Duel
		if policy == "":
			du = Duel.create(cfg, "b%d" % s, 5000 + s, a, b, kind, -1)
		else:
			du = _play(5000 + s, a, b, policy)
		var r := du.result()
		w += int(int(r["winner"]) == 0)
		l += int(int(r["winner"]) == 1)
		lances += int(r["lances"])
		for rec: Dictionary in du.lances_log():
			even += int(str(rec["how"]) == "even")
	print("| %s | %d %% | %d %% | %d %% | %.1f | %d %% |" % [label, roundi(100.0 * w / n), roundi(100.0 * l / n),
		roundi(100.0 * (n - w - l) / n), float(lances) / n, roundi(100.0 * even / maxi(lances, 1))])


func _play(seed: int, a: Dictionary, b: Dictionary, policy: String) -> Duel:
	var du := Duel.create(cfg, "b%d" % (seed - 5000), seed, a, b, kind, 0)
	var guard := 0
	while not du.over() and guard < 64:
		guard += 1
		var v := du.view(0)
		var act := "parry"
		match policy:
			"follow":
				act = CombatRules.ai_choice(cfg, du.fighter(0), du.breath(0), str(v["role"]), str(v["cue"]),
					du.d["history"][1], seed, str(du.d["id"]), int(v["lance"]), 0)
			"random":
				var opts: Array = v["allowed"]
				act = str(opts[floori(CombatRules.roll(seed, "rnd", int(v["lance"]), "pick") * opts.size())])
			_:
				act = policy if policy in (v["allowed"] as Array) else "parry"
		du.choose(0, act)
	return du
