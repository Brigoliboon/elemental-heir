extends RefCounted
## Validates the shared ground shadow on the player and every enemy scene.

const PLAYER_SCENE := "res://entities/characters/warrior.tscn"
const ENEMY_SCENES := [
	"res://entities/enemies/mob.tscn",
	"res://entities/enemies/boarlet.tscn",
	"res://entities/enemies/hollowhart.tscn",
	"res://entities/enemies/guardian.tscn",
	"res://entities/enemies/rootbound.tscn",
]


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_check_scene(failures, PLAYER_SCENE)
	for path in ENEMY_SCENES:
		_check_scene(failures, path)
	await _check_player_runtime(tree, failures)
	return failures


func _check_scene(failures: Array[String], path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("%s did not load" % path)
		return
	var node := packed.instantiate()
	if node == null:
		failures.append("%s did not instantiate" % path)
		return
	var shadow := node.get_node_or_null("Shadow") as EntityShadow
	if shadow == null:
		failures.append("%s has no EntityShadow child" % path)
		node.free()
		return
	if shadow.z_index != -1:
		failures.append("%s shadow must sit below the body" % path)
	if not shadow.z_as_relative:
		failures.append("%s shadow must inherit the entity depth index" % path)
	if shadow.position.y <= 0.0:
		failures.append("%s shadow must sit below the entity origin" % path)
	if shadow.shadow_size.x <= 0.0 or shadow.shadow_size.y <= 0.0:
		failures.append("%s shadow needs a positive size" % path)
	if shadow.opacity <= 0.0 or shadow.opacity > 1.0:
		failures.append("%s shadow opacity must be in (0, 1]" % path)
	node.free()


func _check_player_runtime(tree: SceneTree, failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		failures.append("warrior scene did not load for the shadow runtime check")
		return
	var player := packed.instantiate() as Character
	if player == null:
		failures.append("warrior scene did not instantiate for the shadow runtime check")
		return
	tree.root.add_child(player)
	await tree.process_frame

	var shadow := player.get_node_or_null("Shadow") as EntityShadow
	if shadow == null:
		failures.append("warrior shadow disappeared at runtime")
		player.queue_free()
		await tree.process_frame
		return

	if not (shadow.get("_texture") is GradientTexture2D):
		failures.append("warrior shadow did not build its texture")
	if is_zero_approx(shadow.global_position.y):
		failures.append("warrior shadow must sit below the entity origin")

	var shadow_y := shadow.global_position.y
	player.set_facing(not player.facing_right)
	await tree.process_frame
	if not is_equal_approx(shadow.global_position.y, shadow_y):
		failures.append("warrior shadow must not move when the player turns")

	player.health.kill()
	await tree.create_timer(0.6).timeout
	if shadow.modulate.a > 0.05:
		failures.append("warrior shadow must fade on death")
	player.revive()
	await tree.process_frame
	if not is_equal_approx(shadow.modulate.a, 1.0):
		failures.append("warrior shadow must return on revive")

	player.queue_free()
	await tree.process_frame
