extends RefCounted
## Validates the shared Health component: damage, healing, death, i-frames and reset.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var health := Health.new()
	health.name = "Health"
	health.max_health = 50
	health.invulnerability_seconds = 0.0
	tree.root.add_child(health)
	await tree.process_frame

	if health.current_health != 50:
		failures.append("Health must start at max_health")
	if not health.is_alive():
		failures.append("a fresh Health pool must be alive")

	var changes: Array = []
	var damage_events: Array = []
	var heal_events: Array = []
	var death_count := [0]
	health.health_changed.connect(func(current: int, maximum: int) -> void:
		changes.append([current, maximum])
	)
	health.damaged.connect(func(amount: int, remaining: int) -> void:
		damage_events.append([amount, remaining])
	)
	health.healed.connect(func(amount: int, remaining: int) -> void:
		heal_events.append([amount, remaining])
	)
	health.died.connect(func() -> void: death_count[0] += 1)

	if not health.take_damage(20):
		failures.append("take_damage must report a landed hit")
	if health.current_health != 30:
		failures.append("take_damage must subtract from current_health")
	if changes.is_empty() or changes.back() != [30, 50]:
		failures.append("take_damage must emit health_changed(30, 50)")
	if damage_events.is_empty() or damage_events.back() != [20, 30]:
		failures.append("take_damage must emit damaged(20, 30)")

	if health.heal(100) != 20:
		failures.append("heal must report the amount actually restored")
	if health.current_health != 50:
		failures.append("heal must clamp at max_health")
	if heal_events.is_empty():
		failures.append("heal must emit healed")

	if not health.take_damage(999):
		failures.append("lethal damage must report a landed hit")
	if health.current_health != 0:
		failures.append("health must clamp at zero, not go negative")
	if health.is_alive():
		failures.append("zero health must mean dead")
	if death_count[0] != 1:
		failures.append("death must emit exactly once")
	if health.take_damage(5):
		failures.append("a dead Health pool must ignore further damage")
	if death_count[0] != 1:
		failures.append("a dead Health pool must not emit died again")
	if health.heal(10) != 0 or health.current_health != 0:
		failures.append("heal must not revive a dead pool")

	health.reset()
	if not health.is_alive() or health.current_health != 50:
		failures.append("reset must restore full health")

	health.invulnerability_seconds = 0.5
	if not health.take_damage(10):
		failures.append("the first hit must land")
	if health.take_damage(10):
		failures.append("i-frames must ignore a follow-up hit")
	if health.current_health != 40:
		failures.append("i-frames must not apply the ignored hit")
	health.clear_invulnerability()
	if not health.take_damage(10):
		failures.append("clearing i-frames must allow the next hit")
	if health.current_health != 30:
		failures.append("cleared i-frames must apply damage")

	health.invulnerability_seconds = 0.0
	health.set_max_health(60, true)
	if health.max_health != 60 or health.current_health != 36:
		failures.append("set_max_health(keep_ratio) must preserve the health percentage")
	health.configure(80)
	if health.max_health != 80 or health.current_health != 80:
		failures.append("configure must reset to a new full pool")

	health.queue_free()
	await tree.process_frame
	return failures
