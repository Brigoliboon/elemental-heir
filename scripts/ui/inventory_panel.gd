
class_name InventoryPanel
extends PanelContainer

@export var slot_size := Vector2(96, 96)
@export var equip_slot_size := Vector2(64, 64)
@export var potion_slots := 5
@export var general_columns := 8

@onready var left_slots: VBoxContainer = $Margin/VBox/TopRow/LeftSlots
@onready var right_slots: VBoxContainer = $Margin/VBox/TopRow/RightSlots
@onready var potions_row: HBoxContainer = $Margin/VBox/PotionsRow

@onready var desc_title: Label = $Margin/VBox/TopRow/DescriptionPanel/DescMargin/DescVBox/DescTitle
@onready var desc_body: Label = $Margin/VBox/TopRow/DescriptionPanel/DescMargin/DescVBox/DescBody

@onready var general_grid: GridContainer = $Margin/VBox/GeneralInventory
@onready var close_button: Button = $Margin/VBox/Close

var _inventory: Inventory
var _stats: Stats
var _equipped: Array = [null, null, null, null, null, null, null, null]
const _EQUIP_GROUPS := ["helmet", "chest_armour", "pants", "boots", "necklace", "ring", "sword", "shield"]


func _ready() -> void:
	close_button.pressed.connect(hide_panel)
	hide_panel()


func bind(inventory: Inventory, stats: Stats = null) -> void:
	_inventory = inventory
	_stats = stats
	_restore_equipped()
	_refresh()


func show_panel() -> void:
	_refresh()
	visible = true


func hide_panel() -> void:
	visible = false


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()



func _restore_equipped() -> void:
	if _inventory == null:
		return
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress == null:
		return
	for i in range(8):
		var path := ""
		if i < progress.equipped.size():
			path = str(progress.equipped[i])
		if path.is_empty():
			continue
		var item = load(path)
		if item == null:
			continue
		# remove from inventory if present
		var slots := _inventory.get_slots()
		for idx in range(slots.size()):
			if slots[idx]["item"] == item:
				_inventory.remove_item(idx, int(slots[idx]["count"]))
				break
		_equipped[i] = item
		if _stats != null and item is EquipmentData:
			for mod in item.stat_modifiers:
				if mod != null:
					_stats.add_modifier(item.id, mod.stat, mod.flat, mod.pct)


func _sync_progress() -> void:
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress == null:
		return
	for i in range(8):
		var item = _equipped[i]
		if item != null and item.resource_path != "":
			progress.equipped[i] = item.resource_path
		else:
			progress.equipped[i] = ""
	if progress.has_method("save_progress"):
		progress.save_progress()


func _refresh() -> void:
	if not is_node_ready():
		return

	if left_slots == null or right_slots == null:
		return

	if potions_row == null or general_grid == null:
		return

	# Clear existing slots.
	_clear_slots(left_slots)
	_clear_slots(right_slots)
	_clear_slots(potions_row)
	_clear_slots(general_grid)

	# Create equipment slots.
	for i in range(4):
		var b := _add_slot(left_slots, equip_slot_size)
		b.slot_index = left_slots.get_child_count() - 1 + 0

	for i in range(4):
		_add_slot(right_slots, equip_slot_size)

	# Create potion slots.
	for i in range(potion_slots):
		_add_slot(potions_row, equip_slot_size)

	# Create general inventory slots.
	for i in range(28):
		_add_slot(general_grid, slot_size)

	# Stop if no inventory is bound.
	if _inventory == null:
		return

	# Collect all generated buttons.
	var targets: Array[Button] = []

	for container in [left_slots, right_slots, potions_row, general_grid]:
		for child in container.get_children():
			if child is Button:
				targets.append(child)

	# Assign slot indices for drag/drop (only general inventory maps to Inventory slots).
	var base := 4 + 4 + potion_slots
	for i in range(targets.size()):
		var sb := targets[i] as SlotButton
		if sb == null:
			continue
		if i < 8:
			sb.slot_index = -1
			sb.equip_index = i
		elif i >= base and i - base < 28:
			sb.slot_index = i - base
			sb.equip_index = -1
		else:
			sb.slot_index = -1
			sb.equip_index = -1

	# Stop if no inventory is bound.
	if _inventory == null:
		return

	# Populate equip slots.
	for i in range(8):
		var btn: Button = targets[i]
		var item = _equipped[i]
		if item != null and item.icon != null:
			btn.icon = item.icon
		btn.tooltip_text = item.display_name if item != null else ""

	# Populate slots.
	var slots := _inventory.get_slots() if _inventory != null else []

	for idx in range(mini(slots.size(), targets.size() - base)):
		var item = slots[idx]["item"]
		var btn: Button = targets[base + idx]

		if item == null:
			continue

		if item.icon != null:
			btn.icon = item.icon

		btn.expand_icon = false
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.tooltip_text = item.display_name

		var captured_item = item

		btn.pressed.connect(func() -> void:
			desc_title.text = captured_item.display_name
			var lines: Array[String] = []
			if not captured_item.description.is_empty():
				lines.append(captured_item.description)
			lines.append("Rarity: %s" % ItemData.Rarity.keys()[captured_item.rarity])
			if captured_item is EquipmentData:
				for mod in captured_item.stat_modifiers:
					if mod == null:
						continue
					var stat_name := str(mod.stat)
					var text := ""
					if mod.flat != 0.0:
						text += ("+%s " % mod.flat) if mod.flat > 0 else ("%s " % mod.flat)
					if mod.pct != 0.0:
						text += ("%.0f%% " % (mod.pct * 100.0))
					lines.append("%s: %s" % [stat_name, text.strip_edges()])
			desc_body.text = "\n".join(lines)
		)


