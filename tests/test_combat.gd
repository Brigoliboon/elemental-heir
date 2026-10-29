extends RefCounted
## Smoke test for the sword hitbox: a warrior swing must damage a mob in front.
## Physics is needed, so this runs on the real physics frames.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var warrior_scene := load("res://entities/characters/warrior.tscn") as PackedScene
	var mob_scene := load("res://entities/enemies/mob.tscn") as PackedScene
	if warrior_scene == null or mob_scene == null:
		failures.append("combat scenes did not load")
		return failures

	var player := warrior_scene.instantiate() as Character
	var mob := mob_scene.instantiate() as Node2D
	tree.root.add_child(player)
	tree.root.add_child(mob)
	await tree.physics_frame
	mob.set_physics_process(false)

	# Use the gameplay render scale (areas use 1.5-2.0) and stand both actors on
	# the same ground line so the sword swing can reach the shorter mob.
	player.set_render_scale(2.0)
	var ground_y := Character.FEET_OFFSET_LOCAL * 2.0
	mob.position = Vector2(100.0, ground_y - 90.0)
	await tree.physics_frame

	if player.sword_hitbox == null:
		failures.append("sword hitbox was not created")
		_cleanup(player, mob)
		return failures

	var before: int = mob.current_health
	player.attack()
	var landed := false
	for _frame in range(40):
		await tree.physics_frame
		if mob.current_health < before:
			landed = true
			break

	var expected_sword := Damage.final_damage(
		player.stats.get_stat(Stats.ATTACK),
		mob.stats.get_stat(Stats.DEFENCE),
	)
	if not landed:
		failures.append("a warrior attack did not damage a mob in front of the sword")
	elif mob.current_health != before - expected_sword:
		failures.append("sword damage must use the attacker's Stats and target defence")

	# Test depth miss: mob is in front horizontally but 100px above in depth.
	# The sword swing should miss because depth_tolerance rejects the hit.
	mob.position = Vector2(100.0, ground_y - 90.0 - 100.0)
	await tree.physics_frame
	var hp_before_depth_miss: int = mob.current_health
	player.attack()
	for _frame in range(40):
		await tree.physics_frame
	if mob.current_health != hp_before_depth_miss:
		failures.append("sword should miss a mob that is on a different depth plane")

	# Return mob to valid ground line for the return attack test.
	var player_before: int = player.current_health
	mob.position = Vector2(-60.0, 0.0)
	mob.attack_timer = 0.0
	mob.set_physics_process(true)
	var mob_landed := false
	for _frame in range(240):
		await tree.physics_frame
		if player.current_health < player_before:
			mob_landed = true
			break

	var expected_mob := Damage.final_damage(
		mob.stats.get_stat(Stats.ATTACK),
		player.stats.get_stat(Stats.DEFENCE),
	)
	if not mob_landed:
		failures.append("a mob attack did not damage the player")
	elif player.current_health != player_before - expected_mob:
		failures.append("mob damage must use its Stats and the player's defence")

	_cleanup(player, mob)
	await tree.physics_frame
	return failures


func _cleanup(player: Node, mob: Node) -> void:
	player.queue_free()
	mob.queue_free()
