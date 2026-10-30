extends RefCounted
## Validates the HUD virtual joystick art, deadzone and direction output.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the joystick test" % AREA_SCENE)
		return failures

	var area := packed.instantiate()
	tree.root.add_child(area)
	await tree.process_frame

	var joystick := area.get_node_or_null("HUD/UI/MoveControls") as HudJoystick
	if joystick == null:
		failures.append("HUD/UI/MoveControls must be a HudJoystick")
		area.queue_free()
		await tree.process_frame
		return failures

	var frame := joystick.get_node_or_null("Frame") as TextureRect
	var knob := joystick.get_node_or_null("Knob") as TextureRect
	if frame == null or frame.texture == null:
		failures.append("the joystick must show joystick_frame.png")
	if knob == null or knob.texture == null:
		failures.append("the joystick must show joystick_btn.png")
	if joystick.direction != Vector2.ZERO:
		failures.append("the joystick must start centered")

	var center := joystick.size * 0.5
	if joystick.size.x <= 0.0:
		failures.append("the joystick control must have a visible size")

	joystick.update_from_local(center + Vector2(joystick.size.x * 0.35, 0.0))
	if joystick.direction.x < 0.9 or absf(joystick.direction.y) > 0.01:
		failures.append("dragging right must produce a rightward direction")

	joystick.update_from_local(center)
	if joystick.direction != Vector2.ZERO:
		failures.append("the deadzone must return the joystick to center")

	joystick.update_from_local(center + Vector2(0.0, joystick.size.y * 0.35))
	if joystick.direction.y < 0.9 or absf(joystick.direction.x) > 0.01:
		failures.append("dragging down must produce a downward direction")

	joystick.reset()
	if joystick.direction != Vector2.ZERO:
		failures.append("reset must clear the joystick direction")
	if knob != null and not knob.position.is_equal_approx(center - knob.size * 0.5):
		failures.append("reset must center the joystick knob")

	area.queue_free()
	await tree.process_frame
	return failures
