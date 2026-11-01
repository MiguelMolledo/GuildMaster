class_name Loans
extends RefCounted
## Debts (GDD 4.16): the starting loan, repaying, warnings, the extension with its surcharge, the seizure and the
## ruin that ends the game (D18). Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.


## {"type": "repay_loan", "actor", "loan", "amount"}.
static func order_repay(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## Warnings before the due date, the due date (extension), the end of the extension (seizure, ruin).
static func step(_sim: Sim) -> void:
	pass


## {} | {id, family, lender, principal, outstanding, due_minute, extended, state, days_left} for the UI.
static func status(_sim: Sim, _loan: String) -> Dictionary:
	return {}


## The open loans of `fam` (ids, sorted).
static func of_family(_sim: Sim, _fam: String) -> Array:
	return []
