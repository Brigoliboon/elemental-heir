extends CharacterBody2D
## A data-driven enemy: chases the player inside its aggro radius, stops at attack
## range, and deals damage through a timed hitbox during its attack animation.
## Depth is resolved through DepthSort so it shares the player's front/behind order.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died

@export var config: EnemyData
@export var attack_cooldown: float = 1.0
## Distance at which the mob considers the player in attack range.
@export var attack_range: float = 135.0
## Minimum distance to maintain from the player (prevents crowding/overlapping).
@export var min_attack_space: float = 85.0
## Preferred spacing from the target when moving to attack.
@export var attack_space: float = 110.0
## Maximum depth (feet y) difference to consider in attack range.
@export var attack_depth_tolerance: float = 30.0
## Distance at which the mob notices the player (matches the Attack Radius area).
@export var aggro_radius: float = 325.0
## Root-to-feet offset used as the mob's depth anchor.
@export var depth_foot_offset: float = 80.0
## How quickly a hit's knockback impulse bleeds off (px/s per second).
@export var knockback_decay: float = 1200.0
## Time the corpse fades before the mob is removed from the scene.
@export var death_fade_seconds: float = 0.35

@export_group("Attack")
## Fraction of the attack clip where the hitbox is live.
@export_range(0.0, 1.0) var attack_hit_start := 0.35
@export_range(0.0, 1.0) var attack_hit_end := 0.65
## Hitbox offset from the mob origin, mirrored with facing.
@export var attack_hitbox_offset := Vector2(70.0, 15.0)

@onready var attack_radius: Area2D = $"Attack Radius"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Hitbox = $AttackHitbox

var player_in_range: Node2D = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var attack_damage: int = 10
var move_speed := 200.0
## Shared stat block; initialized from EnemyData when the scene loads.
var stats: Stats
## Shared health pool; initialized from EnemyData when the scene loads.
var health: Health
## Positional voice built from EnemyData.sfx; silent when no set is assigned.
var sfx: SfxComponent
## Impulse velocity applied by the player's sword and decayed each physics frame.
var knockback_velocity := Vector2.ZERO
## +1 facing right, -1 facing left.
var facing_sign := 1.0

var max_health: int:
	get: return health.max_health if health != null else 0
var current_health: int:
	get: return health.current_health if health != null else 0
var _is_dead := false
var _flash_tween: Tween


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if config == null:
		push_error("%s has no EnemyData" % name)
	_ensure_stats()
	_ensure_health()
	_ensure_sfx()

	attack_radius.body_entered.connect(_on_attack_radius_body_entered)
	attack_radius.body_exited.connect(_on_attack_radius_body_exited)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	attack_hitbox.damage = attack_damage
	attack_hitbox.target_group = "player"
	attack_hitbox.attacker = self
	attack_hitbox.deactivate()
	_update_hitbox_position()


func _ensure_stats() -> void:
	stats = get_node_or_null("Stats") as Stats
	if stats == null:
		stats = Stats.new()
		stats.name = "Stats"
		add_child(stats)
	if config != null:
		stats.configure(config, config.level)
		attack_damage = int(stats.get_stat(Stats.ATTACK))
		move_speed = stats.get_stat(Stats.MOVE_SPEED)


func _ensure_health() -> void:
	health = get_node_or_null("Health") as Health
	if health == null:
		health = Health.new()
		health.name = "Health"
		add_child(health)
	var maximum := int(stats.get_stat(Stats.MAX_HEALTH)) if stats != null else 100
	health.configure(maximum)
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


## Builds the positional voice from EnemyData.sfx. A missing set stays silent.
func _ensure_sfx() -> void:
	sfx = get_node_or_null("Sfx") as SfxComponent
	if sfx == null:
		sfx = SfxComponent.new()
		sfx.name = "Sfx"
		add_child(sfx)
	if config != null:
		sfx.bind(config.sfx)


func _physics_process(delta: float) -> void:
	if config == null or _is_dead:
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	if is_attacking:
		_update_attack_hit()
		velocity = knockback_velocity
		_move_with_knockback(delta)
		_apply_depth()
		return

	var target := _get_target_player()
	player_in_range = target

	if target != null:
		_face_target(target)
		var delta_x := target.global_position.x - global_position.x
		var delta_y := DepthSort.get_feet_y(target) - get_feet_y()

		var dist_x := absf(delta_x)
		var in_depth := absf(delta_y) <= attack_depth_tolerance
		var in_attack_range := dist_x <= attack_range and dist_x >= min_attack_space

		if in_depth and in_attack_range:
			velocity = knockback_velocity
			_play_idle_animation()
			if attack_timer <= 0.0:
				attack_player()
		elif in_depth and dist_x < min_attack_space:
			# Too close to the player: back up to maintain attack space
			var back_dir := -facing_sign
			velocity = Vector2(back_dir * move_speed * 0.6, 0.0) + knockback_velocity
			_play_move_animation()
		else:
			# Navigate towards the attack space point in front of the target
			var target_x := target.global_position.x - facing_sign * attack_space
			var move_dx := target_x - global_position.x
			var direction := Vector2(move_dx, delta_y).normalized()
			velocity = direction * move_speed + knockback_velocity
			_play_move_animation()
	else:
		velocity = knockback_velocity
		_play_idle_animation()

	_move_with_knockback(delta)
	_apply_depth()


