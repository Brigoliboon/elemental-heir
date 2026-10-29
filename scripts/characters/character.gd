class_name Character
extends CharacterBody2D
## A rigged side-view character. Builds its skeleton and clips from a CharacterData and
## exposes a small API (move, attack, facing, health) for whatever controls it. Later systems
## such as status and inventory should be added here as their own components.

signal facing_changed(facing_right: bool)
signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died
signal blocking_changed(blocking: bool)

## Horizontal center of the rig in source-art pixels. The skeleton is shifted by this so the
## body center sits on the Character origin; facing flips mirror `scale.x`, so without it
## the whole body jumps sideways by twice this offset every time the character turns.
const RIG_CENTER_X := 31.0
## Distance from the Character origin down to the soles, in rig units (scale 1).
const FEET_OFFSET_LOCAL := 141.7
## Blade hitbox in sword-bone space (source-art pixels). The sword art is 16x64 with
## its grip pivot near the top, so the box is centred down the blade.
const SWORD_HITBOX_SIZE := Vector2(20.0, 58.0)
const SWORD_HITBOX_CENTER := Vector2(0.0, 22.0)
## Impulse applied to enemies hit by the sword, in px/s.
const SWORD_KNOCKBACK := 260.0

@export var config: CharacterData

var rig: CharacterRig
var animations: WarriorSideAnimations
var combo: AttackCombo
## Shared health pool. Scene entities own a `Health` child; a runtime one is created
## when a scene (or test) does not provide it.
var health: Health
## Lives under the sword bone so it follows every swing automatically.
var sword_hitbox: Hitbox
var walk_speed := 230.0
var run_speed := 360
var facing_right := true
## On-screen size of the rig. Defaults to config.base_scale; areas shrink or grow it
## with depth. Move speed follows it so the feet don't slide.
var render_scale := 3.0
## How fast the character moves up/down through the scene, relative to its run speed.
var depth_speed_ratio := 0.6

## Kept for compatibility with HUD/UI code: both read through the Health component.
var max_health: int:
	get: return health.max_health if health != null else 0
var current_health: int:
	get: return health.current_health if health != null else 0

var _manual_animation := "idle"
var _is_moving := false
var _is_blocking := false
var _is_dead := false
var _flash_tween: Tween
var _death_tween: Tween

@onready var skeleton: Skeleton2D = $Skeleton2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if config == null:
		push_error("%s has no CharacterData" % name)
		return
	add_to_group("player")
	_ensure_health()
	rig = CharacterRig.new(config, skeleton)
	rig.build()
	animations = WarriorSideAnimations.new(rig)
	walk_speed = animations.compute_walk_speed()
	run_speed = animations.compute_run_speed()
	anim_player.add_animation_library("", animations.build_library(config.attacks))
	combo = AttackCombo.new(anim_player, config)
	combo.combo_ended.connect(_on_combo_ended)
	render_scale = config.base_scale
	_build_sword_hitbox()
	_apply_scale()
	anim_player.play("idle")


func _process(_delta: float) -> void:
	_update_sword_hitbox()


func is_attacking() -> bool:
	return combo != null and combo.is_attacking()


## Runs the character by direction (-1, 0, 1); idle when 0. Ignored mid-attack.
func move(direction: int, delta: float) -> void:
	move_2d(Vector2(direction, 0), delta)


## Runs left/right (x) and up/down through the scene's depth (y); idle when zero.
## Ignored mid-attack.
func move_2d(direction: Vector2, delta: float) -> void:
	if config == null or _is_dead:
		return
	if is_attacking() or _is_blocking:
		return
	if direction != Vector2.ZERO:
		_is_moving = true
		if direction.x != 0.0:
			set_facing(direction.x > 0.0)
		var speed := run_speed * render_scale / config.base_scale
		var step := direction.normalized() * speed * delta
		step.y *= depth_speed_ratio
		position += step
		if anim_player.current_animation != "run":
			anim_player.play("run", 0.08)
	elif _is_moving:
		_is_moving = false
		_manual_animation = "idle"
		anim_player.play("idle")
	elif _manual_animation != "" and anim_player.current_animation != _manual_animation:
		anim_player.play(_manual_animation)


func attack() -> void:
	if _is_blocking or _is_dead:
		return
	if combo != null:
		combo.press()


## Raise or lower the guard. While blocking, incoming damage is reduced and
## movement/attacks are ignored. Safe to call every frame while held.
func block(on: bool = true) -> void:
	if _is_dead:
		return
	if _is_blocking == on:
		return
	_is_blocking = on
	if on:
		_manual_animation = "block"
		anim_player.play("block", 0.0)
	else:
		_manual_animation = "idle"
		anim_player.play("idle", 0.08)
	blocking_changed.emit(_is_blocking)


