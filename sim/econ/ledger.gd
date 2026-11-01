class_name Ledger
extends RefCounted
## The account book (GDD 4.18): keeps the entries Money.change writes (detail of the last 2 years, older ones summed
## by year, category and building) and answers the panel's questions. Owner: subgrim «cuentas».
## Contract: docs/contratos/h3_mercado.md. Nobody writes entries but Money.change.


## Retention at dawn: entries older than the detail window go into state.ledger.summaries.
static func step(_sim: Sim) -> void:
	pass


## Totals of `fam` for the panel: scope "today" | "days" (last 8 days) | "buildings". Shape in the contract.
static func summary(_sim: Sim, _fam: String, _scope: String) -> Dictionary:
	return {}


## The detailed entries of `fam` from day `from_day` to `to_day` (both included), oldest first.
static func entries(_sim: Sim, _fam: String, _from_day: int, _to_day: int) -> Array:
	return []
