extends RefCounted
## Validates the HUD player profile level and inventory shortcut.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const PROFILE_PATH := "res://assets/ui/hud/player-profile.png"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the HUD profile test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var profile := area.get_node_or_null("HUD/UI/PlayerHealth/Profile") as TextureButton
	var level_label := area.get_node_or_null("HUD/UI/PlayerHealth/LevelLabel") as Label
	var inventory_panel := area.get_node_or_null("HUD/UI/InventoryPanel") as InventoryPanel

	if profile == null:
		failures.append("HUD/UI/PlayerHealth/Profile must be a TextureButton")
	elif profile.texture_normal == null:
		failures.append("the profile must have its art assigned")
	elif profile.texture_normal.resource_path != PROFILE_PATH:
		failures.append("the profile must use %s" % PROFILE_PATH)

	if level_label == null:
		failures.append("the HUD needs PlayerHealth/LevelLabel")
	elif level_label.text != str(area.player.level):
		failures.append("the level label must show the player's current level")

	if level_label != null:
		area.player.apply_progress(3, 0)
		await tree.process_frame
		if level_label.text != "3":
			failures.append("the level label must update when the player levels")

	if inventory_panel == null:
		failures.append("the HUD needs the inventory panel")
	elif profile != null:
		inventory_panel.hide_panel()
		profile.pressed.emit()
		await tree.process_frame
		if not inventory_panel.visible:
			failures.append("clicking the profile must open the inventory")
		profile.pressed.emit()
		await tree.process_frame
		if inventory_panel.visible:
			failures.append("clicking the profile again must close the inventory")

	area.queue_free()
	await tree.process_frame
	return failures
