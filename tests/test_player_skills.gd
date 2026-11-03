extends RefCounted
## Guards the player skill data and runtime: cost, cooldown, energy, and the four
## kit behaviours (heavy hit, Iron Will mitigation, War Cry slow, Ground Slam).
## Physics is needed for the sword and shockwave, so those checks run on real frames.

const WARRIOR_SCENE := "res://entities/characters/warrior.tscn"
const MOB_SCENE := "res://entities/enemies/mob.tscn"
const ROOTBOUND_SCENE := "res://entities/enemies/rootbound.tscn"
const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_check_data(failures)
	await _check_energy_and_cooldowns(tree, failures)
	await _check_heavy_strike(tree, failures)
	await _check_iron_will(tree, failures)
	await _check_war_cry(tree, failures)
	await _check_ground_slam(tree, failures)
	await _check_hud(tree, failures)
	return failures


func _check_data(failures: Array[String]) -> void:
	var data := load("res://resources/characters/warrior.tres") as CharacterData
	if data == null:
		failures.append("warrior.tres did not load for the skill suite")
		return
	var expected := [&"heavy_strike", &"war_cry", &"ground_slam", &"iron_will"]
	if data.skills.size() != expected.size():
		failures.append("warrior.tres should equip 4 skills, got %d" % data.skills.size())
		return
	for i in expected.size():
		var skill := data.skills[i]
		if skill == null:
			failures.append("skill slot %d is null" % (i + 1))
			continue
		if skill.id != expected[i]:
			failures.append("skill slot %d should be %s, got %s" % [i + 1, expected[i], skill.id])
		var problem := skill.validate()
		if problem != "":
			failures.append("%s is invalid: %s" % [skill.id, problem])
		if skill.icon == null:
			failures.append("%s has no HUD icon" % skill.id)
		if skill.keys.is_empty():
			failures.append("%s has no baked key poses" % skill.id)
	if data.max_energy <= 0 or data.energy_regen <= 0.0:
		failures.append("CharacterData must provide an energy pool and regen")

	var heavy := data.skills[0]
	if not heavy.uses_sword or not is_equal_approx(heavy.damage_multiplier, 2.0):
		failures.append("Heavy Strike must use the sword at double damage")
	if heavy.hit_flash_color.a <= 0.0:
		failures.append("Heavy Strike must flash its target")
	if heavy.energy_cost != 15 or not is_equal_approx(heavy.cooldown, 4.0):
		failures.append("Heavy Strike must cost 15 and cool down for 4s")

	var will := data.skills[3] as SelfBuffSkill
	if will == null:
		failures.append("Iron Will must be a SelfBuffSkill")
	else:
		if not is_equal_approx(will.damage_taken_multiplier, 0.6):
			failures.append("Iron Will must take 40% less damage")
		if not will.knockback_immune:
			failures.append("Iron Will must ignore knockback")
		if will.tier2_heal_fraction <= 0.0 or will.tier3_reflect_fraction <= 0.0:
			failures.append("Iron Will must carry its tier 2 heal and tier 3 reflect")
		if not is_equal_approx(will.cooldown, 40.0):
			failures.append("Iron Will must cool down for 40s")

	var cry := data.skills[1] as SelfBuffSkill
	if cry == null or cry.slow_radius <= 0.0 or cry.slow_factor >= 1.0:
		failures.append("War Cry must carry a slow pulse")

	var slam := data.skills[2] as GroundSlamSkill
	if slam == null or slam.radius <= 0.0 or not slam.knockdown:
		failures.append("Ground Slam must damage a radius and knock down")


func _check_energy_and_cooldowns(tree: SceneTree, failures: Array[String]) -> void:
	var player: Character = await _spawn_player(tree)
	if player == null:
		failures.append("warrior scene did not instantiate for the energy check")
		return
	var heavy := player.skill_by_id(&"heavy_strike")

	player.energy = 0.0
	if player.cast_skill(heavy):
		failures.append("a skill must not cast without energy")
	player.energy = player.max_energy
	if not player.cast_skill(heavy):
		failures.append("Heavy Strike should cast at full energy")
	elif not is_equal_approx(player.energy, player.max_energy - float(heavy.energy_cost)):
		failures.append("casting must spend exactly the skill's energy cost")
	if player.cooldown_left(heavy) <= 0.0:
		failures.append("a cast must start the skill cooldown")
	if player.cast_skill(heavy):
		failures.append("a skill on cooldown must not cast again")

	# Cooldown reduction shortens the timer but never below the safety floor.
	await _wait_for_skill_end(tree, player)
	player._cooldowns.clear()
	player.energy = player.max_energy
	player.stats.add_modifier(&"test_cd", Stats.COOLDOWN_REDUCTION, 0.5, 0.0)
	if not player.cast_skill(heavy):
		failures.append("Heavy Strike should cast after clearing its cooldown")
	elif not is_equal_approx(player.cooldown_left(heavy), 2.0):
		failures.append("50% cooldown reduction must halve the 4s cooldown")
	player.stats.remove_modifier(&"test_cd")
	player._cooldowns.clear()

	# Energy regenerates while alive.
	player.energy = 0.0
	for _i in 30:
		await tree.process_frame
	if player.energy <= 0.0:
		failures.append("energy must regenerate over time")

	_cleanup([player])
	await tree.process_frame


