extends RefCounted
## A held joystick must survive the scene change that the player triggers by
## walking into an exit. The new area's joystick should resume the same touch.

const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const JOYSTICK_PATH := "HUD/UI/MoveControls"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the joystick scene-change test" % AREA_SCENE)
		return failures

	var first := packed.instantiate() as Area
	tree.root.add_child(first)
	await tree.process_frame
	await tree.process_frame

	var first_stick := first.get_node_or_null(JOYSTICK_PATH) as HudJoystick
	if first_stick == null:
		failures.append("the first area needs %s" % JOYSTICK_PATH)
		first.queue_free()
		await tree.process_frame
		return failures

	var center := first_stick.global_position + first_stick.size * 0.5
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = center
	first_stick._input(press)

	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(first_stick.size.x * 0.35, 0.0)
	first_stick._input(drag)
	if first_stick.direction.x < 0.9:
		failures.append("the joystick must move before the scene changes")

	first.queue_free()
	await tree.process_frame

	var second := packed.instantiate() as Area
	tree.root.add_child(second)
	await tree.process_frame
	await tree.process_frame

	var second_stick := second.get_node_or_null(JOYSTICK_PATH) as HudJoystick
	if second_stick == null:
		failures.append("the second area needs %s" % JOYSTICK_PATH)
	elif second_stick.direction.x < 0.9:
		failures.append("the new joystick must resume the held direction")

	if second_stick != null:
		var next_center := second_stick.global_position + second_stick.size * 0.5
		var next_drag := InputEventScreenDrag.new()
		next_drag.index = 0
		next_drag.position = next_center + Vector2(0.0, second_stick.size.y * 0.35)
		second_stick._input(next_drag)
		if second_stick.direction.y < 0.9 or absf(second_stick.direction.x) > 0.01:
			failures.append("the new joystick must keep following the same drag")

		var release := InputEventScreenTouch.new()
		release.index = 0
		release.pressed = false
		release.position = next_drag.position
		second_stick._input(release)
		if second_stick.direction != Vector2.ZERO:
			failures.append("releasing the touch must clear the joystick")

	second.queue_free()
	await tree.process_frame

	var third := packed.instantiate() as Area
	tree.root.add_child(third)
	await tree.process_frame
	await tree.process_frame

	var third_stick := third.get_node_or_null(JOYSTICK_PATH) as HudJoystick
	if third_stick != null and third_stick.direction != Vector2.ZERO:
		failures.append("a released touch must not leak into the next area")

	third.queue_free()
	await tree.process_frame
	return failures
