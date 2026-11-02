extends RefCounted
## Validates the monster framework: data migration, skill gates, damage
## multipliers, buff expiry, summon caps, summon XP suppression, auras and the
## General/Guardian scenes. These are the rules the whole rank system relies on.

const MOB_SCENE := "res://entities/enemies/mob.tscn"
const BOARLET_SCENE := "res://entities/enemies/boarlet.tscn"
const ROOTBOUND_SCENE := "res://entities/enemies/rootbound.tscn"
const GUARDIAN_SCENE := "res://entities/enemies/guardian.tscn"

const ENTITY_DATA := [
	"res://resources/entities/goblin.tres",
	"res://resources/entities/boarlet.tres",
	"res://resources/entities/hollowhart.tres",
	"res://resources/entities/rootbound.tres",
	"res://resources/entities/guardian.tres",
]


class TargetBody:
	extends CharacterBody2D
	## Stand-in for the player: on the Player collision layer, in the player group,
	## with a feet anchor so the hitbox depth check has something to compare.

	var damage_taken := 0

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 24.0
		shape.shape = circle
		add_child(shape)

	func take_damage(amount: int, _knockback := Vector2.ZERO) -> void:
		damage_taken += amount

	func get_feet_y() -> float:
		return global_position.y


class ExperiencePlayer:
	extends Node2D

	var experience := 0

	func _init() -> void:
		add_to_group("player")

	func add_experience(amount: int) -> void:
		experience += amount


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_check_data(failures)
	await _check_scenes(tree, failures)
	await _check_skill_gates(tree, failures)
	await _check_melee_multiplier(tree, failures)
	await _check_buff_expiry(tree, failures)
	await _check_summons(tree, failures)
	await _check_aura(tree, failures)
	return failures


func _check_data(failures: Array[String]) -> void:
	for path in ENTITY_DATA:
		var data := load(path) as MonsterData
		if data == null:
			failures.append("%s must load as MonsterData" % path)
			continue
		if data.basic_attack == null:
			failures.append("%s has no basic_attack" % path)
		for skill in data.skills:
			if skill == null:
				failures.append("%s contains a null skill" % path)
				continue
			if skill is SummonSkill and (skill as SummonSkill).summon_scene == null:
				failures.append("%s skill '%s' has no summon scene" % [path, skill.id])

	var guardian := load("res://resources/entities/guardian.tres") as MonsterData
	if guardian == null or guardian.rank != MonsterData.Rank.GUARDIAN:
		failures.append("guardian.tres must use the GUARDIAN rank")
	elif guardian.passives.is_empty():
		failures.append("guardian.tres needs the aura passive")

	var general := load("res://resources/entities/rootbound.tres") as MonsterData
	if general == null or general.rank != MonsterData.Rank.GENERAL:
		failures.append("rootbound.tres must use the GENERAL rank")


func _check_scenes(tree: SceneTree, failures: Array[String]) -> void:
	for path in [BOARLET_SCENE, ROOTBOUND_SCENE, GUARDIAN_SCENE]:
		var packed := load(path) as PackedScene
		if packed == null:
			failures.append("%s did not load" % path)
			continue
		var monster := packed.instantiate() as Monster
		if monster == null:
			failures.append("%s must instantiate as Monster" % path)
			continue
		tree.root.add_child(monster)
		await tree.process_frame
		monster.set_physics_process(false)

		if monster.config == null or not monster.config is MonsterData:
			failures.append("%s must use MonsterData" % path)
		elif monster.health.max_health != monster.config.max_health:
			failures.append("%s health must initialize from MonsterData" % path)

		var sprite := monster.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null:
			failures.append("%s needs SpriteFrames" % path)
		else:
			for animation in [&"default", &"attack"]:
				if not sprite.sprite_frames.has_animation(animation):
					failures.append("%s is missing the '%s' animation" % [path, animation])
			for skill in (monster.config as MonsterData).all_skills():
				if skill != null and not sprite.sprite_frames.has_animation(skill.animation):
					failures.append("%s skill '%s' animation '%s' is missing" % [path, skill.id, skill.animation])

		if path == ROOTBOUND_SCENE:
			_check_skill_overlays(monster, sprite, failures)

		monster.queue_free()
		await tree.process_frame


