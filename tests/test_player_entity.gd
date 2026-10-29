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
	if player.stats == null or player.get_node_or_null("Stats") != player.stats:
		failures.append("warrior entity must own its Stats node")

	var skeleton := player.get_node("Skeleton2D")
	if skeleton.get_child_count() == 0:
		failures.append("warrior rig did not build any bones")

	if player.sword_hitbox == null:
		failures.append("warrior must build a sword hitbox under the sword bone")
	else:
		if player.sword_hitbox.get_parent() != player.rig.bones.get("sword"):
			failures.append("sword hitbox must be parented to the sword bone")
		if player.sword_hitbox.collision_layer != 8:
			failures.append("sword hitbox must sit on Player_Attacks (8)")
		if player.sword_hitbox.collision_mask != 4:
			failures.append("sword hitbox must mask the Enemies layer (4)")
		if player.sword_hitbox.target_group != "enemies":
			failures.append("sword hitbox must target the 'enemies' group")
		if player.sword_hitbox.is_active():
			failures.append("sword hitbox must start inactive")

	var before: int = player.current_health
	var expected := Damage.final_damage(7.0, player.stats.get_stat(Stats.DEFENCE))
	player.take_damage(7)
	if player.current_health != before - expected:
		failures.append("take_damage must mitigate incoming damage through Stats.defence")

	player.queue_free()
	await tree.process_frame
	return failures
