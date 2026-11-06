extends SceneTree
## The scenarios of the verification through the interface (docs/gdd/07_testing.md §7.6, Block D): the starts the
## flows of data/flows/ need to reach the orders no other scenario reaches. Each is built from a scenario that already
## exists (or from a real new game), reproducibly:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_verifica_scenarios.gd
## Same code + same data = same files.
##   patron_treaties  from travel_start: the family is Baron with 3000 gold, Hugo is the Mayor, 45 of reputation in
##                    the hamlet; the hamlet's board has an offer for 2 of one of its dear goods and Hugo carries 3.
##                    The treaties (family and town), the city contracts, buying a building.
##   judge_family     day 9: Hugo (Patrician) is the town's judge; the rival smith is tried for tax evasion after an
##                    inspection and the hearing starts in five minutes: Hugo rules the verdict.
##   school_age       from founder_old: Clara has just turned 8 and her school waits for the family's choice.
##   courtship_gifts  from courtship: Hugo carries two swords and a hammer and the family has 330 gold (the gifts,
##                    equipping the hammer, the wedding feast).
##   festival_eve     from games_gambler: day 0, 11:58; a tournament (joust) is called for tomorrow and its crier is at
##                    12:00 (sponsoring, entering the joust). The family is Citizen.
##   inn_chores       from inn_night: two of the inn's beds are left dirty (making a bed); guests wait to be served.
##   altercation_purse from life_altercation: the family has 200 gold (a bet on the brawl).
##   tavern_for_sale  a real new game (artisan_blacksmith, normal, fixed cast, seed 1) with 3000 gold: the
##                    Taberna-Posada of the town is for sale and the family can buy it.

const OUT: String = "res://data/scenarios"
const HERO: String = "chr_0001"
const FAM: String = "fam_0001"
const RIVAL_FAM: String = "fam_0002"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_verifica_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var ok := _patron_treaties()
	ok = _judge_family() and ok
	ok = _school_age() and ok
	ok = _courtship_gifts() and ok
	ok = _festival_eve() and ok
	ok = _inn_chores() and ok
	ok = _altercation_purse() and ok
	ok = _tavern_for_sale() and ok
	quit(0 if ok else 1)


func _from(id: String) -> Sim:
	var r := NewGame.from_scenario(id)
	if not r["ok"]:
		print("make_verifica_scenarios: %s: %s" % [id, r["error"]])
		return null
	return Sim.new(r["state"], cat)


func _patron_treaties() -> bool:
	var sim := _from("travel_start")
	if sim == null:
		return false
	var st := sim.state
	if st.offices.is_empty():   # travel_start comes from before the government: hand it out as a new game does
		Offices.setup(st, cat)
	st.families[FAM]["title"] = "baron"
	st.families[FAM]["gold"] = 3000
	Offices.take(sim, "mayor", 0, HERO)
	var city := "hamlet"
	Region.add_reputation(sim, city, FAM, 45, "start_scenario")
	var dear := CityTrade.dear_items(sim, city)
	if dear.is_empty():
		print("make_verifica_scenarios: the hamlet has no dear goods")
		return false
	var item := str(dear[0])
	var reward := roundi(float(cat.item(item).get("base_price", 0)) * 2 * 1.4)
	Region.city(sim, city)["board"] = [{"id": Ids.next(st, "rct"), "item": item, "qty": 2, "reward": reward, "days": 4}]
	Inventory.add(st.characters[HERO]["inventory"], cat, item, Inventory.NORMAL, 3)
	for kind: String in ["quota", "exemption"]:
		var why := Treaties.can_sign(sim, FAM, city, kind, item if kind == "quota" else "")
		if why != "":
			print("make_verifica_scenarios: Hugo cannot sign %s in the hamlet: %s" % [kind, why])
			return false
	var town_why := Treaties.can_sign(sim, FAM, city, "exemption", "", "town")
	if town_why != "":
		print("make_verifica_scenarios: the town treaty: %s" % town_why)
		return false
	return _save(sim, "patron_treaties", "Barón y alcalde: los tratados",
		"travel_start con la familia Barón, 3000 de oro, Hugo alcalde y 45 de reputación en la aldea; el tablón de la aldea pide 2 de %s y Hugo lleva 3. Los tratados (de la familia y del pueblo), los encargos de fuera y comprar un edificio (verificación, bloque D)." % SimQuery.item_name(cat, item))


func _judge_family() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_verifica_scenarios: new game: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}
	st.families[FAM]["gold"] = 300
	st.families[FAM]["title"] = "patrician"
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 10 * 60
	Reputation.change(sim, FAM, 40, "start_scenario")
	Offices.take(sim, "judge", 0, HERO)
	var forge := ""
	for b: String in st.buildings:
		if str(st.buildings[b]["owner"]) == RIVAL_FAM and str(st.buildings[b]["type"]) == "forge":
			forge = b
	if forge == "":
		print("make_verifica_scenarios: the rival has no forge")
		return false
	sim.events = [{"type": "inspection", "family": RIVAL_FAM, "building": forge, "caught": true, "escaped": false, "fine": 20}]
	Tribunal.step(sim)
	var open: Array = Tribunal.open_trials(sim)
	if open.is_empty():
		print("make_verifica_scenarios: no trial opened against the rival")
		return false
	var t: Dictionary = open[0]
	st.clock["minute"] = int(t["prep_until"]) - 5
	var hero: Dictionary = st.characters[HERO]
	hero["location"] = ""
	hero["path"] = []
	hero["order_queue"] = []
	hero["position"] = (Titles.service(sim) as Array).duplicate()
	if Tribunal.verdict_status(sim, HERO, str(t["id"]), "innocent") not in ["", "trial_not_in_hearing"]:
		print("make_verifica_scenarios: Hugo cannot rule: %s" % Tribunal.verdict_status(sim, HERO, str(t["id"]), "innocent"))
		return false
	return _save(sim, "judge_family", "Juez de la familia",
		"Día 10: Hugo (familia Patricia) es el juez del pueblo. Al herrero rival lo juzgan por evasión de impuestos tras una inspección y la vista oral empieza en cinco minutos: Hugo preside y dicta el veredicto (verificación, bloque D).")


