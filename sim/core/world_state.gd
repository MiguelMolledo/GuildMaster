class_name WorldState
extends RefCounted
## Everything a saved game holds (GDD 05 §5.3). Plain data only: dictionaries and arrays of JSON-friendly values.
## Entities reference each other by id ("chr_0001", "bld_0003"), never by Node. A view keeps the id it draws, nothing else.
## After a load every integral number comes back as int (SaveFile.intify): code that reads the state casts with
## int() / float() and never relies on the type a number had before saving.

const VERSION: int = 13

var version: int = VERSION
var world_seed: int = 0
var rng := RandomNumberGenerator.new()
var meta: Dictionary = {}          # title, description and origin of a scenario; free text, no rules read it
var map_id: String = ""            # data/maps/<map_id>.json: the static town (tiles, spawns); "" = no map
var clock: Dictionary = {"minute": 0}  # minutes since day 0, 00:00 (Clock derives the rest from data/time.json)
var characters: Dictionary = {}    # chr_id -> character
var families: Dictionary = {}      # fam_id -> family
var buildings: Dictionary = {}     # bld_id -> building
var parcels: Dictionary = {}       # par_id -> parcel
var market: Dictionary = {"demand": {}, "regulations": []}
var offices: Dictionary = {}      # H10: office_id -> {seats: [{holder, since, until, cooldowns}], settings}: Offices
var elections: Array = []          # H10: [election] open and the last closed ones (GDD 4.12.4): Elections
var trials: Array = []             # H11: [trial] open and the last closed ones (GDD 4.12.5): Tribunal
var justice: Dictionary = {"facts": []}  # H11: facts that can be taken to court (an inspection, a scandal): Tribunal
var relationships: Dictionary = {} # "chr_a|chr_b" (sorted as String) -> {relation, affinity}
var emotions: Dictionary = {}      # chr_id -> [emotion]
var events_active: Array = []     # H13: the global events in force [{id, def, start, end, by}] (GDD 4.13): WorldEvents
var chronicle: Array = []          # facts of the game (births, weddings, titles...): input of the future chronicler
var next_ids: Dictionary = {}      # prefix -> next number (Ids.next)
# H3 (docs/contratos/h3_mercado.md): money, debt, contracts, errands, the start of a game.
var ledger: Dictionary = {"entries": [], "summaries": {}}  # Money.change writes entries; Ledger keeps and sums them
var notices: Array = []            # [notice] the warnings log (GDD 4.18): Notices.add
var loans: Dictionary = {}         # lon_id -> loan (GDD 4.16): Loans
var contracts: Dictionary = {"board": [], "accepted": [], "cooldowns": {}, "relations": {}}  # GDD 4.5.6: Contracts
var deliveries: Array = []         # [delivery] market errands on their way (GDD 4.5.7): Market
var difficulty: String = "normal"  # easy | normal | hard (GDD 4.23, data/difficulty.json)
var objectives: Dictionary = {}    # fam_id -> progress of its start objectives (GDD 4.16): Objectives
var ending: Dictionary = {}        # {} while the game goes on; {kind, family, minute} when it ends (ruin, D18)
# H7 (docs/contratos/h7_ciudad.md): the living town. Characters get occupation and town (SaveFile._step 7 -> 8).
var microevents: Dictionary = {"active": [], "pending": [], "cooldowns": {}, "last_day": {}}  # GDD 4.20: Microevents
var town: Dictionary = {"counters": {}}  # the shop counters' next customer (GDD 4.5.4): Counter
# H4 (docs/contratos/h4_empleados.md): no new root fields. Characters get home, rank, job, hire_bans and routine;
# buildings get employee_slots and queue (SaveFile._step 4 -> 5).
# H5 (docs/contratos/h5_mejoras.md): no new root fields. Buildings get upgrades, upgrade_work and inspection
# (SaveFile._step 5 -> 6).
# H8 (docs/contratos/h8_familia.md): no new root fields (relationships and chronicle already were). Characters get
# birth_day, death_day, class, profession, spouse, parents, children, assigned, directives, schedule, visual and life;
# families get head, heir, founder, generation, regent, class and goals_done (SaveFile._step 6 -> 7).
# H7: emotions (already a root field) get their shape: chr -> [{state, source, start, duration, intensity0}].
# H9 (docs/contratos/h9_titulos.md): no new root fields. Families get title, class_reputation, reputation_log and
# reputation_caps (SaveFile._step 8 -> 9). The town hall is a site of the map, not state.
# H10 (docs/contratos/h10_cargos.md): offices, elections and market.regulations (root fields that already were) get
# their shape (SaveFile._step 9 -> 10). An empty offices on a map with a town hall = a government not handed out yet:
# Offices.step hands it out the first time it runs.
# H11 (docs/contratos/h11_tribunal.md): trials (a root field that already was) gets its shape and the new root justice
# keeps the facts; families get attitudes {honesty, generosity, diplomacy} and characters banished_until
# (SaveFile._step 10 -> 11).
# H14 (docs/contratos/h14_ia_familiar.md): no new root fields. Characters get needs {hunger, rest, social, fun} and ai
# (the directives' memory) (SaveFile._step 11 -> 12).
# H13 (estaciones y eventos globales): events_active (a root field that already was, always []) gets its shape
# [{id, def, start, end, by}] (SaveFile._step 12 -> 13). The season is not state: Clock derives it from the minute.


