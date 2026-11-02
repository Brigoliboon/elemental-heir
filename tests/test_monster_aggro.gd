extends RefCounted
## Validates engagement persistence: once a monster reaches attack range it keeps
## chasing the player even when they run back outside the aggro radius.

const MOB_SCENE := "res://entities/enemies/mob.tscn"


class TargetBody:
	extends CharacterBody2D

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 24.0
		shape.shape = circle
		add_child(shape)

	func get_feet_y() -> float:
		return global_position.y


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	# Let the tree finish building before adding test nodes from _ready().
	await tree.process_frame
	await _check_persistent_chase(tree, failures)
	return failures


func _check_persistent_chase(tree: SceneTree, failures: Array[String]) -> void:
	var data := MonsterData.new()
	data.enemy_name = "Aggro Test Monster"
	data.max_health = 100
	data.attack_damage = 5
	data.xp_reward = 0
	data.basic_attack = load("res://resources/skills/bite.tres") as MonsterSkill

	var mob := (load(MOB_SCENE) as PackedScene).instantiate() as Monster
	mob.config = data
	tree.root.add_child(mob)
	await tree.process_frame
	mob.set_physics_process(false)
	mob.aggro_radius = 200.0
	mob.attack_range = 100.0
	mob.min_attack_space = 10.0
	mob.attack_space = 60.0
	mob.attack_depth_tolerance = 30.0
	mob.global_position = Vector2.ZERO
	await tree.physics_frame
	var feet := mob.get_feet_y()

	var target := TargetBody.new()
	tree.root.add_child(target)
	target.global_position = Vector2(1000.0, feet)
	await tree.physics_frame

	# Before engaging, a player outside the notice radius stays ignored.
	if mob._get_target_player() != null:
		failures.append("a monster must ignore a player outside aggro range before engaging")

	# Reach attack range once, then run far outside the aggro radius.
	target.global_position = Vector2(50.0, feet)
	mob._physics_process(0.016)
	if not mob._engaged:
		failures.append("reaching attack range must engage the monster")

	target.global_position = Vector2(1000.0, feet)
	if mob._get_target_player() != target:
		failures.append("an engaged monster must keep chasing outside aggro range")

	# The persistence switch can still leash a monster when a scene wants that.
	mob.chase_after_engage = false
	mob._engaged = false
	if mob._get_target_player() != null:
		failures.append("chase_after_engage = false must leash the monster at aggro range")

	mob.queue_free()
	target.queue_free()
	await tree.process_frame
