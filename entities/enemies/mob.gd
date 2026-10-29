extends CharacterBody2D
## A data-driven enemy: chases the player inside its aggro radius, stops at attack
## range, and deals damage through a timed hitbox during its attack animation.
## Depth is resolved through DepthSort so it shares the player's front/behind order.

signal health_changed(current: int, maximum: int)
signal died

@export var config: EnemyData
@export var attack_cooldown: float = 1.0
## Distance at which the mob stops chasing and starts swinging.
@export var attack_range: float = 80.0
## Distance at which the mob notices the player (matches the Attack Radius area).
@export var aggro_radius: float = 325.0
## Root-to-feet offset used as the mob's depth anchor.
@export var depth_foot_offset: float = 80.0

@export_group("Attack")
## Fraction of the attack clip where the hitbox is live.
@export_range(0.0, 1.0) var attack_hit_start := 0.35
@export_range(0.0, 1.0) var attack_hit_end := 0.65
## Hitbox offset from the mob origin, mirrored with facing.
@export var attack_hitbox_offset := Vector2(50.0, 15.0)

@onready var attack_radius: Area2D = $"Attack Radius"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Hitbox = $AttackHitbox

var player_in_range: Node2D = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var attack_damage: int = 10
var max_health: int = 100
var current_health: int = 100
## +1 facing right, -1 facing left.
var facing_sign := 1.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if config == null:
		push_error("%s has no EnemyData" % name)
	else:
		attack_damage = config.attack_damage
		max_health = config.max_health
	current_health = max_health

	attack_radius.body_entered.connect(_on_attack_radius_body_entered)
	attack_radius.body_exited.connect(_on_attack_radius_body_exited)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	attack_hitbox.damage = attack_damage
	attack_hitbox.target_group = "player"
	attack_hitbox.deactivate()
	_update_hitbox_position()


func _physics_process(delta: float) -> void:
	if config == null:
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	if is_attacking:
		_update_attack_hit()
		velocity = Vector2.ZERO
		_apply_depth()
		return

	var target := _get_target_player()
	player_in_range = target

	if target != null:
		_face_target(target)
		var to_player := target.global_position - global_position
		var distance := to_player.length()

		if distance > attack_range:
			var direction := to_player.normalized()
			velocity = direction * config.move_speed
			_play_move_animation()
			move_and_slide()
		else:
			velocity = Vector2.ZERO
			_play_idle_animation()
			if attack_timer <= 0.0:
				attack_player()
	else:
		velocity = Vector2.ZERO
		_play_idle_animation()

	_apply_depth()


## Depth index: lower on screen (larger y) renders in front.
func _apply_depth() -> void:
	z_index = DepthSort.z_for_y(global_position.y + depth_foot_offset)


func _get_target_player() -> Node2D:
	if is_instance_valid(player_in_range):
		if global_position.distance_to(player_in_range.global_position) <= aggro_radius:
			return player_in_range
		player_in_range = null

	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player") as Node2D
	if player != null and global_position.distance_to(player.global_position) <= aggro_radius:
		return player
	return null


func _face_target(target: Node2D) -> void:
	facing_sign = -1.0 if target.global_position.x < global_position.x else 1.0
	animated_sprite.flip_h = facing_sign < 0.0
	_update_hitbox_position()


func _update_hitbox_position() -> void:
	attack_hitbox.position = Vector2(absf(attack_hitbox_offset.x) * facing_sign, attack_hitbox_offset.y)


func _play_move_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
	var anim := "walk" if animated_sprite.sprite_frames.has_animation("walk") else "default"
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _play_idle_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
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


## Enables the damage area only while the attack clip is between hit_start and hit_end.
func _update_attack_hit() -> void:
	if animated_sprite.animation != "attack" or animated_sprite.sprite_frames == null:
		return
	var frame_count := animated_sprite.sprite_frames.get_frame_count("attack")
	var progress := float(animated_sprite.frame) / float(maxi(frame_count - 1, 1))
	var should_hit := progress >= attack_hit_start and progress <= attack_hit_end

	if should_hit:
		if not attack_hitbox.is_active():
			attack_hitbox.activate(attack_damage)
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


func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if current_health <= 0:
		return
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()