func seed_rng(s: int) -> void:
	world_seed = s
	rng.seed = s


func to_dict() -> Dictionary:
	return {
		"version": version,
		# 64-bit numbers go as text: a JSON number is a double and loses them past 2^53.
		"seed": str(world_seed),
		"rng_state": str(rng.state),
		"meta": meta,
		"map_id": map_id,
		"clock": clock,
		"characters": characters,
		"families": families,
		"buildings": buildings,
		"parcels": parcels,
		"market": market,
		"offices": offices,
		"elections": elections,
		"trials": trials,
		"justice": justice,
		"relationships": relationships,
		"emotions": emotions,
		"events_active": events_active,
		"chronicle": chronicle,
		"next_ids": next_ids,
		"ledger": ledger,
		"notices": notices,
		"loans": loans,
		"contracts": contracts,
		"deliveries": deliveries,
		"difficulty": difficulty,
		"objectives": objectives,
		"ending": ending,
		"microevents": microevents,
		"town": town,
	}


## Builds a state from a dictionary already migrated to VERSION (SaveFile.migrate). A deep copy: the dictionary
## passed in is not shared with the state.
static func from_dict(src: Dictionary) -> WorldState:
	var d: Dictionary = SaveFile.intify(src.duplicate(true))
	var s := WorldState.new()
	s.version = int(d.get("version", VERSION))
	s.world_seed = str(d.get("seed", "0")).to_int()
	s.rng.seed = s.world_seed
	var rng_state := str(d.get("rng_state", ""))
	if rng_state != "":
		s.rng.state = rng_state.to_int()
	s.meta = d.get("meta", {})
	s.map_id = str(d.get("map_id", ""))
	s.clock = d.get("clock", {"minute": 0})
	s.characters = d.get("characters", {})
	s.families = d.get("families", {})
	s.buildings = d.get("buildings", {})
	s.parcels = d.get("parcels", {})
	s.market = d.get("market", {"demand": {}, "regulations": []})
	s.offices = d.get("offices", {})
	s.elections = d.get("elections", [])
	s.trials = d.get("trials", [])
	s.justice = d.get("justice", {"facts": []})
	s.relationships = d.get("relationships", {})
	s.emotions = d.get("emotions", {})
	s.events_active = d.get("events_active", [])
	s.chronicle = d.get("chronicle", [])
	s.next_ids = d.get("next_ids", {})
	s.ledger = d.get("ledger", {"entries": [], "summaries": {}})
	s.notices = d.get("notices", [])
	s.loans = d.get("loans", {})
	s.contracts = d.get("contracts", {"board": [], "accepted": [], "cooldowns": {}, "relations": {}})
	s.deliveries = d.get("deliveries", [])
	s.difficulty = str(d.get("difficulty", "normal"))
	s.objectives = d.get("objectives", {})
	s.ending = d.get("ending", {})
	s.microevents = d.get("microevents", {"active": [], "pending": [], "cooldowns": {}, "last_day": {}})
	s.town = d.get("town", {"counters": {}})
	return s


## The inventory of an entity (character or building) by id, or an empty dictionary if it has none.
func inventory_of(entity_id: String) -> Dictionary:
	if characters.has(entity_id):
		return characters[entity_id].get("inventory", {})
	if buildings.has(entity_id):
		return buildings[entity_id].get("inventory", {})
	return {}
