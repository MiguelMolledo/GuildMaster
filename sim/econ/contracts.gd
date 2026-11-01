class_name Contracts
extends RefCounted
## NPC contracts (GDD 4.5.6): the board in the square, accepting, delivering, abandoning, deadlines.
## Owner: subgrim «rival». Contract: docs/contratos/h3_mercado.md. Figures in data/contracts/<profession>.json and
## data/market.json "board". Gold through Money.change (category contracts); it does not touch market demand.


## {"type": "accept_contract", "actor", "contract"}.
static func order_accept(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "deliver_contract", "actor", "contract"}.
static func order_deliver(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "abandon_contract", "actor", "contract"}.
static func order_abandon(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## A new contract at dawn if the board has room; deadline warnings; expiries.
static func step(_sim: Sim) -> void:
	pass


## What the board shows to `actor`: {at_board: bool, open: [contract + {status}], accepted: [contract + {status,
## hours_left}]} (status "ok" | a refusal reason).
static func board_view(_sim: Sim, _actor: String) -> Dictionary:
	return {"at_board": false, "open": [], "accepted": []}
