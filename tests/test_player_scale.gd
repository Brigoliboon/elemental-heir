extends RefCounted
## The character is authored against the 1.5x design background. Wider landscape
## viewports must grow the character with the background instead of leaving it
## looking small; smaller viewports must not shrink it below the authored scale.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const SIZES := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2400, 1080),
	Vector2i(2560, 1080),
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var previous_size := tree.root.size

	for size in SIZES:
		tree.root.size = size
		await tree.process_frame

		var area := (load(AREA_SCENE) as PackedScene).instantiate() as Area
		tree.root.add_child(area)
		await tree.process_frame
		await tree.process_frame

		failures.append_array(_check_player_scale(area, size))

		area.queue_free()
		await tree.process_frame

	tree.root.size = previous_size
	await tree.process_frame
	return failures


func _check_player_scale(area: Area, view: Vector2i) -> Array[String]:
	var failures: Array[String] = []
	if area.player == null:
		failures.append("the area must have a player")
		return failures

	var depth_scale := lerpf(
		area.far_character_scale,
		area.near_character_scale,
		area.depth_ratio()
	)
	var background_factor := maxf(
		1.0,
		area.background.scale.x / Area.DESIGN_BACKGROUND_SCALE
	)
	var expected := depth_scale * background_factor
	if not is_equal_approx(area.player.render_scale, expected):
		failures.append("the player scale at %s must be %.3f, got %.3f" % [
			view,
			expected,
			area.player.render_scale,
		])
	return failures
