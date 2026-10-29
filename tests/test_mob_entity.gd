extends RefCounted
## Validates that mob.tscn is wired to EnemyData and can detect the player layer.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://entities/enemies/mob.tscn") as PackedScene
	if packed == null:
		failures.append("mob.tscn did not load")
		return failures

	var mob := packed.instantiate()
	tree.root.add_child(mob)
	await tree.process_frame

	if not mob.config is EnemyData:
		failures.append("mob.tscn must reference an EnemyData resource")
		mob.queue_free()
		await tree.process_frame
		return failures

	if mob.config.enemy_name != "Goblin":
		failures.append("goblin.tres enemy_name should be 'Goblin'")
	if mob.attack_damage != mob.config.attack_damage:
		failures.append("mob attack damage must come from EnemyData")
	if mob.current_health != mob.config.max_health:
		failures.append("mob health must initialize from EnemyData.max_health")
	if mob.collision_layer != 4:
		failures.append("mob must sit on the Enemies physics layer (bit value 4)")
	if mob.collision_mask != 1:
		failures.append("mob must mask the World physics layer (1)")

	var sprite := mob.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		failures.append("mob needs an AnimatedSprite2D with SpriteFrames")
	elif sprite.sprite_frames.get_animation_loop("attack"):
		failures.append("mob attack animation must not loop")

	var area := mob.get_node_or_null("Attack Radius") as Area2D
	if area == null:
		failures.append("mob needs an Attack Radius Area2D")
	elif (area.collision_mask & 2) == 0:
		failures.append("mob attack area must detect the Player layer (2)")

	var hitbox := mob.get_node_or_null("AttackHitbox") as Hitbox
	if hitbox == null:
		failures.append("mob needs an AttackHitbox")
	else:
		if hitbox.collision_layer != 16:
			failures.append("mob hitbox must sit on Enemy_Attackss (16)")
		if hitbox.collision_mask != 2:
			failures.append("mob hitbox must mask the Player layer (2)")
		if hitbox.target_group != "player":
			failures.append("mob hitbox must target the 'player' group")
		if hitbox.is_active():
			failures.append("mob hitbox must start inactive")
		if hitbox.damage != mob.attack_damage:
			failures.append("mob hitbox damage must come from EnemyData")

	var before: int = mob.current_health
	mob.take_damage(4)
	if mob.current_health != before - 4:
		failures.append("mob take_damage must reduce current health")

	if ResourceLoader.exists("res://scripts/entity/hostile-mob.gd"):
		failures.append("unused hostile-mob.gd should be removed")

	mob.queue_free()
	await tree.process_frame
	return failures
