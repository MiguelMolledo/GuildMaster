class_name WorkshopFame
extends RefCounted
## The fame of a workshop (Equilibrio 13, docs/decisiones.json; GDD 04g §4.6.5.7): a multiplier 0.5-2.0, 1 at the
## start, the fame(b) of the comarca's clientele. Figures: data/town.json "workshop_fame" [balance].
##
## fame = clamp(1 + quality × quality_weight + renown, min, max), where quality is the mean quality (0 normal, 1 good,
## 2 excellent) of what the workshop sold in the last window_days (market sales by its family and its counter's), and
## renown adds points per fact and decays by decay_per_day at each dawn: a masterwork, a contract done (more for a
## festival one), a contest won (fiestas: buildings[b].contests_won from FestivalCourt._judge, read on its
## festival_contest event) up; a contract failed and a
## complaint (a counter customer who leaves unserved or with nothing to buy) down.
## A family's facts with no building (market sales, contracts, masterworks) go to its main workshop: its first own
## building with an upgrade tree that is not the Taberna-Posada (which has its own fame, 4.27).
## State: buildings[b].fame {renown, sold: [[day, quality, qty]]} (read with defaults: no save version).
## Read by: Counter (the interval between customers and the price).

const POINTS: Array[String] = ["masterwork", "contract_done", "festival_contract_done", "contest_won", "contract_failed",
	"complaint"]


static func _cfg(sim: Sim) -> Dictionary:
	return sim.catalog.town.get("workshop_fame", {})


## The fame of `bld` (1.0 for a building that is not a workshop, or with no figures).
static func of(sim: Sim, bld: String) -> float:
	var cfg := _cfg(sim)
	var b: Dictionary = sim.state.buildings.get(bld, {})
	if cfg.is_empty() or b.is_empty():
		return 1.0
	var f: Dictionary = b.get("fame", {}) if b.get("fame") is Dictionary else {}
	var q := mean_quality(sim, bld)
	var v := 1.0 + q * float(cfg.get("quality_weight", 0.25)) + float(f.get("renown", 0.0))
	return clampf(v, float(cfg.get("min", 0.5)), float(cfg.get("max", 2.0)))


## The mean quality of what `bld` sold in the last window_days (0 if nothing).
static func mean_quality(sim: Sim, bld: String) -> float:
	var f: Variant = sim.state.buildings.get(bld, {}).get("fame")
	if not f is Dictionary:
		return 0.0
	var from := Clock.day(int(sim.state.clock["minute"])) - int(_cfg(sim).get("window_days", 4)) + 1
	var n := 0
	var sum := 0.0
	for r: Variant in (f as Dictionary).get("sold", []):
		if int(r[0]) >= from:
			n += int(r[2])
			sum += float(r[1]) * int(r[2])
	return sum / n if n > 0 else 0.0


## A fact of `kind` (one of POINTS) for `bld`: its points to the renown.
static func add(sim: Sim, bld: String, kind: String, times: int = 1) -> void:
	var cfg := _cfg(sim)
	if cfg.is_empty() or not sim.state.buildings.has(bld):
		return
	var f := _mem(sim.state, bld)
	var pts := float(cfg.get("points", {}).get(kind, 0.0)) * times
	var lim := float(cfg.get("renown_max", 0.75))
	f["renown"] = clampf(float(f.get("renown", 0.0)) + pts, -lim, lim)
	if OS.is_debug_build():
		print("[WorkshopFame] %s: %s %+.2f (renombre=%.2f, fama=%.2f)" % [bld, kind, pts, float(f["renown"]), of(sim, bld)])


static func _mem(st: WorldState, bld: String) -> Dictionary:
	var b: Dictionary = st.buildings[bld]
	if not b.get("fame") is Dictionary:
		b["fame"] = {"renown": 0.0, "sold": []}
	return b["fame"]