## World-space y coordinate of the mob's feet (depth anchor).
func get_feet_y() -> float:
	return global_position.y + depth_foot_offset * scale.y


func _move_with_knockback(delta: float) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	if velocity != Vector2.ZERO:
		move_and_slide()


## Depth index: lower on screen (larger y) renders in front.
func _apply_depth() -> void:
	z_index = DepthSort.z_for_y(get_feet_y())


func _get_target_player() -> Node2D:
	if is_instance_valid(player_in_range):
		if _ground_distance_to(player_in_range) <= aggro_radius:
			return player_in_range
		player_in_range = null

	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player") as Node2D
	if player != null and _ground_distance_to(player) <= aggro_radius:
		return player
	return null


func _ground_distance_to(target: Node2D) -> float:
	var delta_x := target.global_position.x - global_position.x
	var delta_y := DepthSort.get_feet_y(target) - get_feet_y()
	return Vector2(delta_x, delta_y).length()


func _face_target(target: Node2D) -> void:
	facing_sign = -1.0 if target.global_position.x < global_position.x else 1.0
	# Source monster art is drawn facing left. When facing left (facing_sign < 0),
	# flip_h is false. When facing right (facing_sign > 0), flip_h is true.
	animated_sprite.flip_h = facing_sign > 0.0
	_update_hitbox_position()


func _update_hitbox_position() -> void:
	attack_hitbox.position = Vector2(absf(attack_hitbox_offset.x) * facing_sign, attack_hitbox_offset.y)


func _play_move_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
	if sfx != null:
		sfx.idle_enabled = false
	var anim := "walk" if animated_sprite.sprite_frames.has_animation("walk") else "default"
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _play_idle_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
	if sfx != null:
		sfx.idle_enabled = true
	if animated_sprite.animation != "default":
		animated_sprite.play("default")


func attack_player() -> void:
	if not is_instance_valid(player_in_range):
		player_in_range = null
		return
	if animated_sprite.sprite_frames == null or not animated_sprite.sprite_frames.has_animation("attack"):
		push_warning("Missing 'attack' animation in AnimatedSprite2D.")
		return

	is_attacking = true
	attack_timer = attack_cooldown
	attack_hitbox.deactivate()
	animated_sprite.play("attack")
	if sfx != null:
		sfx.idle_enabled = false
		sfx.play_attack()


## Enables the damage area only while the attack clip is between hit_start and hit_end.
func _update_attack_hit() -> void:
	if animated_sprite.animation != "attack" or animated_sprite.sprite_frames == null:
		return
	var frame_count := animated_sprite.sprite_frames.get_frame_count("attack")
	var progress := float(animated_sprite.frame) / float(maxi(frame_count - 1, 1))
	var should_hit := progress >= attack_hit_start and progress <= attack_hit_end

	if should_hit:
		if not attack_hitbox.is_active():
			attack_hitbox.activate()
	elif attack_hitbox.is_active():
		attack_hitbox.deactivate()


func _on_attack_radius_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = body
		attack_timer = minf(attack_timer, 0.35)


func _on_attack_radius_body_exited(body: Node2D) -> void:
	if body == player_in_range:
		player_in_range = null


func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack":
		is_attacking = false
		attack_hitbox.deactivate()
		animated_sprite.play("default")
		if sfx != null:
			sfx.idle_enabled = true


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0 or health == null or not health.is_alive() or health.is_invulnerable():
		return
	if stats != null:
		amount = Damage.final_damage(float(amount), stats.get_stat(Stats.DEFENCE))
	if health.take_damage(amount) and not _is_dead and knockback != Vector2.ZERO:
		knockback_velocity += knockback


func is_alive() -> bool:
	return health != null and health.is_alive()


func is_dead() -> bool:
	return _is_dead


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_health_damaged(amount: int, _remaining: int) -> void:
	_flash_damage()
	damaged.emit(amount)
	if amount > 0:
		_spawn_damage_number(amount, Color(1.0, 0.9, 0.3))
	if sfx != null:
		sfx.play_hurt()


func _spawn_damage_number(amount: int, color: Color) -> void:
	var scene := load("res://scenes/ui/damage_number.tscn") as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node2D
	if node == null:
		return
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(node)
	node.global_position = global_position + Vector2(0, -20)
	node.setup(amount, color)


func _on_health_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	is_attacking = false
	knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	attack_hitbox.deactivate()
	attack_radius.set_deferred("monitoring", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_physics_process(false)
	_award_experience()
	if sfx != null:
		sfx.play_death()
	died.emit()
	_play_death_fade()


## Grants EnemyData.xp_reward to the player when this mob dies.
func _award_experience() -> void:
	if config == null or config.xp_reward <= 0 or get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_experience"):
		player.add_experience(config.xp_reward)


func _flash_damage() -> void:
	if _is_dead:
		return
	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.18)


## Fades the whole corpse (sprite and health bar) and removes it from the scene.
func _play_death_fade() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), death_fade_seconds)
	tween.tween_callback(queue_free)
