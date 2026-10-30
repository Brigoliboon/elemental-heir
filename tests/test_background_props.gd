extends RefCounted
## Validates that background-relative props and obstacle footprints stay locked
## to the background when the viewport changes.


const VILLAGE := "res://scenes/areas/forest/forest_village_square.tscn"
const FIGHT := "res://scenes/areas/forest/forest_fight.tscn"
const DESIGN_BACKGROUND_SCALE := 1.5
const FOUNTAIN_DESIGN_POSITION := Vector2(1083.125, 781.06256)


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var previous_size := tree.root.size

	for size in [Vector2i(2400, 1080), Vector2i(1280, 720)]:
		tree.root.size = size
		await tree.process_frame

		var village := (load(VILLAGE) as PackedScene).instantiate()
		tree.root.add_child(village)
		await tree.process_frame
		failures.append_array(_check_village(village))
		village.queue_free()
		await tree.process_frame

		var fight := (load(FIGHT) as PackedScene).instantiate()
		tree.root.add_child(fight)
		await tree.process_frame
		failures.append_array(_check_fight(fight))
		fight.queue_free()
		await tree.process_frame

	tree.root.size = previous_size
	await tree.process_frame
	return failures


func _check_village(area: Node) -> Array[String]:
	var failures: Array[String] = []
	var background := area.get_node_or_null("Background") as Sprite2D
	var props := area.get_node_or_null("BackgroundProps") as Node2D
	var overlay := area.get_node_or_null("BackgroundProps/Sprite2D") as DepthOverlay
	var body := area.get_node_or_null("BackgroundProps/StaticBody2D") as StaticBody2D

	if background == null or props == null:
		failures.append("the village needs Background and BackgroundProps")
		return failures
	if overlay == null:
		failures.append("the fountain overlay must live under BackgroundProps")
	if body == null:
		failures.append("the fountain obstacles must live under BackgroundProps")

	var expected_scale := background.scale.x / DESIGN_BACKGROUND_SCALE
	if not is_equal_approx(props.scale.x, expected_scale):
		failures.append("BackgroundProps must scale with the background")
	if not props.position.is_equal_approx(background.position):
		failures.append("BackgroundProps must share the background anchor")

	if overlay != null:
		var expected_position := background.position + FOUNTAIN_DESIGN_POSITION * expected_scale
		if not overlay.global_position.is_equal_approx(expected_position):
			failures.append("the fountain overlay must follow the background scale and anchor")
	if body != null and not is_equal_approx(body.global_scale.x, expected_scale):
		failures.append("the fountain collision must scale with the background")

	return failures


func _check_fight(area: Node) -> Array[String]:
	var failures: Array[String] = []
	var background := area.get_node_or_null("Background") as Sprite2D
	var props := area.get_node_or_null("BackgroundProps") as Node2D
	var obstacles := area.get_node_or_null("BackgroundProps/Obstacles") as StaticBody2D

	if background == null or props == null:
		failures.append("the fight scene needs Background and BackgroundProps")
		return failures
	if obstacles == null:
		failures.append("the fight obstacles must live under BackgroundProps")

	var expected_scale := background.scale.x / DESIGN_BACKGROUND_SCALE
	if not is_equal_approx(props.scale.x, expected_scale):
		failures.append("the fight props must scale with the background")
	if not props.position.is_equal_approx(background.position):
		failures.append("the fight props must share the background anchor")
	if obstacles != null and not is_equal_approx(obstacles.global_scale.x, expected_scale):
		failures.append("the fight collision must scale with the background")
	return failures
