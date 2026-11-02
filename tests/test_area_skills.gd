extends RefCounted
## Validates the radial skill payloads: self-centred AoE bursts and ground-targeted
## impacts, including position locking at cast time and depth filtering.

const MOB_SCENE := "res://entities/enemies/mob.tscn"


class TargetBody:
	extends CharacterBody2D
	## Player stand-in: Player collision layer, player group, feet anchor and a
	## damage sink. No mask so it never pushes anything around.

	var damage_taken := 0
	var hit_count := 0

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
		hit_count += 1

	func get_feet_y() -> float:
		return global_position.y


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	# Let the tree finish building before adding test nodes from _ready().
	await tree.process_frame
	_check_validation(failures)
	await _check_aoe(tree, failures)
	await _check_ground_lock(tree, failures)
	await _check_ground_tracking(tree, failures)
	return failures


func _check_validation(failures: Array[String]) -> void:
	var aoe := AoESkill.new()
	aoe.radius = 0.0
	if aoe.validate() == "":
		failures.append("an AoE skill must reject a zero radius")

	aoe.radius = 100.0
	aoe.active_seconds = 0.0
	if aoe.validate() == "":
		failures.append("a radial skill must reject a zero active_seconds")

	aoe.active_seconds = 0.1
	aoe.damage_multiplier = 0.0
	if aoe.validate() == "":
		failures.append("a radial skill must reject a zero damage multiplier")

	aoe.damage_multiplier = 1.0
	if aoe.validate() != "":
		failures.append("a valid AoE skill must pass validation")


func _check_aoe(tree: SceneTree, failures: Array[String]) -> void:
	var mob := await _spawn(tree)
	mob.global_position = Vector2.ZERO
	await tree.physics_frame
	var feet := mob.get_feet_y()

	var left := _target(tree, Vector2(-90.0, feet))
	var right := _target(tree, Vector2(90.0, feet))
	var far := _target(tree, Vector2(900.0, feet))
	var other_depth := _target(tree, Vector2(0.0, feet + 120.0))
	await tree.physics_frame

	var skill := AoESkill.new()
	skill.id = &"nova"
	skill.radius = 180.0
	skill.active_seconds = 0.05
	skill.damage_multiplier = 1.5
	mob._execute_effect(skill)
	await _settle(tree)

	var expected := maxi(1, roundi(Damage.raw_damage(mob.stats.get_stat(Stats.ATTACK), 1.5)))
	for entry in [left, right]:
		var target := entry as TargetBody
		if target.damage_taken != expected:
			failures.append("an AoE must damage targets inside its radius (got %d, expected %d)" % [target.damage_taken, expected])
		if target.hit_count != 1:
			failures.append("an AoE must hit each target once per activation (got %d)" % target.hit_count)
	if far.damage_taken != 0:
		failures.append("an AoE must not damage targets outside its radius")
	if other_depth.damage_taken != 0:
		failures.append("an AoE must respect the impact depth tolerance")

	await _cleanup(tree, mob, [left, right, far, other_depth])


func _check_ground_lock(tree: SceneTree, failures: Array[String]) -> void:
	var mob := await _spawn(tree)
	mob.global_position = Vector2.ZERO
	await tree.physics_frame
	var feet := mob.get_feet_y()

	var target := _target(tree, Vector2(300.0, feet))
	await tree.physics_frame

	var skill := GroundTargetSkill.new()
	skill.id = &"locked_slam"
	skill.radius = 120.0
	skill.active_seconds = 0.05
	skill.lock_at_cast = true
	mob._cast_skill(skill, false, target)

	# The player dodges after the cast starts; the impact must stay on the old spot.
	target.global_position = Vector2(900.0, feet)
	var marker := _target(tree, Vector2(300.0, feet))
	await tree.physics_frame
	mob._execute_effect(skill)
	await _settle(tree)

	if marker.damage_taken == 0:
		failures.append("a locked ground target must hit the position captured at cast time")
	if target.damage_taken != 0:
		failures.append("a locked ground target must not follow a target that moved away")

	await _cleanup(tree, mob, [target, marker])


func _check_ground_tracking(tree: SceneTree, failures: Array[String]) -> void:
	var mob := await _spawn(tree)
	mob.global_position = Vector2.ZERO
	await tree.physics_frame
	var feet := mob.get_feet_y()

	var target := _target(tree, Vector2(300.0, feet))
	await tree.physics_frame

	var skill := GroundTargetSkill.new()
	skill.id = &"tracking_slam"
	skill.radius = 120.0
	skill.active_seconds = 0.05
	skill.lock_at_cast = false
	mob._cast_skill(skill, false, target)

	# Without the lock, the impact should follow the target to its new position.
	target.global_position = Vector2(600.0, feet)
	var old_spot := _target(tree, Vector2(300.0, feet))
	await tree.physics_frame
	mob._execute_effect(skill)
	await _settle(tree)

	if target.damage_taken == 0:
		failures.append("an unlocked ground target must re-sample the target at impact")
	if old_spot.damage_taken != 0:
		failures.append("an unlocked ground target must not hit the stale cast position")

	await _cleanup(tree, mob, [target, old_spot])


func _spawn(tree: SceneTree) -> Monster:
	var data := MonsterData.new()
	data.enemy_name = "Area Test Monster"
	data.max_health = 500
	data.attack_damage = 20
	data.move_speed = 100.0
	data.xp_reward = 0
	data.basic_attack = load("res://resources/skills/bite.tres") as MonsterSkill

	var mob := (load(MOB_SCENE) as PackedScene).instantiate() as Monster
	mob.config = data
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)
	return mob


func _target(tree: SceneTree, position: Vector2) -> TargetBody:
	var target := TargetBody.new()
	tree.root.add_child(target)
	target.global_position = position
	return target


## Three physics frames let activate() run its deferred monitoring and overlap scan.
func _settle(tree: SceneTree) -> void:
	for _frame in 3:
		await tree.physics_frame
	await tree.create_timer(0.1).timeout


func _cleanup(tree: SceneTree, mob: Monster, targets: Array) -> void:
	mob.queue_free()
	for entry in targets:
		var node := entry as Node
		if is_instance_valid(node):
			node.queue_free()
	await tree.process_frame
