extends RefCounted
## Validates the shared death flow: player death/revive, mob death fade, and the
## area HUD health bar with timed respawn.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	failures.append_array(await _check_player_death(tree))
	failures.append_array(await _check_mob_death(tree))
	failures.append_array(await _check_area_respawn(tree))
	return failures


func _check_player_death(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://entities/characters/warrior.tscn") as PackedScene
	if packed == null:
		failures.append("warrior.tscn did not load for death test")
		return failures

	var player := packed.instantiate() as Character
	tree.root.add_child(player)
	await tree.process_frame

	if player.health == null:
		failures.append("player must own a Health component")
		player.queue_free()
		await tree.process_frame
		return failures
	if player.health.max_health != player.config.max_health:
		failures.append("player Health must initialize from CharacterData.max_health")
	if player.health.invulnerability_seconds <= 0.0:
		failures.append("player Health must configure i-frames")
	if player.get_node_or_null("Health") != player.health:
		failures.append("player Health must be the scene's Health node")

	var death_count := [0]
	player.died.connect(func() -> void: death_count[0] += 1)

	player.health.kill()
	if death_count[0] != 1:
		failures.append("lethal player damage must emit died once")
	if player.is_alive():
		failures.append("player must be dead at zero health")
	if not player.is_dead():
		failures.append("Character.is_dead must report the death state")

	var before := player.position
	player.move_2d(Vector2.RIGHT, 1.0)
	player.attack()
	if player.position != before:
		failures.append("dead players must ignore movement")
	if player.is_attacking():
		failures.append("dead players must ignore attacks")

	player.revive()
	if not player.is_alive():
		failures.append("revive must restore player health")
	if player.current_health != player.max_health:
		failures.append("revive must restore full health")
	if player.is_dead():
		failures.append("revive must clear the death state")
	if player.health.is_invulnerable():
		failures.append("revive must clear i-frames")

	player.queue_free()
	await tree.process_frame
	return failures


func _check_mob_death(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://entities/enemies/mob.tscn") as PackedScene
	if packed == null:
		failures.append("mob.tscn did not load for death test")
		return failures

	var mob := packed.instantiate()
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)

	if mob.health == null:
		failures.append("mob must own a Health component")
		mob.queue_free()
		await tree.process_frame
		return failures
	if mob.health.max_health != mob.config.max_health:
		failures.append("mob Health must initialize from EnemyData.max_health")

	var bar := mob.get_node_or_null("HealthBar") as WorldHealthBar
	if bar == null:
		failures.append("mob must have a WorldHealthBar")
	elif bar.visible:
		failures.append("a full-health mob bar must start hidden")

	mob.take_damage(10)
	await tree.process_frame
	if mob.current_health != mob.max_health - 10:
		failures.append("mob take_damage must reduce its shared health")
	if bar != null and not bar.visible:
		failures.append("a damaged mob bar must become visible")

	var death_count := [0]
	mob.died.connect(func() -> void: death_count[0] += 1)
	mob.take_damage(mob.current_health)
	if death_count[0] != 1:
		failures.append("lethal mob damage must emit died once")
	if mob.is_alive() or not mob.is_dead():
		failures.append("mob must enter the dead state")

	await tree.create_timer(0.8).timeout
	if is_instance_valid(mob):
		failures.append("dead mobs must fade out and free themselves")
		mob.queue_free()
		await tree.process_frame
	return failures


func _check_area_respawn(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://scenes/areas/forest/forest_village_square.tscn") as PackedScene
	if packed == null:
		failures.append("forest_village_square.tscn did not load for respawn test")
		return failures

	var area := packed.instantiate() as Area
	area.respawn_delay = 0.15
	tree.root.add_child(area)
	await tree.process_frame

	var bar := area.get_node_or_null("HUD/UI/PlayerHealth/HealthBar") as ProgressBar
	var label := area.get_node_or_null("HUD/UI/PlayerHealth/HealthLabel") as Label
	var death_label := area.get_node_or_null("HUD/UI/DeathLabel") as Label
	if bar == null or label == null or death_label == null:
		failures.append("area HUD must contain the player health bar, label and death overlay")
	else:
		if bar.max_value != float(area.player.max_health):
			failures.append("HUD health bar max must track player.max_health")
		if bar.value != float(area.player.current_health):
			failures.append("HUD health bar value must track player.current_health")
		if not label.text.contains(str(area.player.current_health)):
			failures.append("HUD health label must show current health")
		if death_label.visible:
			failures.append("death overlay must start hidden")

	area.player.take_damage(20)
	await tree.process_frame
	if bar != null and bar.value != float(area.player.current_health):
		failures.append("HUD health bar must update after damage")

	# Kill directly; an attack equal to max health would be reduced by defence.
	area.player.health.kill()
	await tree.process_frame
	if area.player.is_alive():
		failures.append("lethal damage must kill the area player")
	if death_label != null and not death_label.visible:
		failures.append("the death overlay must show while the player is down")

	await tree.create_timer(0.6).timeout
	if is_instance_valid(area):
		if not area.player.is_alive():
			failures.append("area must respawn the player after the death delay")
		elif area.player.current_health != area.player.max_health:
			failures.append("respawn must restore full player health")
		if death_label != null and death_label.visible:
			failures.append("the death overlay must hide after respawn")
		if bar != null and bar.value != float(area.player.max_health):
			failures.append("HUD health bar must refill after respawn")
		if not is_equal_approx(area.player.position.x, area.world_width * area.spawn_x_ratio):
			failures.append("respawn must return the player to the area spawn point")

		area.queue_free()
		await tree.process_frame
	return failures