## The family's main workshop: its first own building with an upgrade tree, not the Taberna-Posada ("" if none).
static func main_workshop(sim: Sim, fam: String) -> String:
	var st := sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(st.buildings[b].get("owner", "")) != fam or Inn.is_inn(sim, b):
			continue
		if Upgrades.tree_of(sim, b) != "":
			return b
	return ""


## Every minute: the facts of the step's events; at dawn, the renown decays and the old sales go.
static func step(sim: Sim) -> void:
	var cfg := _cfg(sim)
	if cfg.is_empty():
		return
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	for e: Dictionary in sim.events:
		var t := str(e["type"])
		match t:
			"market_sold":
				_sold(sim, main_workshop(sim, str(e.get("family", ""))), today, int(e.get("quality", 0)),
					int(e.get("qty", 1)))
			"counter_sold":
				_sold(sim, str(e.get("building", "")), today, int(e.get("quality", 0)), 1)
			"customer_left":
				if str(e.get("reason", "")) in (cfg.get("complaints", ["nobody", "no_product"]) as Array):
					add(sim, str(e.get("building", "")), "complaint")
			"contract_delivered":
				_fam_fact(sim, str(e.get("family", "")), "contract_done")
			"festival_contract_done":
				_fam_fact(sim, str(e.get("family", "")), "festival_contract_done")
			"contract_failed":
				_fam_fact(sim, str(e.get("family", "")), "contract_failed")
			"masterwork_made":
				_fam_fact(sim, str(e.get("family", "")), "masterwork")
			"festival_contest":  # fiestas (FestivalCourt._judge): buildings[b].contests_won counts the wins
				_contests(sim)
			"contest_won":  # a contest won with the workshop's piece (the building, else the family's)
				if st.buildings.has(str(e.get("building", ""))):
					add(sim, str(e["building"]), "contest_won")
				else:
					_fam_fact(sim, str(e.get("family", "")), "contest_won")
	if not Ledger.is_dawn(sim):
		return
	var keep_from := today - int(cfg.get("window_days", 4)) + 1
	var decay := clampf(float(cfg.get("decay_per_day", 0.15)), 0.0, 1.0)
	for b: Variant in st.buildings:
		var f: Variant = st.buildings[b].get("fame")
		if not f is Dictionary:
			continue
		var fd: Dictionary = f
		fd["renown"] = float(fd.get("renown", 0.0)) * (1.0 - decay)
		fd["sold"] = (fd.get("sold", []) as Array).filter(func(r: Variant) -> bool: return int(r[0]) >= keep_from)


## The contests won since the last look (buildings[b].contests_won, written by fiestas' FestivalCourt._judge): each new
## win is a contest_won fact of that workshop. Remembered in its fame memory (contests_seen).
static func _contests(sim: Sim) -> void:
	var st := sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var won := int(st.buildings[b].get("contests_won", 0))
		if won <= 0:
			continue
		var f := _mem(st, b)
		var seen := int(f.get("contests_seen", 0))
		if won > seen:
			f["contests_seen"] = won
			add(sim, b, "contest_won", won - seen)


static func _fam_fact(sim: Sim, fam: String, kind: String) -> void:
	var b := main_workshop(sim, fam)
	if b != "":
		add(sim, b, kind)


static func _sold(sim: Sim, bld: String, day: int, quality: int, qty: int) -> void:
	if bld == "" or not sim.state.buildings.has(bld):
		return
	var sold: Array = _mem(sim.state, bld)["sold"]
	for r: Variant in sold:
		if int(r[0]) == day and int(r[1]) == quality:
			r[2] = int(r[2]) + qty
			return
	sold.append([day, quality, qty])


## What the panel shows: {fame, quality, renown}.
static func view(sim: Sim, bld: String) -> Dictionary:
	var f: Variant = sim.state.buildings.get(bld, {}).get("fame")
	return {"fame": of(sim, bld), "quality": mean_quality(sim, bld),
		"renown": float((f as Dictionary).get("renown", 0.0)) if f is Dictionary else 0.0}
