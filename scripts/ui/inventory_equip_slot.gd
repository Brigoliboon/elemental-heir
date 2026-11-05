class_name InventoryEquipSlot
extends Button

signal item_dropped(slot_index: int, bag_index: int, item: ItemData)

var slot_index := -1
var accepts: StringName = &""


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if slot_index < 0 or accepts == &"" or not (data is Dictionary):
		return false
	if data.get("type") != InventoryBagSlot.DRAG_TYPE:
		return false
	var item = data.get("item")
	return item is EquipmentData and (item as EquipmentData).equip_slot == accepts


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data):
		return
	item_dropped.emit(slot_index, int(data["bag_index"]), data["item"])
