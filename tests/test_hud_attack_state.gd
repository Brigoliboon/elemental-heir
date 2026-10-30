extends RefCounted
## Validates the attack button's pressed opacity feedback.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the attack state test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var attack_button := area.get_node_or_null("HUD/UI/AttackButton") as TextureButton
	if attack_button == null:
		failures.append("HUD/UI/AttackButton must be a TextureButton")
		area.queue_free()
		await tree.process_frame
		return failures

	if not is_equal_approx(attack_button.modulate.a, 1.0):
		failures.append("the attack button must start fully opaque")

	attack_button.button_down.emit()
	await tree.process_frame
	if attack_button.modulate.a >= 1.0:
		failures.append("the attack button must dim while pressed")

	attack_button.button_up.emit()
	await tree.process_frame
	if not is_equal_approx(attack_button.modulate.a, 1.0):
		failures.append("the attack button must return to full opacity on release")

	area.queue_free()
	await tree.process_frame
	return failures
