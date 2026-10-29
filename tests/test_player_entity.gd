extends RefCounted
## Validates that warrior.tscn is a usable player entity.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://entities/characters/warrior.tscn") as PackedScene
	if packed == null:
		failures.append("warrior.tscn did not load")
		return failures

	var player := packed.instantiate()
	tree.root.add_child(player)
	await tree.process_frame

	if not player is CharacterBody2D:
		failures.append("warrior.tscn root must be a CharacterBody2D")
	if not player is Character:
		failures.append("warrior.tscn root must use the Character script")
	if not player.is_in_group("player"):
		failures.append("warrior entity must be in the 'player' group")
	if player.collision_layer != 2:
		failures.append("warrior entity must sit on the Player physics layer (2)")
	if not player.config is CharacterData:
		failures.append("warrior entity must reference CharacterData")
	if player.get_node_or_null("CollisionShape2D") == null:
		failures.append("warrior entity needs a CollisionShape2D")
	if player.get_node_or_null("Skeleton2D") == null:
		failures.append("warrior entity needs a Skeleton2D")
	if player.get_node_or_null("AnimationPlayer") == null:
		failures.append("warrior entity needs an AnimationPlayer")
	if player.current_health != player.config.max_health:
		failures.append("health must initialize from CharacterData.max_health")

	var skeleton := player.get_node("Skeleton2D")
	if skeleton.get_child_count() == 0:
		failures.append("warrior rig did not build any bones")

	var before: int = player.current_health
	player.take_damage(7)
	if player.current_health != before - 7:
		failures.append("take_damage must reduce current health")

	player.queue_free()
	await tree.process_frame
	return failures
