extends "res://tests/test_case.gd"
## H12.2 in the cities of the region (plantillas; tools/city/organic.py starts, generator.py TEMPLATE stalls): every
## city of Valldaura has the Consulta médica's site (player_clinic, on the player forge's plot, as in town_e) and the
## Boticario's stall (apothecary) on the plaza, so the physician's start plays in any of them: the clinic is the
## family's, patients come and the bandages are bought and sold at the apothecary.

const CITIES: Array[String] = ["capital", "port", "quarry", "hamlet", "abbey"]

var cat := Catalog.load_from()


func test_every_city_has_the_clinic_and_the_apothecary() -> void:
	for city: String in CITIES:
		var m: Dictionary = cat.maps()[str(NewGame.city(cat, city)["map"])]
		check((m["stalls"] as Dictionary).has("apothecary"), "%s: the apothecary's stall" % city)
		var cl: Dictionary = m["buildings"].get("player_clinic", {})
		eq(str(cl.get("type", "")), "clinic", "%s: the Consulta's site" % city)
		eq(cl.get("door", []), m["buildings"]["player_forge"]["door"], "%s: on the player forge's plot (its door)" % city)


func test_the_physician_plays_in_every_city() -> void:
	for city: String in CITIES:
		var r := NewGame.from_start(cat, "scholar_physician", "normal", {"city": city, "cast": "fixed"}, 1)
		check(bool(r.get("ok", false)), "%s: a new game (%s)" % [city, r.get("error", "")])
		if not bool(r.get("ok", false)):
			continue
		var sim := Sim.new(r["state"], cat)
		var st := sim.state
		var clinic := ""
		for id: String in st.buildings:
			if str(st.buildings[id]["type"]) == "clinic":
				clinic = id
		check(clinic != "" and str(st.buildings[clinic]["owner"]) == "fam_0001", "%s: the Consulta is the family's" % city)
		check(Market.price(sim, "bandages", Inventory.NORMAL, "buy") > 0 and RivalAI.stall_for(sim, "bandages") == "apothecary",
			"%s: bandages at the apothecary" % city)
		var came := 0
		for i: int in Clock.MINUTES_PER_DAY:
			for e: Dictionary in sim.step():
				if str(e.get("type", "")) == "service_client_arrived":
					came += 1
		check(came >= 1, "%s: patients come to the Consulta in a day (%d)" % [city, came])
