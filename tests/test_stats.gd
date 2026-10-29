extends RefCounted
## Validates the Stats component: level-scaled base values, the
## (base + flat) * (1 + pct) pipeline, modifier sources and stats_changed.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var data := CharacterData.new()
	data.max_health = 100
	data.attack_damage = 20
	data.defence = 10
	data.move_speed = 200.0
	data.crit_rate = 0.1
	data.crit_damage = 2.0
	data.cooldown_reduction = 0.25
	data.hp_per_level = 10
	data.attack_per_level = 2
	data.defence_per_level = 1

	var stats := Stats.new()
	stats.name = "Stats"
	tree.root.add_child(stats)
	await tree.process_frame

	var change_count := [0]
	stats.stats_changed.connect(func() -> void: change_count[0] += 1)

	stats.configure(data, 3)
	if change_count[0] != 1:
		failures.append("configure must emit stats_changed once")
	_expect(failures, stats, Stats.MAX_HEALTH, 120.0, "max_health at level 3")
	_expect(failures, stats, Stats.ATTACK, 24.0, "attack at level 3")
	_expect(failures, stats, Stats.DEFENCE, 12.0, "defence at level 3")
	_expect(failures, stats, Stats.MOVE_SPEED, 200.0, "move_speed")
	_expect(failures, stats, Stats.CRIT_RATE, 0.1, "crit_rate")
	_expect(failures, stats, Stats.CRIT_DAMAGE, 2.0, "crit_damage")
	_expect(failures, stats, Stats.COOLDOWN_REDUCTION, 0.25, "cooldown_reduction")
	_expect(failures, stats, &"unknown_stat", 0.0, "unknown stat")

	# (24 + 6) * (1 + 0.25) = 37.5
	stats.add_modifier(&"weapon", Stats.ATTACK, 6.0, 0.25)
	_expect(failures, stats, Stats.ATTACK, 37.5, "flat + pct modifier")
	if change_count[0] != 2:
		failures.append("add_modifier must emit stats_changed")

	# Percentage bonuses from different sources are additive: (30) * 1.35 = 40.5
	stats.add_modifier(&"buff", Stats.ATTACK, 0.0, 0.1)
	_expect(failures, stats, Stats.ATTACK, 40.5, "pct modifiers stack additively")

	stats.add_modifier(&"weapon", Stats.DEFENCE, 5.0, 0.0)
	_expect(failures, stats, Stats.DEFENCE, 17.0, "a source can hold multiple stats")

	stats.remove_modifier(&"weapon")
	_expect(failures, stats, Stats.ATTACK, 26.4, "removing a source drops all its modifiers")
	_expect(failures, stats, Stats.DEFENCE, 12.0, "removing a source restores defence")
	stats.remove_modifier(&"missing")
	_expect(failures, stats, Stats.ATTACK, 26.4, "removing an unknown source is a no-op")

	# Reconfiguring at a new level keeps modifiers but rebuilds the base.
	stats.configure(data, 1)
	_expect(failures, stats, Stats.ATTACK, 22.0, "level reconfigure rebuilds base and keeps modifiers")
	_expect(failures, stats, Stats.MAX_HEALTH, 100.0, "level reconfigure rebuilds max_health")

	stats.remove_modifier(&"buff")
	var enemy := EnemyData.new()
	enemy.max_health = 60
	enemy.attack_damage = 15
	enemy.defence = 2
	enemy.move_speed = 220.0
	enemy.level = 2
	stats.configure(enemy, enemy.level)
	_expect(failures, stats, Stats.MAX_HEALTH, 60.0, "EnemyData max_health")
	_expect(failures, stats, Stats.ATTACK, 15.0, "EnemyData attack")
	_expect(failures, stats, Stats.DEFENCE, 2.0, "EnemyData defence")

	stats.queue_free()
	await tree.process_frame
	return failures


func _expect(
	failures: Array[String],
	stats: Stats,
	stat: StringName,
	expected: float,
	label: String,
) -> void:
	var actual := stats.get_stat(stat)
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %.2f, got %.2f" % [label, expected, actual])
