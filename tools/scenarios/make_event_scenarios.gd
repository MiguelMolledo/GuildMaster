extends SceneTree
## Builds the H13 scenario of the seasons and global events (GDD 4.5.3 phase 2, 4.13) from a real new game
## (artisan_blacksmith, normal), so it is reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_event_scenarios.gd
##   season_events  winter, day 7 (year 1), 23:50: a regional war since autumn (until day 13) and a town festival that
##                  ends at midnight; the world seed is the first one whose roll of the next day starts a local event,
##                  so at midnight one notice says the festival is over and another that a new event begins. With
##                  --at=10:00 the market is open: its rows say why each price moves (winter, war, festival).

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const DAY: int = 1440

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_event_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _make() else 1)


func _make() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_event_scenarios: new game: %s" % r["error"])
		return false
	var st: WorldState = r["state"]
	st.loans = {}
	st.families[FAM]["gold"] = 300
	st.clock["minute"] = 6 * DAY + 23 * 60 + 50
	st.events_active = [
		{"id": Ids.next(st, "gev"), "def": "war", "start": 4 * DAY, "end": 12 * DAY, "by": ""},
		{"id": Ids.next(st, "gev"), "def": "festival", "start": 6 * DAY, "end": 7 * DAY, "by": ""},
	]
	var seed := _seed_with_event(st)
	if seed < 0:
		print("make_event_scenarios: no seed starts an event on day 7")
		return false
	st.seed_rng(seed)
	st.meta = {"title": "Estaciones y eventos",
		"description": "Invierno, día 7, 23:50: guerra regional desde el otoño y una fiesta popular que acaba a medianoche; al empezar el día 8 sale otro evento (semilla %d). Con --at=10:00 el mercado abierto dice por qué se mueve cada precio." % seed,
		"origin": "tools/scenarios/make_event_scenarios.gd"}
	var path := OUT.path_join("season_events.json")
	if SaveFile.save(st, path) != OK:
		print("make_event_scenarios: could not write %s" % path)
		return false
	print("make_event_scenarios: %s (seed %d)" % [path, seed])
	return true


## The first seed whose midnight (day 7) ends the festival and starts another event.
func _seed_with_event(st: WorldState) -> int:
	for s: int in range(1, 500):
		var copy: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
		copy.seed_rng(s)
		var sim := Sim.new(copy, cat)
		copy.clock["minute"] = 7 * DAY
		sim.events = [{"type": "day_started", "day": 7}]
		WorldEvents.step(sim)
		for e: Dictionary in sim.events:
			if str(e["type"]) == "world_event_started":
				print("make_event_scenarios: seed %d starts %s on day 7" % [s, e["def"]])
				return s
	return -1