func _check_heavy_strike(tree: SceneTree, failures: Array[String]) -> void:
	var player: Character = await _spawn_player(tree)
	var mob: Monster = await _spawn_mob(tree)
	if player == null or mob == null:
		failures.append("combat actors did not instantiate for Heavy Strike")
		return
	_place_on_ground(player, mob, 100.0)
	await tree.physics_frame

	var heavy := player.skill_by_id(&"heavy_strike")
	var before := mob.current_health
	if not player.cast_skill(heavy):
		failures.append("Heavy Strike did not start")
		_cleanup([player, mob])
		return

	for _i in 80:
		await tree.physics_frame
		if mob.current_health < before:
			break

	var expected := Damage.final_damage(
		player.stats.get_stat(Stats.ATTACK) * heavy.damage_multiplier,
		mob.stats.get_stat(Stats.DEFENCE)
	)
	if mob.current_health >= before:
		failures.append("Heavy Strike did not damage the mob in front")
	elif mob.current_health != before - expected:
		failures.append("Heavy Strike must deal double damage (%d vs %d)" % [
			before - mob.current_health, expected,
		])

	_cleanup([player, mob])
	await tree.physics_frame


func _check_iron_will(tree: SceneTree, failures: Array[String]) -> void:
	var player: Character = await _spawn_player(tree)
	var mob: Monster = await _spawn_mob(tree)
	if player == null or mob == null:
		failures.append("actors did not instantiate for Iron Will")
		return
	var will := player.skill_by_id(&"iron_will")
	var attack_before := player.stats.get_stat(Stats.ATTACK)

	if not player.cast_skill(will):
		failures.append("Iron Will did not start")
		_cleanup([player, mob])
		return
	await _wait_for_effect(tree, player)

	if player._active_skill != will:
		failures.append("Iron Will must stay active while its clip plays")
	if not is_equal_approx(player._damage_taken_scale(), 0.6):
		failures.append("Iron Will must scale incoming damage to 0.6")
	if not player._is_knockback_immune():
		failures.append("Iron Will must report knockback immunity")
	if player.stats.get_stat(Stats.ATTACK) <= attack_before:
		failures.append("Iron Will must raise attack while active")

	var before := player.current_health
	var mitigated := roundi(Damage.final_damage(100.0, player.stats.get_stat(Stats.DEFENCE)) * 0.6)
	player.take_damage(100)
	if player.current_health != before - mitigated:
		failures.append("Iron Will must reduce a 100 hit to %d" % mitigated)

	player.take_damage(10, Vector2(500.0, 0.0))
	if player.knockback_velocity != Vector2.ZERO:
		failures.append("Iron Will must ignore knockback impulses")

	# Tier 2 heals on cast.
	await _wait_for_skill_end(tree, player)
	player.health.set_current_health(50)
	player.evolution_tier = 2
	player._cooldowns.clear()
	player.energy = player.max_energy
	if not player.cast_skill(will):
		failures.append("Iron Will should recast after clearing its cooldown")
	else:
		await _wait_for_effect(tree, player)
		var healed := roundi(float(player.max_health) * will.tier2_heal_fraction)
		if player.current_health != 50 + healed:
			failures.append("tier 2 Iron Will must heal %d" % healed)

	# Tier 3 reflects part of the damage at the attacker.
	await _wait_for_skill_end(tree, player)
	player.evolution_tier = 3
	player._cooldowns.clear()
	player.energy = player.max_energy
	if not player.cast_skill(will):
		failures.append("Iron Will should recast at tier 3")
	else:
		await _wait_for_effect(tree, player)
		var mob_before := mob.current_health
		var taken := roundi(Damage.final_damage(100.0, player.stats.get_stat(Stats.DEFENCE)) * 0.6)
		var reflected := maxi(1, roundi(float(taken) * will.tier3_reflect_fraction))
		var expected := Damage.final_damage(float(reflected), mob.stats.get_stat(Stats.DEFENCE))
		player.take_hit(100, Vector2.ZERO, mob)
		if mob.current_health != mob_before - expected:
			failures.append("tier 3 Iron Will must reflect %d damage" % expected)

	_cleanup([player, mob])
	await tree.physics_frame


