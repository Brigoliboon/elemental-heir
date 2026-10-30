extends RefCounted
## Validates the HUD map shortcut and the full-screen world map scene.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const MAP_SCENE := "res://scenes/map/world_map.tscn"
const MAP_BUTTON_PATH := "res://assets/ui/hud/map-btn.png"
const MAP_BACKGROUND_PATH := "res://assets/backgrounds/world-map.jpg"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var area_packed := load(AREA_SCENE) as PackedScene
	if area_packed == null:
		failures.append("%s did not load for the world map test" % AREA_SCENE)
		return failures

	var area := area_packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var map_button := area.get_node_or_null("HUD/UI/MapButton") as TextureButton
	if map_button == null:
		failures.append("HUD/UI/MapButton must be a TextureButton")
	elif map_button.texture_normal == null:
		failures.append("the map button must have its art assigned")
	elif map_button.texture_normal.resource_path != MAP_BUTTON_PATH:
		failures.append("the map button must use %s" % MAP_BUTTON_PATH)

	if area.get_node_or_null("HUD/UI/StatsButton") != null:
		failures.append("the top-right StatsButton must be removed")
	if area.get_node_or_null("HUD/UI/InventoryButton") != null:
		failures.append("the top-right InventoryButton must be removed")

	if map_button != null:
		if not map_button.pressed.is_connected(Callable(area, "_on_map_button_pressed")):
			failures.append("the map button must open the world map")

	area.queue_free()
	await tree.process_frame

	var map_packed := load(MAP_SCENE) as PackedScene
	if map_packed == null:
		failures.append("%s did not load" % MAP_SCENE)
		return failures

	var map := map_packed.instantiate() as Control
	tree.root.add_child(map)
	await tree.process_frame

	var background := map.get_node_or_null("Background") as TextureRect
	var back_button := map.get_node_or_null("BackButton") as Button
	var zoom_in := map.get_node_or_null("ZoomControls/ZoomIn") as Button
	var zoom_out := map.get_node_or_null("ZoomControls/ZoomOut") as Button

	if background == null:
		failures.append("the world map needs a Background TextureRect")
	else:
		if background.texture == null:
			failures.append("the world map background must have its art assigned")
		elif background.texture.resource_path != MAP_BACKGROUND_PATH:
			failures.append("the world map background must use %s" % MAP_BACKGROUND_PATH)
		if not is_equal_approx(background.anchor_right, 1.0):
			failures.append("the world map background must fill the screen horizontally")
		if not is_equal_approx(background.anchor_bottom, 1.0):
			failures.append("the world map background must fill the screen vertically")

	if back_button == null:
		failures.append("the world map needs a BackButton")
	if zoom_in == null or zoom_out == null:
		failures.append("the world map needs zoom in and zoom out buttons")

	if background != null and zoom_in != null and zoom_out != null:
		var initial_scale := background.scale.x
		if not is_equal_approx(initial_scale, 1.0):
			failures.append("the world map must start at its fit-to-screen zoom")

		zoom_in.pressed.emit()
		await tree.process_frame
		if background.scale.x <= initial_scale:
			failures.append("zoom in must enlarge the world map")

		zoom_out.pressed.emit()
		await tree.process_frame
		if not is_equal_approx(background.scale.x, initial_scale):
			failures.append("zoom out must return to the fit-to-screen zoom")

		for i in range(20):
			zoom_in.pressed.emit()
		await tree.process_frame
		if background.scale.x > 3.001:
			failures.append("zoom in must clamp at the maximum zoom")

		for i in range(20):
			zoom_out.pressed.emit()
		await tree.process_frame
		if background.scale.x < 0.999:
			failures.append("zoom out must clamp at the fit-to-screen zoom")

	map.queue_free()
	await tree.process_frame
	return failures
