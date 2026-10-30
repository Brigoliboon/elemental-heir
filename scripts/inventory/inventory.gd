class_name Inventory
extends Node

@export var capacity: int = 30

var _slots: Array = []


func _ready() -> void:
	_ensure_slots()


func _ensure_slots() -> void:
	if _slots.size() == capacity:
		return
	_slots.resize(capacity)
	for i in range(capacity):
		if _slots[i] == null or not (_slots[i] is Dictionary):
			_slots[i] = {"item": null, "count": 0}


func get_slots() -> Array:
	_ensure_slots()
	return _slots


func add_item(item: ItemData, count: int = 1) -> int:
	_ensure_slots()
	if item == null or count <= 0:
		return count
	var leftover := count
	# stack into existing
	if item.max_stack > 1:
		for slot in _slots:
			if slot["item"] == item and int(slot["count"]) < item.max_stack:
				var space := item.max_stack - int(slot["count"])
				var add := mini(space, leftover)
				slot["count"] = int(slot["count"]) + add
				leftover -= add
				if leftover <= 0:
					return 0
	# new slots
	for slot in _slots:
		if slot["item"] == null:
			var put := leftover
			if item.max_stack > 1:
				put = mini(item.max_stack, leftover)
			slot["item"] = item
			slot["count"] = put
			leftover -= put
			if leftover <= 0:
				return 0
	return leftover


func remove_item(slot_index: int, count: int = 1) -> bool:
	_ensure_slots()
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot: Dictionary = _slots[slot_index]
	if slot["item"] == null:
		return false
	var c := int(slot["count"]) - count
	if c <= 0:
		slot["item"] = null
		slot["count"] = 0
	else:
		slot["count"] = c
	return true


func swap_slots(a: int, b: int) -> void:
	_ensure_slots()
	if a < 0 or b < 0 or a >= _slots.size() or b >= _slots.size():
		return
	var tmp = _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp


func split_stack(slot_index: int, amount: int) -> int:
	_ensure_slots()
	if slot_index < 0 or slot_index >= _slots.size():
		return -1
	var slot: Dictionary = _slots[slot_index]
	if slot["item"] == null or amount <= 0 or amount >= int(slot["count"]):
		return -1
	# find empty slot
	for i in range(_slots.size()):
		if _slots[i]["item"] == null:
			_slots[i]["item"] = slot["item"]
			_slots[i]["count"] = amount
			slot["count"] = int(slot["count"]) - amount
			return i
	return -1


func sort_by_type() -> void:
	_ensure_slots()
	var items: Array = []
	var empties: Array = []
	for slot in _slots:
		if slot["item"] == null:
			empties.append(slot)
		else:
			items.append(slot)
	items.sort_custom(func(a, b):
		return int(a["item"].item_type) < int(b["item"].item_type)
	)
	var new_slots: Array = items + empties
	for i in range(_slots.size()):
		_slots[i] = new_slots[i] if i < new_slots.size() else {"item": null, "count": 0}
