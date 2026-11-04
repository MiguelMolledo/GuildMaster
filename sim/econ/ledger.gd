class_name Ledger
extends RefCounted
## The account book (GDD 4.18): keeps the entries Money.change writes (detail of the last 2 years, older ones summed
## by year, category and building) and answers the panel's questions. Owner: subgrim «cuentas».
## Contract: docs/contratos/h3_mercado.md. Nobody writes entries but Money.change.
##
## state.ledger = {entries: [entry], summaries: {fam: {year (String): {category: {building_or_"": int}}}}}.
## Figures in data/accounts.json (Catalog.accounts): ledger_detail_years, ledger_days_view.


## Retention at dawn: entries older than the detail window go into state.ledger.summaries.
static func step(sim: Sim) -> void:
	if not is_dawn(sim):
		return
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	var keep_days := int(sim.catalog.accounts.get("ledger_detail_years", 2)) * Clock.days_per_year(sim.catalog.time)
	var first_kept := today - keep_days + 1
	var entries: Array = st.ledger.get("entries", [])
	if entries.is_empty() or int(entries[0]["day"]) >= first_kept:
		return
	var kept: Array = []
	var moved := 0
	var summaries: Dictionary = st.ledger.get("summaries", {})
	for e: Dictionary in entries:
		if int(e["day"]) >= first_kept:
			kept.append(e)
			continue
		var fam := str(e["family"])
		var year := str(Clock.year(int(e["minute"]), sim.catalog.time))
		var by_year: Dictionary = summaries.get_or_add(fam, {})
		var by_cat: Dictionary = by_year.get_or_add(year, {})
		var by_bld: Dictionary = by_cat.get_or_add(str(e["category"]), {})
		var bld := str(e.get("building", ""))
		by_bld[bld] = int(by_bld.get(bld, 0)) + int(e["amount"])
		moved += 1
	st.ledger["entries"] = kept
	st.ledger["summaries"] = summaries
	if OS.is_debug_build():
		print("[Ledger] retención: %d asientos anteriores al día %d pasan al resumen (quedan %d)" % [moved, first_kept,
			kept.size()])


## Totals of `fam` for the panel. Scopes:
##   "today"     -> {income, expense, net, by_category {cat: net}}   (income >= 0, expense <= 0, net = income + expense)
##   "days"      -> [{day, income, expense, net}] the last ledger_days_view days up to today, oldest first
##   "buildings" -> {bld_or_"": {cat: net}} over the detailed entries
##   "debts"     -> {loans: [Loans.status], contracts: [accepted contract of fam + hours_left],
##                   upkeep: [{building, debt, unpaid_since, days_unpaid}]}
static func summary(sim: Sim, fam: String, scope: String) -> Variant:
	var st := sim.state
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	match scope:
		"today":
			return _totals(entries(sim, fam, today, today))
		"days":
			var n := int(sim.catalog.accounts.get("ledger_days_view", 8))
			var out: Array = []
			for d: int in range(maxi(0, today - n + 1), today + 1):
				var t := _totals(entries(sim, fam, d, d))
				out.append({"day": d, "income": t["income"], "expense": t["expense"], "net": t["net"]})
			return out
		"buildings":
			var by_bld := {}
			for e: Dictionary in st.ledger.get("entries", []):
				if str(e["family"]) != fam:
					continue
				var cats: Dictionary = by_bld.get_or_add(str(e.get("building", "")), {})
				cats[str(e["category"])] = int(cats.get(str(e["category"]), 0)) + int(e["amount"])
			return by_bld
		"debts":
			var loans: Array = []
			for id: String in Loans.of_family(sim, fam):
				loans.append(Loans.status(sim, id))
			var contracts: Array = []
			for c: Dictionary in st.contracts.get("accepted", []):
				if str(c.get("family", "")) != fam:
					continue
				var row := c.duplicate(true)
				var due := int(c.get("due", -1))
				row["hours_left"] = maxi(0, ceili(float(due - now) / 60.0)) if due >= 0 else -1
				contracts.append(row)
			var upkeep: Array = []
			var ids: Array = st.buildings.keys()
			ids.sort()
			for b: String in ids:
				var bld: Dictionary = st.buildings[b]
				if Money.family_of(st, b) != fam or int(bld.get("upkeep_debt", 0)) <= 0:
					continue
				var since := int(bld.get("upkeep_unpaid_since", -1))
				upkeep.append({"building": b, "debt": int(bld["upkeep_debt"]), "unpaid_since": since,
					"days_unpaid": today - since if since >= 0 else 0})
			return {"loans": loans, "contracts": contracts, "upkeep": upkeep}
	push_error("Ledger.summary: unknown scope %s" % scope)
	return {}


## Where the family's gold goes at its pace (mercado_y_libro.md §4.3): the mean net of the last `days` whole days (today
## if there is none yet) times the days left until `until_minute`, plus the gold now: {avg_net, days, days_left, gold_at}.
## Read only: the same estimate for the UI and the bots.
static func forecast(sim: Sim, fam: String, until_minute: int, days: int = 3) -> Dictionary:
	var now := int(sim.state.clock["minute"])
	var today := Clock.day(now)
	var first := maxi(0, today - days)
	var nets: Array = []
	for d: int in range(first, today):
		nets.append(int(_totals(entries(sim, fam, d, d))["net"]))
	if nets.is_empty():
		nets.append(int(_totals(entries(sim, fam, today, today))["net"]))
	var sum := 0
	for n: Variant in nets:
		sum += int(n)
	var avg := roundi(float(sum) / float(nets.size()))
	var left := maxf(0.0, float(until_minute - now) / float(Clock.MINUTES_PER_DAY))
	return {"avg_net": avg, "days": nets.size(), "days_left": left,
		"gold_at": Money.gold(sim.state, fam) + roundi(avg * left)}


## The detailed entries of `fam` from day `from_day` to `to_day` (both included), oldest first (copies).
static func entries(sim: Sim, fam: String, from_day: int, to_day: int) -> Array:
	var out: Array = []
	for e: Dictionary in sim.state.ledger.get("entries", []):
		var d := int(e["day"])
		if str(e["family"]) == fam and d >= from_day and d <= to_day:
			out.append(e.duplicate())
	return out


## The sum of every amount of `fam` kept in the book: detailed entries plus the yearly summaries. It equals the
## change of the family's gold since the book started (the conservation rule of GDD 4.19).
static func total(state: WorldState, fam: String) -> int:
	var n := 0
	for e: Dictionary in state.ledger.get("entries", []):
		if str(e["family"]) == fam:
			n += int(e["amount"])
	var by_year: Dictionary = state.ledger.get("summaries", {}).get(fam, {})
	for y: String in by_year:
		for cat: String in by_year[y]:
			for b: String in by_year[y][cat]:
				n += int(by_year[y][cat][b])
	return n


## Whether this step began a dawn (the "at dawn" of every H3 system: a phase_changed event with phase "dawn").
static func is_dawn(sim: Sim) -> bool:
	for e: Dictionary in sim.events:
		if str(e["type"]) == "phase_changed" and str(e.get("phase", "")) == "dawn":
			return true
	return false


static func _totals(rows: Array) -> Dictionary:
	var income := 0
	var expense := 0
	var by_cat := {}
	for e: Dictionary in rows:
		var a := int(e["amount"])
		if a > 0:
			income += a
		else:
			expense += a
		by_cat[str(e["category"])] = int(by_cat.get(str(e["category"]), 0)) + a
	return {"income": income, "expense": expense, "net": income + expense, "by_category": by_cat}