func _school_age() -> bool:
	var sim := _from("founder_old")
	if sim == null:
		return false
	var st := sim.state
	var clara := ""
	for c: String in st.characters:
		if str(st.characters[c].get("family", "")) == FAM and str(st.characters[c].get("name", "")) == "Clara":
			clara = c
	if clara == "":
		print("make_verifica_scenarios: founder_old has no Clara")
		return false
	var ch: Dictionary = st.characters[clara]
	var age := int(cat.family.get("life", {}).get("school_age", 8))
	ch["birth_day"] = Kin.birth_day_for(age, int(st.clock["minute"]), cat.time)
	ch["profession"] = ""
	ch["assigned"] = ""
	ch["life"] = {"school": "pending"}
	Notices.add(sim, FAM, "info", "notice.school_choice", {"name": str(ch.get("name", ""))}, clara)
	if Kin.age(sim, clara) != age:
		print("make_verifica_scenarios: Clara is %d, not %d" % [Kin.age(sim, clara), age])
		return false
	return _save(sim, "school_age", "Una hija en edad de escuela",
		"founder_old con Clara recién cumplidos los %d: su escuela espera la elección de la familia (el árbol, «Elegir escuela»; verificación, bloque D)." % age)


func _courtship_gifts() -> bool:
	var sim := _from("courtship")
	if sim == null:
		return false
	var st := sim.state
	st.families[FAM]["gold"] = int(st.families[FAM]["gold"]) + 300
	Inventory.add(st.characters[HERO]["inventory"], cat, "sword", Inventory.NORMAL, 2)
	Inventory.add(st.characters[HERO]["inventory"], cat, "hammer", Inventory.NORMAL, 1)
	return _save(sim, "courtship_gifts", "Cortejo con regalos",
		"courtship con 300 de oro más (el banquete de boda) y en la bolsa de Hugo dos espadas y un martillo: los regalos a Agnès y a un vecino y equiparse el martillo (verificación, bloque D).")


func _festival_eve() -> bool:
	var sim := _from("games_gambler")
	if sim == null:
		return false
	var st := sim.state
	st.families[FAM]["title"] = "citizen"
	st.clock["minute"] = 11 * 60 + 58
	Festivals.ensure(st)
	var fid := Festivals._schedule(sim, "tournament", 1, "organized")
	if fid == "":
		print("make_verifica_scenarios: the tournament was not called")
		return false
	return _save(sim, "festival_eve", "La víspera de un torneo",
		"games_gambler (3000 de oro) con la familia Ciudadana: día 0, 11:58; mañana hay torneo y a las 12:00 el pregonero lo anuncia (la carta: patrocinar el banquete o la música, inscribirse en la justa o apostar; verificación, bloque D).")


func _inn_chores() -> bool:
	var sim := _from("inn_night")
	if sim == null:
		return false
	var inn := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["type"]) == "tavern_inn" and str(sim.state.buildings[b]["owner"]) == FAM:
			inn = b
	var beds: Array = Inn.state_of(sim, inn).get("beds", [])
	var n := 0
	for i: int in range(beds.size() - 1, -1, -1):
		if n < 2 and str(beds[i].get("state", "")) == "made":
			beds[i]["state"] = "dirty"
			beds[i]["guest"] = ""
			n += 1
	if n == 0:
		print("make_verifica_scenarios: no bed to leave dirty")
		return false
	return _save(sim, "inn_chores", "La posada: servir y hacer camas",
		"inn_night con dos camas sin hacer: Hugo está en la sala, hay parroquianos esperando a que les sirvan y camas que hacer (verificación, bloque D).")


func _altercation_purse() -> bool:
	var sim := _from("life_altercation")
	if sim == null:
		return false
	sim.state.families[FAM]["gold"] = 200
	return _save(sim, "altercation_purse", "Un altercado con la bolsa llena",
		"life_altercation con 200 de oro: apostar por uno de los que llegan a las manos (verificación, bloque D).")


func _tavern_for_sale() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_verifica_scenarios: new game: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.families[FAM]["gold"] = 3000
	var sale := ""
	for b: String in st.buildings:
		if str(st.buildings[b]["type"]) == "tavern_inn" and str(st.buildings[b].get("owner", "")) == "":
			sale = b
	if sale == "":
		print("make_verifica_scenarios: no Taberna-Posada for sale")
		return false
	return _save(sim, "tavern_for_sale", "La posada en venta",
		"Partida nueva (herrero, normal) con 3000 de oro: la Taberna-Posada del pueblo está en venta y la familia puede comprarla (verificación, bloque D).")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	var meta: Dictionary = st.meta.duplicate() if st.meta is Dictionary else {}
	meta["title"] = title
	meta["description"] = description
	meta["origin"] = "tools/scenarios/make_verifica_scenarios.gd"
	st.meta = meta
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_verifica_scenarios: %s (%s) minuto %d, oro %d" % [id, error_string(e), int(st.clock["minute"]),
		Money.gold(st, FAM)])
	return e == OK
