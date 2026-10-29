extends RefCounted
## Verifies that blocking reduces incoming damage by CharacterData.block_damage_reduction.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load("res://entities/characters/warrior.tscn") as PackedScene
	if packed == null:
		failures.append("warrior.tscn did not load")
		return failures

	var player := packed.instantiate() as Character
	tree.root.add_child(player)
	await tree.process_frame

	var reduction := player.config.block_damage_reduction
	if reduction <= 0.0:
		failures.append("CharacterData.block_damage_reduction must be positive")
		player.queue_free()
		await tree.process_frame
		return failures

	var mitigated := Damage.final_damage(50.0, player.stats.get_stat(Stats.DEFENCE))

	# Hit without blocking
	player.block(false)
	await tree.process_frame
	var hp_before := player.current_health
	player.take_damage(50)
	await tree.process_frame
	var dmg_without_block := hp_before - player.current_health
	if dmg_without_block != mitigated:
		failures.append("unblocked hit should deal defence-mitigated damage (got %d)" % dmg_without_block)

	player.heal(dmg_without_block)
	await tree.process_frame
	player.health.clear_invulnerability()

	# Hit while blocking
	player.block(true)
	await tree.process_frame
	if not player.is_blocking():
		failures.append("block(true) must set _is_blocking")
	hp_before = player.current_health
	player.take_damage(50)
	await tree.process_frame
	var dmg_with_block := hp_before - player.current_health
	var expected := int(float(mitigated) * (1.0 - reduction))
	if dmg_with_block != expected:
		failures.append("blocked hit should deal reduced damage: expected %d, got %d" % [expected, dmg_with_block])

	player.queue_free()
	await tree.process_frame
	return failures