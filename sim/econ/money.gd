class_name Money
extends RefCounted
## Gold (GDD 4.18, 4.19). Each family has one purse: state.families[fam].gold (int). Nobody changes it but change():
## every movement writes an entry in the ledger (state.ledger.entries) and emits gold_changed, so the ledger always
## adds up to the gold (the conservation rule of 4.19). Contract: docs/contratos/h3_mercado.md.
##
## Entry: {day, minute, family, building, actor, category, amount, ref}. `minute` is the absolute clock minute (the
## hour comes from it), `day` = Clock.day(minute); `building` / `actor` are "" when nobody in particular; `ref` is the
## id of what caused it (an order type, a contract, a loan, a delivery...).

# Ledger categories (GDD 4.19). Sources first, sinks after; some are both (loans, property, events).
const MARKET_SALES: String = "market_sales"
const CONTRACTS: String = "contracts"
const LOANS: String = "loans"
const COUNTER_SALES: String = "counter_sales"
const EVENTS: String = "events"
const PROPERTY: String = "property"
const OFFICES: String = "offices"
const SERVICES: String = "services"
const LOOT: String = "loot"
const PURCHASES: String = "purchases"
const ERRANDS: String = "errands"
const UPKEEP: String = "upkeep"
const WAGES: String = "wages"
const UPGRADES: String = "upgrades"
const FINES: String = "fines"
const TITLES: String = "titles"
const POLITICS: String = "politics"
const TAXES: String = "taxes"
const JUSTICE: String = "justice"
const FAMILY: String = "family"
const DONATIONS: String = "donations"
const GAMES: String = "games"            # 04f §4.26: games, bets and competition prizes (sim/games/)
const CATEGORIES: Array[String] = [MARKET_SALES, CONTRACTS, LOANS, COUNTER_SALES, EVENTS, PROPERTY, OFFICES, SERVICES,
	LOOT, PURCHASES, ERRANDS, UPKEEP, WAGES, UPGRADES, FINES, TITLES, POLITICS, TAXES, JUSTICE, FAMILY, DONATIONS, GAMES]


## The gold of a family (0 if it does not exist).
static func gold(state: WorldState, fam: String) -> int:
	return int(state.families.get(fam, {}).get("gold", 0))


## The family whose purse pays for `entity`: a family id is itself; a character, its family; a building, its owner's
## family (the owner may be a family or a character). "" if none (a public building, a character without family).
static func family_of(state: WorldState, entity: String) -> String:
	if state.families.has(entity):
		return entity
	if state.characters.has(entity):
		return str(state.characters[entity].get("family", ""))
	if state.buildings.has(entity):
		return family_of(state, str(state.buildings[entity].get("owner", "")))
	return ""


## Whether `fam` has at least `amount` gold.
static func can_pay(state: WorldState, fam: String, amount: int) -> bool:
	return state.families.has(fam) and gold(state, fam) >= amount


## The only way to change gold. `amount` > 0 comes in, < 0 goes out. Refuses (false, nothing changes) an unknown
## family, an unknown category, or leaving the gold below 0 unless `allow_negative`. 0 changes nothing and is true.
## Writes the ledger entry and emits gold_changed {family, amount, category, gold}.
static func change(sim: Sim, fam: String, amount: int, category: String, ref: String, building: String = "",
		actor: String = "", allow_negative: bool = false) -> bool:
	var st := sim.state
	if not st.families.has(fam):
		return false
	if not category in CATEGORIES:
		push_error("Money.change: unknown category %s" % category)
		return false
	if amount == 0:
		return true
	var now := gold(st, fam) + amount
	if now < 0 and not allow_negative:
		return false
	st.families[fam]["gold"] = now
	var minute := int(st.clock["minute"])
	st.ledger["entries"].append({"day": Clock.day(minute), "minute": minute, "family": fam, "building": building,
		"actor": actor, "category": category, "amount": amount, "ref": ref})
	sim.events.append({"type": "gold_changed", "family": fam, "amount": amount, "category": category, "gold": now})
	if OS.is_debug_build():
		print("[Money] %s %+d (%s, ref=%s, edificio=%s, actor=%s) -> oro=%d" % [fam, amount, category, ref, building,
			actor, now])
	return true
