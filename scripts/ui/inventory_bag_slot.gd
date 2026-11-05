class_name InventoryBagSlot
extends Button

const DRAG_TYPE := &"inventory_item"

var slot_index := -1
var item: ItemData

@onready var count_label: Label = $CountLabel


func bind_slot(index: int, item_data: ItemData, count: int) -> void:
	slot_index = index
	item = item_data
	icon = item.icon if item != null else null
	if item == null:
		count_label.visible = false
		tooltip_text = ""
		return
	count_label.text = str(count)
	count_label.visible = count > 1
	tooltip_text = item.display_name if count <= 1 else "%s x%d" % [item.display_name, count]


func clear_slot() -> void:
	slot_index = -1
	item = null
	icon = null
	count_label.visible = false
	tooltip_text = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null or slot_index < 0:
		return null
	var preview := TextureRect.new()
	preview.texture = item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(64, 64)
	preview.size = Vector2(64, 64)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	return {"type": DRAG_TYPE, "bag_index": slot_index, "item": item}
