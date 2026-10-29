extends CharacterBody2D

@export var config: EnemyData
@export var attack_cooldown: float = 1.0
@export var attack_range: float = 80.0

@onready var attack_radius: Area2D = $"Attack Radius"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var player_in_range: Node2D = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var attack_damage: int = 10
var max_health: int = 100
var current_health: int = 100

signal health_changed(current: int, maximum: int)
signal died


func _ready() -> void:
	if config == null:
		push_error("%s has no EnemyData" % name)
	else:
		attack_damage = config.attack_damage
		max_health = config.max_health
	current_health = max_health
	attack_radius.body_entered.connect(_on_attack_radius_body_entered)
	attack_radius.body_exited.connect(_on_attack_radius_body_exited)
	animated_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if config == null:
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	# Resolve the current target player (Area2D detection with a fallback scan).
	var target := _get_target_player()
	player_in_range = target

	if is_attacking:
		pass
	elif target != null:
		var to_player := target.global_position - global_position
		var distance := to_player.length()
		var direction := to_player.normalized()

		if direction.x < 0:
			animated_sprite.flip_h = true
		elif direction.x > 0:
			animated_sprite.flip_h = false

		if distance > attack_range:
			position += direction * config.move_speed * delta
			if animated_sprite.animation != "default" and animated_sprite.sprite_frames.has_animation("default"):
				animated_sprite.play("default")
		else:
			if attack_timer <= 0.0:
				attack_player()
	else:
		if animated_sprite.animation != "default":
			animated_sprite.play("default")
	# Depth-based z-index: lower on screen (higher Y) renders in front
	z_index = int(global_position.y)


func _get_target_player() -> Node2D:
	if is_instance_valid(player_in_range):
		return player_in_range
	var tree := get_tree()
	if tree != null:
		var group: Variant = tree.get_first_group("player")
		if group is Node2D:
			return group as Node2D
	return null


func _on_attack_radius_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = body
		attack_timer = 0.0


func _on_attack_radius_body_exited(body: Node2D) -> void:
	if body == player_in_range:
		player_in_range = null


func attack_player() -> void:
	if not is_instance_valid(player_in_range):
		player_in_range = null
		return

	is_attacking = true
	attack_timer = attack_cooldown

	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
	else:
		push_warning("Missing 'attack' animation in AnimatedSprite2D.")


func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack":
		is_attacking = false
		animated_sprite.play("default")
		if is_instance_valid(player_in_range):
			if player_in_range.has_method("take_damage"):
				player_in_range.take_damage(attack_damage)


func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if current_health <= 0:
		return
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()