func _check_war_cry(tree: SceneTree, failures: Array[String]) -> void:
	var player: Character = await _spawn_player(tree)
	var mob: Monster = await _spawn_mob(tree)
	if player == null or mob == null:
		failures.append("actors did not instantiate for War Cry")
		return
	_place_on_ground(player, mob, 120.0)
	await tree.physics_frame

	var cry := player.skill_by_id(&"war_cry")
	var attack_before := player.stats.get_stat(Stats.ATTACK)
	if not player.cast_skill(cry):
		failures.append("War Cry did not start")
		_cleanup([player, mob])
		return
	await _wait_for_effect(tree, player)

	var expected := attack_before * 1.25
	if not is_equal_approx(player.stats.get_stat(Stats.ATTACK), expected):
		failures.append("War Cry must raise attack by 25% (%s vs %s)" % [
			player.stats.get_stat(Stats.ATTACK), expected,
		])
	if mob._slow_factor >= 1.0 or mob._slow_left <= 0.0:
		failures.append("War Cry must slow a nearby mob")

	_cleanup([player, mob])
	await tree.physics_frame


func _check_ground_slam(tree: SceneTree, failures: Array[String]) -> void:
	var player: Character = await _spawn_player(tree)
	var left: Monster = await _spawn_mob(tree)
	var right: Monster = await _spawn_mob(tree)
	if player == null or left == null or right == null:
		failures.append("actors did not instantiate for Ground Slam")
		return
	_place_on_ground(player, left, -140.0)
	_place_on_ground(player, right, 140.0)
	await tree.physics_frame

	var slam := player.skill_by_id(&"ground_slam")
	var left_before := left.current_health
	var right_before := right.current_health
	if not player.cast_skill(slam):
		failures.append("Ground Slam did not start")
		_cleanup([player, left, right])
		return
	await _wait_for_effect(tree, player)
	for _i in 6:
		await tree.physics_frame

	var expected := Damage.final_damage(
		player.stats.get_stat(Stats.ATTACK) * slam.damage_multiplier,
		left.stats.get_stat(Stats.DEFENCE)
	)
	if left.current_health != left_before - expected:
		failures.append("Ground Slam must hit the enemy on the left")
	if right.current_health != right_before - expected:
		failures.append("Ground Slam must hit the enemy on the right")
	if left._knockdown_left <= 0.0 or right._knockdown_left <= 0.0:
		failures.append("Ground Slam must knock down normal mobs")

	# Generals and Guardians ignore the knockdown.
	var general := load(ROOTBOUND_SCENE).instantiate() as Monster
	tree.root.add_child(general)
	await tree.physics_frame
	general.set_physics_process(false)
	if general.can_be_knocked_down():
		failures.append("a General must not be knocked down")
	general.knock_down(1.0)
	if general._knockdown_left > 0.0:
		failures.append("knock_down must refuse an immune General")

	_cleanup([player, left, right, general])
	await tree.physics_frame


func _check_hud(tree: SceneTree, failures: Array[String]) -> void:
	var packed := load(AREA_SCENE) as PackedScene
	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame
	await tree.process_frame

	if area.skill_buttons.size() != 3:
		failures.append("the HUD must expose 3 circular skill buttons")
	for i in area.skill_buttons.size():
		var button := area.skill_buttons[i]
		if button == null:
			failures.append("HUD skill button %d is missing" % (i + 1))
		elif button.skill == null or button.skill.id != area.player.skill_in_slot(i).id:
			failures.append("HUD skill button %d is not bound to its slot" % (i + 1))
	if area._passive_skill == null or area._passive_skill.id != &"iron_will":
		failures.append("the passive button must be bound to Iron Will")

	if area.skill_buttons.size() > 0 and area.skill_buttons[0] != null:
		var before := area.player.energy
		area.skill_buttons[0].pressed.emit()
		await tree.process_frame
		if area.player.energy >= before:
			failures.append("pressing a skill button must spend energy")

	area.queue_free()
	await tree.process_frame


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _spawn_player(tree: SceneTree) -> Character:
	var scene := load(WARRIOR_SCENE) as PackedScene
	if scene == null:
		return null
	var player := scene.instantiate() as Character
	tree.root.add_child(player)
	await tree.physics_frame
	# Deterministic damage checks: no i-frames swallowing the second hit.
	player.health.invulnerability_seconds = 0.0
	player.health.clear_invulnerability()
	player.energy = player.max_energy
	return player


func _spawn_mob(tree: SceneTree) -> Monster:
	var scene := load(MOB_SCENE) as PackedScene
	if scene == null:
		return null
	var mob := scene.instantiate() as Monster
	tree.root.add_child(mob)
	await tree.physics_frame
	mob.set_physics_process(false)
	return mob


## Mirrors the combat suite: both actors on the same ground line, with the mob
## standing in front of the player's sword.
func _place_on_ground(player: Character, mob: Monster, offset_x: float) -> void:
	player.set_render_scale(2.0)
	player.position = Vector2.ZERO
	var ground_y := Character.FEET_OFFSET_LOCAL * 2.0
	mob.position = Vector2(offset_x, ground_y - 90.0)


func _wait_for_effect(tree: SceneTree, player: Character) -> void:
	for _i in 120:
		await tree.process_frame
		if player._active_skill_effect_done:
			return


func _wait_for_skill_end(tree: SceneTree, player: Character) -> void:
	for _i in 240:
		await tree.process_frame
		if not player.is_casting_skill():
			return


func _cleanup(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
