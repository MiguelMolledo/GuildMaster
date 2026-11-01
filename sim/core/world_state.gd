class_name WorldState
extends RefCounted
## Everything a saved game holds (GDD 05 §5.3). Plain data only: dictionaries and arrays of JSON-friendly values.
## Entities reference each other by id ("chr_0001", "bld_0003"), never by Node. A view keeps the id it draws, nothing else.
## After a load every integral number comes back as int (SaveFile.intify): code that reads the state casts with
## int() / float() and never relies on the type a number had before saving.

const VERSION: int = 1

var version: int = VERSION
var world_seed: int = 0
var rng := RandomNumberGenerator.new()
var meta: Dictionary = {}          # title, description and origin of a scenario; free text, no rules read it
var clock: Dictionary = {"minute": 0}  # minutes since day 0, 00:00 (Clock derives the rest from data/time.json)
var characters: Dictionary = {}    # chr_id -> character
var families: Dictionary = {}      # fam_id -> family
var buildings: Dictionary = {}     # bld_id -> building
var parcels: Dictionary = {}       # par_id -> parcel
var market: Dictionary = {"demand": {}, "regulations": []}
var offices: Dictionary = {}
var elections: Array = []
var trials: Array = []
var relationships: Dictionary = {} # "chr_a|chr_b" (sorted as String) -> {relation, affinity}
var emotions: Dictionary = {}      # chr_id -> [emotion]
var events_active: Array = []
var chronicle: Array = []          # facts of the game (births, weddings, titles...): input of the future chronicler
var next_ids: Dictionary = {}      # prefix -> next number (Ids.next)


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
		"clock": clock,
		"characters": characters,
		"families": families,
		"buildings": buildings,
		"parcels": parcels,
		"market": market,
		"offices": offices,
		"elections": elections,
		"trials": trials,
		"relationships": relationships,
		"emotions": emotions,
		"events_active": events_active,
		"chronicle": chronicle,
		"next_ids": next_ids,
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
	s.clock = d.get("clock", {"minute": 0})
	s.characters = d.get("characters", {})
	s.families = d.get("families", {})
	s.buildings = d.get("buildings", {})
	s.parcels = d.get("parcels", {})
	s.market = d.get("market", {"demand": {}, "regulations": []})
	s.offices = d.get("offices", {})
	s.elections = d.get("elections", [])
	s.trials = d.get("trials", [])
	s.relationships = d.get("relationships", {})
	s.emotions = d.get("emotions", {})
	s.events_active = d.get("events_active", [])
	s.chronicle = d.get("chronicle", [])
	s.next_ids = d.get("next_ids", {})
	return s


## The inventory of an entity (character or building) by id, or an empty dictionary if it has none.
func inventory_of(entity_id: String) -> Dictionary:
	if characters.has(entity_id):
		return characters[entity_id].get("inventory", {})
	if buildings.has(entity_id):
		return buildings[entity_id].get("inventory", {})
	return {}
