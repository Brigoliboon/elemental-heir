extends RefCounted
## Validates the XP curve, level-up stat growth, the level cap and enemy XP rewards.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var progression := ProgressionData.new()
	progression.base_xp = 100
	progression.exponent = 1.0
	progression.max_level = 3

	if progression.xp_to_next(1) != 100:
		failures.append("xp_to_next(1) must be base_xp * 1 ^ exponent")
	if progression.xp_to_next(2) != 200:
		failures.append("xp_to_next(2) must be base_xp * 2 ^ exponent")
	if progression.xp_to_next(3) != 0:
		failures.append("xp_to_next at the level cap must be 0")

	var packed := load("res://entities/characters/warrior.tscn") as PackedScene
	if packed == null:
		failures.append("warrior.tscn did not load for the leveling test")
		return failures

	var player := packed.instantiate() as Character
	player.progression = progression
	tree.root.add_child(player)
	await tree.process_frame

	if player.level != player.config.starting_level:
		failures.append("a fresh character must start at CharacterData.starting_level")
	if player.experience != player.config.starting_exp:
		failures.append("a fresh character must start at CharacterData.starting_exp")
	if player.experience_to_next_level() != 100:
		failures.append("level 1 must require 100 XP with the test curve")

	var level_events: Array = []
	player.level_changed.connect(func(level: int, experience: int, to_next: int) -> void:
		level_events.append([level, experience, to_next])
	)

	player.add_experience(50)
	if player.level != 1 or player.experience != 50:
		failures.append("partial XP must not level the character")
	if level_events.size() != 0:
		failures.append("partial XP must not emit level_changed")

	# Kill a goblin at level 1 so the enemy reward is exercised before the cap.
	var mob_packed := load("res://entities/enemies/mob.tscn") as PackedScene
	var mob := mob_packed.instantiate()
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)
	var xp_before := player.experience
	mob.take_damage(mob.current_health)
	if player.experience != xp_before + mob.config.xp_reward:
		failures.append("a dying mob must award EnemyData.xp_reward to the player")
	mob.queue_free()
	await tree.process_frame

	# 50 + 10 already banked; add enough to reach level 2.
	player.add_experience(40)
	if player.level != 2 or player.experience != 0:
		failures.append("reaching the XP threshold must level up and carry the remainder")
	if level_events.size() != 1 or level_events.back()[0] != 2:
		failures.append("level-up must emit level_changed with the new level")
	if not is_equal_approx(player.stats.get_stat(Stats.MAX_HEALTH), 110.0):
		failures.append("level 2 must apply hp_per_level growth")
	if not is_equal_approx(player.stats.get_stat(Stats.ATTACK), 17.0):
		failures.append("level 2 must apply attack_per_level growth")
	if player.health.max_health != 110:
		failures.append("level-up must raise the shared Health maximum")
	if player.current_health != 110:
		failures.append("a full-health level-up must stay full")

	# Level 2 -> 3 needs 200 XP; 250 leaves 50 banked.
	player.add_experience(250)
	if player.level != 3 or player.experience != 50:
		failures.append("multiple level-ups must consume each level's curve in order")
	if player.experience_to_next_level() != 0:
		failures.append("the level cap must report no next level")

	player.add_experience(9999)
	if player.level != 3 or player.experience != 50:
		failures.append("XP at the level cap must be ignored")

	player.queue_free()
	await tree.process_frame
	return failures