## Returns true while the guard is up.
func is_blocking() -> bool:
	return _is_blocking


## Plays a looping clip ("idle", "walk" or "run") in place. Ignored mid-attack.
func play_manual(anim_name: String) -> void:
	if is_attacking() or _is_dead:
		return
	_manual_animation = anim_name
	anim_player.play(anim_name)


func set_facing(right: bool) -> void:
	if facing_right == right:
		return
	facing_right = right
	_apply_scale()
	facing_changed.emit(facing_right)


func set_render_scale(value: float) -> void:
	render_scale = value
	_apply_scale()


func _apply_scale() -> void:
	skeleton.position.x = -RIG_CENTER_X
	scale = Vector2(render_scale if facing_right else -render_scale, render_scale)


## Creates the blade's damage area under the sword bone. Because it is parented to the
## animated bone it tracks the swing for free, including the mirrored facing transform.
func _build_sword_hitbox() -> void:
	var sword_bone := rig.bones.get("sword") as Bone2D
	if sword_bone == null:
		push_warning("%s rig has no 'sword' bone; attacks will not deal damage" % name)
		return

	sword_hitbox = Hitbox.new()
	sword_hitbox.name = "SwordHitbox"
	sword_hitbox.damage = config.attack_damage
	sword_hitbox.knockback_force = SWORD_KNOCKBACK
	sword_hitbox.target_group = "enemies"
	sword_hitbox.collision_layer = 8  # Player_Attacks
	sword_hitbox.collision_mask = 4  # Enemies

	var shape := RectangleShape2D.new()
	shape.size = SWORD_HITBOX_SIZE
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	collision.position = SWORD_HITBOX_CENTER
	sword_hitbox.add_child(collision)
	sword_bone.add_child(sword_hitbox)


## Turns the sword hitbox on only during the active window of the current attack clip.
func _update_sword_hitbox() -> void:
	if sword_hitbox == null or config == null:
		return

	var data := _current_attack_data()
	var active := false
	if data != null and anim_player.current_animation == data.id:
		var length := anim_player.current_animation_length
		var t := anim_player.current_animation_position
		active = length > 0.0 and t >= data.hit_start * length and t <= data.hit_end * length

	if active:
		if not sword_hitbox.is_active():
			sword_hitbox.activate(data.damage if data.damage > 0 else config.attack_damage)
	elif sword_hitbox.is_active():
		sword_hitbox.deactivate()


func _current_attack_data() -> AttackData:
	if combo == null or config == null:
		return null
	var hit := combo.current_hit()
	if hit <= 0 or hit > config.attacks.size():
		return null
	return config.attacks[hit - 1]


func toggle_facing() -> void:
	set_facing(not facing_right)


## Applies damage through the shared Health component. Guard reduction stays here
## because it is character-specific; i-frames and death live on Health.
func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if health == null or not health.is_alive() or health.is_invulnerable():
		return
	if _is_blocking and config != null:
		amount = maxi(0, int(float(amount) * (1.0 - config.block_damage_reduction)))
	health.take_damage(amount)


func heal(amount: int) -> int:
	return health.heal(amount) if health != null else 0


func is_alive() -> bool:
	return health != null and health.is_alive()


## True once the death sequence has started. Stays true until `revive()`.
func is_dead() -> bool:
	return _is_dead


## Restores full health and clears the death visual. Areas call this on respawn.
func revive() -> void:
	if health == null:
		return
	health.reset()
	_is_dead = false
	_is_moving = false
	_is_blocking = false
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	if skeleton != null:
		skeleton.modulate = Color.WHITE
	_manual_animation = "idle"
	if anim_player.has_animation("idle"):
		anim_player.play("idle")


func _ensure_health() -> void:
	health = get_node_or_null("Health") as Health
	if health == null:
		health = Health.new()
		health.name = "Health"
		add_child(health)
	health.configure(config.max_health)
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_health_damaged(amount: int, _remaining: int) -> void:
	_flash_damage()
	damaged.emit(amount)


func _on_health_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_moving = false
	_is_blocking = false
	if combo != null:
		combo.cancel()
	if sword_hitbox != null:
		sword_hitbox.deactivate()
	if anim_player.has_animation("idle"):
		anim_player.play("idle")
	_play_death_fade()
	died.emit()


func _flash_damage() -> void:
	if skeleton == null or _is_dead:
		return
	skeleton.modulate = Color(1.0, 0.35, 0.35, 1.0)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(skeleton, "modulate", Color.WHITE, 0.18)


func _play_death_fade() -> void:
	if skeleton == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(skeleton, "modulate", Color(1.0, 1.0, 1.0, 0.25), 0.45)


func _on_combo_ended() -> void:
	_is_moving = false
	_manual_animation = "idle"
	if sword_hitbox != null:
		sword_hitbox.deactivate()
