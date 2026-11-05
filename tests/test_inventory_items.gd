extends RefCounted
## Validates the virtualized items grid: the bag scrolls, reuses a fixed slot
## pool and rebinds those slots to the inventory indexes currently in view.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const ITEMS_BG := "res://assets/ui/hud/inventory/tab_sections/tab_items_blank.png"
const SWORD := "res://resources/items/weapons/swords/default_sword.tres"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the inventory items test" % AREA_SCENE)
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

	var sword = load(SWORD)
	if sword == null:
		failures.append("%s did not load" % SWORD)
		area.queue_free()
		await tree.process_frame
		return failures

	for i in area.player.inventory.capacity:
		area.player.inventory.add_item(sword, 1)

	panel.show_panel()
	var items_tab := _find(panel, "ItemsTab") as Button
	if items_tab == null:
		failures.append("the inventory needs the ItemsTab button")
	else:
		items_tab.pressed.emit()
		await tree.process_frame
	await tree.process_frame

	if panel.current_tab != &"items":
		failures.append("clicking ITEMS must switch to the items tab")

	var background := _find(panel, "Background") as TextureRect
	if background == null or background.texture == null or background.texture.resource_path != ITEMS_BG:
		failures.append("the items tab must use %s" % ITEMS_BG)

	var items_page := _find(panel, "ItemsPage") as Control
	var stats_page := _find(panel, "StatsPage") as Control
	if items_page == null or not items_page.visible:
		failures.append("the items page must be visible on the items tab")
	if stats_page != null and stats_page.visible:
		failures.append("the stats page must be hidden on the items tab")

	var bag_viewport := _find(panel, "BagViewport") as ScrollContainer
	var bag_content := _find(panel, "BagContent") as Control
	if bag_viewport == null:
		failures.append("the items page needs a BagViewport ScrollContainer")
	if bag_content == null:
		failures.append("the bag needs a BagContent layout root")
	if bag_viewport == null or bag_content == null:
		area.queue_free()
		await tree.process_frame
		return failures

	var capacity := area.player.inventory.capacity
	var pool_size := bag_content.get_child_count()
	if pool_size <= 0:
		failures.append("the bag must create a pool of slot controls")
	elif pool_size >= capacity:
		failures.append("the bag must not create one control per inventory slot")
	if bag_content.custom_minimum_size.y <= bag_viewport.size.y:
		failures.append("the bag content must be taller than the viewport")

	var first_slot := bag_content.get_child(0) as InventoryBagSlot
	if first_slot == null:
		failures.append("BagContent children must be InventoryBagSlot controls")
	else:
		if first_slot.slot_index != 0:
			failures.append("the first visible bag slot must start at inventory index 0")
		if first_slot.icon == null:
			failures.append("the first bag slot must show its item icon")

	var first_instance := bag_content.get_child(0).get_instance_id()
	var scroll_bar := bag_viewport.get_v_scroll_bar()
	bag_viewport.scroll_vertical = int(ceil(scroll_bar.max_value))
	await tree.process_frame
	await tree.process_frame

	if bag_content.get_child_count() != pool_size:
		failures.append("scrolling must not allocate or remove bag slot controls")
	if bag_content.get_child(0).get_instance_id() != first_instance:
		failures.append("scrolling must reuse the existing bag slot controls")

	var max_index := -1
	for child in bag_content.get_children():
		var slot := child as InventoryBagSlot
		if slot == null:
			continue
		max_index = maxi(max_index, slot.slot_index)
		if slot.slot_index >= capacity:
			failures.append("bag slots must never bind past the inventory capacity")
	if max_index != capacity - 1:
		failures.append("scrolling to the bottom must bind the last inventory slot")

	var sort_button := _find(panel, "SortButton") as Button
	if sort_button == null:
		failures.append("the items page needs the painted SortButton hitbox")
	else:
		sort_button.pressed.emit()
		await tree.process_frame

	area.queue_free()
	await tree.process_frame
	return failures


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)