## The General's overgrowth aura and root trail are visual overlays triggered by
## their matching skill animations rather than body clips.
func _check_skill_overlays(monster: Monster, sprite: AnimatedSprite2D, failures: Array[String]) -> void:
	if sprite == null:
		return
	var aura := sprite.get_node_or_null("OvergrowthAura") as AnimatedSprite2D
	var trail := sprite.get_node_or_null("RootTrail") as AnimatedSprite2D
	if aura == null or trail == null:
		failures.append("rootbound needs the overgrowth aura and root trail overlays")
		return
	var data := monster.config as MonsterData
	var charge := _find_skill(data, &"charge")
	var enrage := _find_skill(data, &"enrage")
	if charge != null:
		monster._cast_skill(charge, false, null)
		if not trail.visible:
			failures.append("casting the root charge must show the root trail")
		if aura.visible:
			failures.append("the root charge must not show the overgrowth aura")
	if enrage != null:
		monster._cast_skill(enrage, false, null)
		if not aura.visible:
			failures.append("casting enrage must show the overgrowth aura")


func _find_skill(data: MonsterData, id: StringName) -> MonsterSkill:
	for skill in data.skills:
		if skill != null and skill.id == id:
			return skill
	return null


func _check_skill_gates(tree: SceneTree, failures: Array[String]) -> void:
	var dummy := Node2D.new()
	tree.root.add_child(dummy)

	var ranged := MeleeSkill.new()
	ranged.id = &"ranged"
	ranged.min_range = 200.0
	ranged.max_range = 400.0

	var gated := MeleeSkill.new()
	gated.id = &"gated"
	gated.max_range = 1000.0
	gated.health_below = 0.4

	var capped := MeleeSkill.new()
	capped.id = &"capped"
	capped.max_range = 1000.0
	capped.max_casts = 1

	var low := MeleeSkill.new()
	low.id = &"low"
	low.max_range = 1000.0
	low.priority = 1

	var high := MeleeSkill.new()
	high.id = &"high"
	high.max_range = 1000.0
	high.priority = 5

	var summon := SummonSkill.new()
	summon.id = &"test_summon"
	summon.max_range = 1000.0
	summon.summon_scene = load(BOARLET_SCENE) as PackedScene
	summon.max_alive = 1
	summon.count = 1

	var data := _make_data(load("res://resources/skills/bite.tres") as MonsterSkill)
	data.rank = MonsterData.Rank.NORMAL

	var mob := await _spawn(tree, data)
	dummy.global_position = Vector2.ZERO

	# Range gate: only the out-of-range skill is equipped.
	data.skills.append(ranged)
	if mob._pick_special(dummy) != null:
		failures.append("a skill outside its min range must not be eligible")
	data.skills.clear()
	mob._skill_cooldowns.clear()

	# Health gate: phase-gated skill stays locked until the threshold.
	data.skills.append(gated)
	if mob._pick_special(dummy) != null:
		failures.append("a health-gated skill must stay locked above its threshold")
	mob.health.current_health = 20
	if mob._pick_special(dummy) == null:
		failures.append("a health-gated skill must unlock below its threshold")
	mob.health.current_health = mob.health.max_health
	data.skills.clear()

	# Cast cap: a once-per-fight skill is spent after one cast.
	data.skills.append(capped)
	mob._skill_casts[capped] = 1
	if mob._pick_special(dummy) != null:
		failures.append("a skill at max_casts must not be eligible")
	data.skills.clear()
	mob._skill_casts.erase(capped)

	# Summon cap: no room while max_alive summons are already alive.
	data.skills.append(summon)
	var summon_alive := (load(BOARLET_SCENE) as PackedScene).instantiate() as Monster
	tree.root.add_child(summon_alive)
	mob._summons[summon] = [summon_alive]
	if mob._summon_has_room(summon):
		failures.append("a summon at max_alive must report no room")
	if mob._pick_special(dummy) != null:
		failures.append("a summon at max_alive must not be eligible")
	mob._summons.erase(summon)
	summon_alive.queue_free()
	await tree.process_frame
	if mob._pick_special(dummy) != summon:
		failures.append("a NORMAL rank must be allowed to use a summon skill")
	data.skills.clear()

	# Priority: the highest-priority eligible skill wins.
	data.skills.append(low)
	data.skills.append(high)
	var picked := mob._pick_special(dummy)
	if picked != high:
		failures.append("the highest-priority eligible skill must win")

	mob.queue_free()
	dummy.queue_free()
	await tree.process_frame


