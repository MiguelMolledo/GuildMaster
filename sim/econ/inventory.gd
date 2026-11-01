class_name Inventory
extends RefCounted
## Own inventory (GDD 05 §5.9; no addons, lesson L5). A plain dictionary so it saves as is:
##   {"limit_kind": "weight" | "stacks", "limit": float, "stacks": [{"item": "iron", "quality": 0, "qty": 3}, ...]}
## A stack is (item, quality): qualities never mix, a stack never holds more than the item's max_stack, and nothing
## ever goes negative. add() and remove() are all-or-nothing. Selling, buying and moving always go through here.

const NORMAL: int = 0
const GOOD: int = 1
const EXCELLENT: int = 2
const QUALITIES: Array[int] = [NORMAL, GOOD, EXCELLENT]


static func create(limit_kind: String, limit: float) -> Dictionary:
	return {"limit_kind": limit_kind, "limit": limit, "stacks": []}


## Units of `item` held; quality -1 counts every quality.
static func count(inv: Dictionary, item: String, quality: int = -1) -> int:
	var n := 0
	for s: Dictionary in inv.get("stacks", []):
		if str(s["item"]) == item and (quality < 0 or int(s["quality"]) == quality):
			n += int(s["qty"])
	return n


static func weight(inv: Dictionary, catalog: Catalog) -> float:
	var w := 0.0
	for s: Dictionary in inv.get("stacks", []):
		w += float(catalog.item(str(s["item"])).get("weight", 0.0)) * int(s["qty"])
	return w


## Whether `qty` units fit: weight limit, or number of stacks (filling the open stacks of the same kind first).
static func can_add(inv: Dictionary, catalog: Catalog, item: String, quality: int, qty: int) -> bool:
	var def := catalog.item(item)
	if def.is_empty() or qty <= 0 or not quality in QUALITIES:
		return false
	if str(inv["limit_kind"]) == "weight":
		return weight(inv, catalog) + float(def.get("weight", 0.0)) * qty <= float(inv["limit"]) + 0.0001
	var new_stacks := _new_stacks_needed(inv, item, quality, qty, int(def["max_stack"]))
	return (inv["stacks"] as Array).size() + new_stacks <= int(inv["limit"])


static func add(inv: Dictionary, catalog: Catalog, item: String, quality: int, qty: int) -> bool:
	if not can_add(inv, catalog, item, quality, qty):
		return false
	var max_stack := int(catalog.item(item)["max_stack"])
	var left := qty
	for s: Dictionary in inv["stacks"]:
		if left == 0:
			break
		if str(s["item"]) == item and int(s["quality"]) == quality and int(s["qty"]) < max_stack:
			var put := mini(left, max_stack - int(s["qty"]))
			s["qty"] = int(s["qty"]) + put
			left -= put
	while left > 0:
		var put := mini(left, max_stack)
		(inv["stacks"] as Array).append({"item": item, "quality": quality, "qty": put})
		left -= put
	return true


static func remove(inv: Dictionary, item: String, quality: int, qty: int) -> bool:
	if qty <= 0 or count(inv, item, quality) < qty:
		return false
	var left := qty
	var stacks: Array = inv["stacks"]
	# From the last stack backwards, so the open (partial) stacks empty first and the order of the rest stays.
	for i: int in range(stacks.size() - 1, -1, -1):
		if left == 0:
			break
		var s: Dictionary = stacks[i]
		if str(s["item"]) == item and int(s["quality"]) == quality:
			var take := mini(left, int(s["qty"]))
			s["qty"] = int(s["qty"]) - take
			left -= take
			if int(s["qty"]) == 0:
				stacks.remove_at(i)
	return true


static func _new_stacks_needed(inv: Dictionary, item: String, quality: int, qty: int, max_stack: int) -> int:
	var room := 0
	for s: Dictionary in inv.get("stacks", []):
		if str(s["item"]) == item and int(s["quality"]) == quality:
			room += max_stack - int(s["qty"])
	var left := maxi(0, qty - room)
	return ceili(float(left) / max_stack)
