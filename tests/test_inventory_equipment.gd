extends RefCounted
## Validates that equipment can be equipped by dragging from the bag onto the
## equipment slots on both the Stats and Items pages.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const HOLY_SWORD := "res://resources/items/weapons/swords/holy_sword.tres"
const DRAG_TYPE := &"inventory_item"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var panel := area.get_node_or_null("HUD/UI/InventoryPanel") as InventoryPanel
	if panel == null:
		failures.append("the HUD needs the InventoryPanel")
		area.queue_free()
		await tree.process_frame
		return failures

	var holy := load(HOLY_SWORD) as EquipmentData
	if holy == null:
		failures.append("%s did not load" % HOLY_SWORD)
		area.queue_free()
		await tree.process_frame
		return failures

	# The area starts with default_sword, default_buckler, holy_sword in the bag.
	panel.show_panel()
	var items_tab := panel.find_child("ItemsTab", true, false) as Button
	if items_tab == null:
		failures.append("ItemsTab missing")
	else:
		items_tab.pressed.emit()
		await tree.process_frame

	if panel.current_tab != &"items":
		failures.append("Failed to switch to Items tab")

	# Locate the bag slot that holds the holy sword.
	var bag_content := panel.find_child("BagContent", true, false) as Control
	var drag_data: Variant = null
	if bag_content == null:
		failures.append("BagContent missing")
	else:
		var holy_slot: InventoryBagSlot = null
		for child in bag_content.get_children():
			var slot := child as InventoryBagSlot
			if slot != null and slot.item != null and slot.item.id == &"holy_sword":
				holy_slot = slot
				break
		if holy_slot == null:
			failures.append("Holy sword not found in bag")
		else:
			# Simulate drag from bag slot.
			drag_data = holy_slot._get_drag_data(Vector2.ZERO)
			if drag_data == null or drag_data.get("type") != DRAG_TYPE:
				failures.append("Drag data invalid")
			else:
				# Test dropping on Items page primary slot (visual index 2 -> primary).
				var item_primary := panel.find_child("ItemEquipPrimary", true, false) as Button
				if item_primary == null:
					failures.append("ItemEquipPrimary missing")
				else:
					var can_drop := item_primary._can_drop_data(Vector2.ZERO, drag_data)
					if not can_drop:
						failures.append("ItemEquipPrimary should accept primary weapon")
					else:
						item_primary._drop_data(Vector2.ZERO, drag_data)
						await tree.process_frame
						# Verify equip: both stats and items primary buttons show holy sword icon.
						var stat_primary := panel.find_child("EquipPrimary", true, false) as Button
						if stat_primary == null or stat_primary.icon != holy.icon:
							failures.append("Stats page primary slot not updated")
						if item_primary.icon != holy.icon:
							failures.append("Items page primary slot not updated")
						# Verify attack stat increased by holy sword flat +20.
						var player := area.player
						if player != null and player.stats != null:
							var attack := player.stats.get_stat(Stats.ATTACK)
							# Base warrior attack_damage = 15, attack_per_level = 2.
							var base_attack := 15 + maxi(0, player.level - 1) * 2
							var expected_attack := base_attack + 20.0
							if not is_equal_approx(attack, expected_attack):
								failures.append("Attack stat not updated after equip, got %s (expected %s)" % [attack, expected_attack])
						# Verify holy sword removed from bag (slot cleared or different item).
						if holy_slot.item != null and holy_slot.item.id == &"holy_sword":
							failures.append("Holy sword still in bag slot after equip")

				# Test reject on secondary slot (should not accept primary).
				var item_secondary := panel.find_child("ItemEquipSecondary", true, false) as Button
				if item_secondary != null:
					var can_drop_sec := item_secondary._can_drop_data(Vector2.ZERO, drag_data)
					if can_drop_sec:
						failures.append("ItemEquipSecondary should reject primary weapon")

	# Also test dropping on Stats page primary slot works.
	if drag_data != null:
		var stat_primary2 := panel.find_child("EquipPrimary", true, false) as Button
		if stat_primary2 != null:
			var can_drop_stat := stat_primary2._can_drop_data(Vector2.ZERO, drag_data)
			if not can_drop_stat:
				failures.append("Stats EquipPrimary should accept primary weapon")
			else:
				stat_primary2._drop_data(Vector2.ZERO, drag_data)
				await tree.process_frame
				# Should still be equipped (no double equip). Just ensure no error.

	area.queue_free()
	await tree.process_frame
	return failures