func _check_melee_multiplier(tree: SceneTree, failures: Array[String]) -> void:
	var data := _make_data(load("res://resources/skills/bite.tres") as MonsterSkill)
	var mob := await _spawn(tree, data)

	var target := TargetBody.new()
	tree.root.add_child(target)
	target.global_position = Vector2(60.0, mob.get_feet_y())
	await tree.physics_frame

	var skill := MeleeSkill.new()
	skill.damage_multiplier = 2.0
	skill.hitbox_offset = Vector2(60.0, 0.0)
	skill.hitbox_size = Vector2(200.0, 150.0)
	skill.hit_depth_tolerance = 60.0
	mob._prepare_melee(skill)
	mob.attack_hitbox.activate()
	for _frame in 4:
		await tree.physics_frame

	var expected := maxi(1, roundi(Damage.raw_damage(mob.stats.get_stat(Stats.ATTACK), 2.0)))
	if target.damage_taken != expected:
		failures.append("melee multiplier must scale hitbox damage (got %d, expected %d)" % [target.damage_taken, expected])

	mob.attack_hitbox.deactivate()
	mob.queue_free()
	target.queue_free()
	await tree.process_frame


func _check_buff_expiry(tree: SceneTree, failures: Array[String]) -> void:
	var data := _make_data(load("res://resources/skills/bite.tres") as MonsterSkill)
	var mob := await _spawn(tree, data)
	var base_attack := mob.stats.get_stat(Stats.ATTACK)

	var attack_buff := StatBuff.new()
	attack_buff.stat = Stats.ATTACK
	attack_buff.pct = 0.5
	attack_buff.seconds = 0.2

	var skill := BuffSkill.new()
	skill.id = &"rage"
	skill.buffs.append(attack_buff)
	mob._apply_skill_buffs(skill)

	if not is_equal_approx(mob.stats.get_stat(Stats.ATTACK), base_attack * 1.5):
		failures.append("a buff skill must raise attack by its percentage")

	mob._tick_buffs(0.1)
	if not is_equal_approx(mob.stats.get_stat(Stats.ATTACK), base_attack * 1.5):
		failures.append("a buff must survive until its timer expires")
	mob._tick_buffs(0.2)
	if not is_equal_approx(mob.stats.get_stat(Stats.ATTACK), base_attack):
		failures.append("an expired buff must remove its modifier")

	var hp_buff := StatBuff.new()
	hp_buff.stat = Stats.MAX_HEALTH
	hp_buff.pct = 0.5
	var base_max := mob.health.max_health
	mob.apply_buffs([hp_buff], &"test_hp")
	if mob.health.max_health <= base_max:
		failures.append("a max-health buff must raise the health pool")
	mob.remove_buff_source(&"test_hp")
	if mob.health.max_health != base_max:
		failures.append("removing a max-health buff must restore the pool")

	mob.queue_free()
	await tree.process_frame


func _check_summons(tree: SceneTree, failures: Array[String]) -> void:
	var player := ExperiencePlayer.new()
	tree.root.add_child(player)

	var buff := StatBuff.new()
	buff.stat = Stats.ATTACK
	buff.pct = 0.5

	var summon := SummonSkill.new()
	summon.id = &"pack"
	summon.cooldown = 0.0
	summon.max_range = 1000.0
	summon.summon_scene = load(BOARLET_SCENE) as PackedScene
	summon.count = 3
	summon.max_alive = 2
	summon.spawn_telegraph = 0.0
	summon.buffs.append(buff)

	var data := _make_data(load("res://resources/skills/bite.tres") as MonsterSkill)
	data.skills.append(summon)
	var mob := await _spawn(tree, data)

	mob._summon(summon)
	await tree.process_frame
	var living := mob._living_summons(summon)
	if living != 2:
		failures.append("a summon skill must respect max_alive (got %d, expected 2)" % living)
	if mob._summon_has_room(summon):
		failures.append("a summon skill at max_alive must have no room")

	for node in mob._summons.get(summon, []):
		var summon_monster := node as Monster
		if summon_monster == null:
			failures.append("summons must be Monster scenes")
			continue
		if not summon_monster.is_summoned() or summon_monster.summoner != mob:
			failures.append("a summon must know its summoner")
		if summon_monster.stats.get_stat(Stats.ATTACK) <= summon_monster.stats.get_base(Stats.ATTACK):
			failures.append("a summoned monster must receive its skill buffs")
		summon_monster.set_physics_process(false)

	# Summons are worth no experience.
	var summoned := mob._summons[summon][0] as Monster
	var survivor := mob._summons[summon][1] as Monster
	var xp_before := player.experience
	summoned.take_damage(99999)
	await tree.process_frame
	if player.experience != xp_before:
		failures.append("killing a summon must not grant experience")

	# A freed summon reference must not poison the next summon check.
	await tree.create_timer(0.5).timeout
	if mob._living_summons(summon) != 1:
		failures.append("a freed summon must be pruned from the living count")

	# A normal monster still grants its reward.
	var normal := (load(BOARLET_SCENE) as PackedScene).instantiate() as Monster
	tree.root.add_child(normal)
	await tree.process_frame
	normal.set_physics_process(false)
	var normal_xp := normal.config.xp_reward
	normal.take_damage(99999)
	await tree.process_frame
	if player.experience != xp_before + normal_xp:
		failures.append("a normal monster must still grant experience")

	# Telegraphs reserve their slots, so spamming a summon cannot overshoot the cap.
	var telegraph_skill := SummonSkill.new()
	telegraph_skill.id = &"telegraphed_pack"
	telegraph_skill.cooldown = 0.0
	telegraph_skill.max_range = 1000.0
	telegraph_skill.summon_scene = load(BOARLET_SCENE) as PackedScene
	telegraph_skill.count = 2
	telegraph_skill.max_alive = 2
	telegraph_skill.spawn_telegraph = 0.4
	mob._summon(telegraph_skill)
	mob._summon(telegraph_skill)
	if mob._pending_for(telegraph_skill) != 2:
		failures.append("pending telegraphs must reserve summon slots")
	await tree.create_timer(0.7).timeout
	if mob._living_summons(telegraph_skill) > 2:
		failures.append("telegraphed summons must not exceed max_alive")
	for node in mob._summons.get(telegraph_skill, []):
		if node is Monster:
			(node as Monster).set_physics_process(false)

	# The summoner's death clears its adds.
	mob.take_damage(99999)
	await tree.process_frame
	if is_instance_valid(survivor) and survivor.is_inside_tree():
		failures.append("summons must despawn when their summoner dies")
		survivor.queue_free()

	player.queue_free()
	await tree.process_frame