func _clear_slots(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()



class SlotButton extends Button:
	var slot_index := -1
	var equip_index := -1
	var panel: InventoryPanel

	func _get_drag_data(_pos):
		if panel == null or panel._inventory == null:
			return null
		if equip_index >= 0:
			var item = panel._equipped[equip_index]
			if item == null:
				return null
			var preview := TextureRect.new()
			preview.texture = item.icon
			preview.expand_mode = 1
			preview.stretch_mode = 5
			preview.custom_minimum_size = Vector2(48, 48)
			set_drag_preview(preview)
			return {"equip": equip_index}
		var slots := panel._inventory.get_slots()
		if slot_index < 0 or slot_index >= slots.size():
			return null
		if slots[slot_index]["item"] == null:
			return null
		var preview := TextureRect.new()
		preview.texture = slots[slot_index]["item"].icon
		preview.expand_mode = 1
		preview.stretch_mode = 5
		preview.custom_minimum_size = Vector2(48, 48)
		set_drag_preview(preview)
		return {"slot": slot_index}

	func _can_drop_data(_pos, data):
		return typeof(data) == TYPE_DICTIONARY and (data.has("slot") or data.has("equip"))

	func _drop_data(_pos, data):
		if panel == null:
			return
		# drag from general inventory slot
		if data.has("slot"):
			var from := int(data["slot"])
			# drop onto equip slot
			if equip_index >= 0:
				if panel._inventory == null:
					return
				var slots := panel._inventory.get_slots()
				if from < 0 or from >= slots.size():
					return
				var item = slots[from]["item"]
				if not (item is EquipmentData):
					return
				if item.item_group != panel._EQUIP_GROUPS[equip_index]:
					return
				# return existing equipped item
				if panel._equipped[equip_index] != null:
					panel._inventory.add_item(panel._equipped[equip_index], 1)
				panel._equipped[equip_index] = item
				panel._inventory.remove_item(from, int(slots[from]["count"]))
				panel._sync_progress()
				if panel._stats != null:
					for mod in item.stat_modifiers:
						if mod != null:
							panel._stats.add_modifier(item.id, mod.stat, mod.flat, mod.pct)
				panel._refresh()
				return
			# drop onto general slot
			if slot_index >= 0:
				if panel._inventory == null:
					return
				var from_idx := from
				var to_idx := slot_index
				if from_idx == to_idx:
					return
				panel._inventory.swap_slots(from_idx, to_idx)
				panel._refresh()
				return
		# drag from equip slot
		if data.has("equip"):
			var from_equip := int(data["equip"])
			if slot_index >= 0 and panel._inventory != null:
				var item = panel._equipped[from_equip]
				if item == null:
					return
				panel._equipped[from_equip] = null
				panel._inventory.add_item(item, 1)
				if panel._stats != null:
					panel._stats.remove_modifier(item.id)
				panel._sync_progress()
				panel._refresh()



func _add_slot(parent: Control, size: Vector2) -> Button:
	var btn := SlotButton.new()
	btn.panel = self

	btn.custom_minimum_size = size
	btn.custom_maximum_size = size
	btn.expand_icon = false
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

	parent.add_child(btn)
	return btn
