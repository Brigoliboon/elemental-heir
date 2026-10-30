extends RefCounted
## Validates the HUD attack button art and its connection to the player.


const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const ATTACK_PATH := "res://assets/ui/hud/attack-btn.png"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the HUD button test" % AREA_SCENE)
		return failures

	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var attack_button := area.get_node_or_null("HUD/UI/AttackButton") as TextureButton
	if attack_button == null:
		failures.append("HUD/UI/AttackButton must be a TextureButton")
	elif attack_button.texture_normal == null:
		failures.append("the attack button must have its art assigned")
	elif attack_button.texture_normal.resource_path != ATTACK_PATH:
		failures.append("the attack button must use %s" % ATTACK_PATH)

	if attack_button != null and attack_button.size.x < 120.0:
		failures.append("the attack button must be large enough for touch input")

	if attack_button != null:
		attack_button.pressed.emit()
		await tree.process_frame

	area.queue_free()
	await tree.process_frame
	return failures