func _check_aura(tree: SceneTree, failures: Array[String]) -> void:
	var aura := AuraPassive.new()
	aura.id = &"test_aura"
	aura.radius = 200.0
	aura.tick_seconds = 0.1
	var buff := StatBuff.new()
	buff.stat = Stats.ATTACK
	buff.pct = 0.25
	aura.buffs.append(buff)

	var data := _make_data(load("res://resources/skills/bite.tres") as MonsterSkill)
	data.passives.append(aura)
	var owner := await _spawn(tree, data)

	var near := (load(BOARLET_SCENE) as PackedScene).instantiate() as Monster
	var far := (load(BOARLET_SCENE) as PackedScene).instantiate() as Monster
	tree.root.add_child(near)
	tree.root.add_child(far)
	await tree.process_frame
	near.set_physics_process(false)
	far.set_physics_process(false)
	near.global_position = Vector2(60.0, 0.0)
	far.global_position = Vector2(900.0, 0.0)
	await tree.physics_frame

	var near_base := near.stats.get_stat(Stats.ATTACK)
	var far_base := far.stats.get_stat(Stats.ATTACK)
	owner._tick_aura(aura, 10.0)

	if near.stats.get_stat(Stats.ATTACK) <= near_base:
		failures.append("an aura must buff allies inside its radius")
	if not is_equal_approx(far.stats.get_stat(Stats.ATTACK), far_base):
		failures.append("an aura must not buff allies outside its radius")

	near.global_position = Vector2(900.0, 0.0)
	owner._tick_aura(aura, 10.0)
	if not is_equal_approx(near.stats.get_stat(Stats.ATTACK), near_base):
		failures.append("leaving the aura radius must remove its buff")

	near.global_position = Vector2(60.0, 0.0)
	owner._tick_aura(aura, 10.0)
	if near.stats.get_stat(Stats.ATTACK) <= near_base:
		failures.append("the aura must reapply when an ally comes back")

	owner.take_damage(99999)
	await tree.process_frame
	if not is_equal_approx(near.stats.get_stat(Stats.ATTACK), near_base):
		failures.append("an aura must drop when its owner dies")

	near.queue_free()
	far.queue_free()
	await tree.process_frame


func _make_data(basic: MonsterSkill) -> MonsterData:
	var data := MonsterData.new()
	data.enemy_name = "Test Monster"
	data.max_health = 100
	data.attack_damage = 10
	data.move_speed = 100.0
	data.xp_reward = 0
	data.basic_attack = basic
	return data


func _spawn(tree: SceneTree, data: MonsterData) -> Monster:
	var packed := load(MOB_SCENE) as PackedScene
	var mob := packed.instantiate() as Monster
	mob.config = data
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)
	return mob
