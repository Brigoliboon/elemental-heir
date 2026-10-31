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
signal experience_changed(experience: int, to_next: int)
signal level_changed(level: int, experience: int, to_next: int)

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
const DEFAULT_PROGRESSION := preload("res://resources/progression/default_progression.tres")

@export var config: CharacterData
## XP curve. Falls back to the shared default resource when unset.
@export var progression: ProgressionData

var rig: CharacterRig
var animations: WarriorSideAnimations
var combo: AttackCombo
## Shared stat block. Scene entities own a `Stats` child; a runtime one is created
## when a scene (or test) does not provide it.
var stats: Stats
var inventory: Inventory
## Positional voice built from CharacterData.sfx; silent when no set is assigned.
var sfx: SfxComponent
## Shared health pool. Scene entities own a `Health` child; a runtime one is created
## when a scene (or test) does not provide it.
var health: Health
var level := 1
var experience := 0
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
## Timestamp of the last shield clang, so one frame of multiple hits clangs once.
var _block_sfx_msec := -1000
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
	_ensure_stats()
	_ensure_health()
	_ensure_inventory()
	_ensure_sfx()
	rig = CharacterRig.new(config, skeleton)
	rig.build()
	animations = WarriorSideAnimations.new(rig)
	walk_speed = animations.compute_walk_speed()
	run_speed = animations.compute_run_speed()
	anim_player.add_animation_library("", animations.build_library(config.attacks))
	combo = AttackCombo.new(anim_player, config)
	combo.combo_ended.connect(_on_combo_ended)
	if sfx != null:
		combo.hit_started.connect(_on_combo_hit_started)
	render_scale = config.base_scale
	_build_sword_hitbox()
	_apply_scale()
	anim_player.play("idle")


func _process(_delta: float) -> void:
	_update_sword_hitbox()
	if sfx != null:
		# Vocalize only while genuinely idle, not mid-swing, guard or run.
		sfx.idle_enabled = not _is_dead and not _is_moving and not _is_blocking and not is_attacking()


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
	# Raising the guard interrupts a swing: cancel the combo first so the guard
	# never replaces the attack animation underneath it, which would strand the
	# combo in "attacking" forever.
	if on and combo != null:
		combo.cancel()
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


## World-space y coordinate of the character's feet (depth anchor).
func get_feet_y() -> float:
	return global_position.y + FEET_OFFSET_LOCAL * render_scale


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
	sword_hitbox.attacker = self
	sword_hitbox.damage = int(stats.get_stat(Stats.ATTACK)) if stats != null else config.attack_damage
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
			sword_hitbox.activate(data.damage if data.damage > 0 else -1)
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


## Applies damage through the shared Health component. Incoming damage is first
## mitigated by this character's defence, then reduced by the guard; i-frames and
## death live on Health.
func take_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0 or health == null or not health.is_alive():
		return
	# Give block feedback even when i-frames swallow the hit: the shield is being
	# struck either way, and a crowd of enemies otherwise makes most guards silent.
	if _is_blocking and config != null:
		_play_block_feedback()
	if health.is_invulnerable():
		return
	if stats != null:
		amount = Damage.final_damage(float(amount), stats.get_stat(Stats.DEFENCE))
	if _is_blocking and config != null:
		amount = maxi(0, int(float(amount) * (1.0 - config.block_damage_reduction)))
	health.take_damage(amount)


## One clang per impact, even if several enemies connect on the same frame.
func _play_block_feedback() -> void:
	if sfx == null:
		return
	var now := Time.get_ticks_msec()
	if now - _block_sfx_msec < 60:
		return
	_block_sfx_msec = now
	sfx.play_block()


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


## Builds the positional voice from CharacterData.sfx. A missing set stays silent.
func _ensure_sfx() -> void:
	sfx = get_node_or_null("Sfx") as SfxComponent
	if sfx == null:
		sfx = SfxComponent.new()
		sfx.name = "Sfx"
		add_child(sfx)
	if config != null:
		sfx.bind(config.sfx)


func _ensure_inventory() -> void:
	inventory = get_node_or_null("Inventory") as Inventory
	if inventory == null:
		inventory = Inventory.new()
		inventory.name = "Inventory"
		add_child(inventory)
	var sword = load("res://resources/items/weapons/default_sword.tres")
	var buckler = load("res://resources/items/weapons/default_buckler.tres")
	if sword != null:
		inventory.add_item(sword, 1)
	if buckler != null:
		inventory.add_item(buckler, 1)
	var holy = load("res://resources/items/weapons/holy_sword.tres")
	if holy != null:
		inventory.add_item(holy, 1)


func _ensure_stats() -> void:
	stats = get_node_or_null("Stats") as Stats
	if stats == null:
		stats = Stats.new()
		stats.name = "Stats"
		add_child(stats)
	if progression == null:
		progression = DEFAULT_PROGRESSION
	level = clampi(config.starting_level, 1, progression.max_level)
	experience = maxi(0, config.starting_exp)
	stats.configure(config, level)


func _ensure_health() -> void:
	health = get_node_or_null("Health") as Health
	if health == null:
		health = Health.new()
		health.name = "Health"
		add_child(health)
	var maximum := int(stats.get_stat(Stats.MAX_HEALTH)) if stats != null else config.max_health
	health.configure(maximum)
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


## XP required to advance from the current level. 0 at the level cap.
func experience_to_next_level() -> int:
	return progression.xp_to_next(level) if progression != null else 0


## Adds XP and applies every level-up the amount earns. Ignored at the cap.
func add_experience(amount: int) -> void:
	if amount <= 0 or progression == null or level >= progression.max_level:
		return
	experience += amount
	var leveled := false
	while level < progression.max_level:
		var needed := progression.xp_to_next(level)
		if needed <= 0 or experience < needed:
			break
		experience -= needed
		level += 1
		leveled = true
	if leveled:
		_apply_level_stats()
		level_changed.emit(level, experience, experience_to_next_level())
	experience_changed.emit(experience, experience_to_next_level())


## Restores level/experience from persistent progress and rebuilds derived stats.
func apply_progress(saved_level: int, saved_experience: int) -> void:
	if config == null or progression == null:
		return
	level = clampi(saved_level, 1, progression.max_level)
	experience = maxi(0, saved_experience)
	_apply_level_stats()
	level_changed.emit(level, experience, experience_to_next_level())
	experience_changed.emit(experience, experience_to_next_level())


## Recomputes base stats and raises the health pool when a level is gained.
func _apply_level_stats() -> void:
	if stats == null or config == null:
		return
	stats.configure(config, level)
	if health != null:
		health.set_max_health(int(stats.get_stat(Stats.MAX_HEALTH)), true)
	if sword_hitbox != null:
		sword_hitbox.damage = int(stats.get_stat(Stats.ATTACK))


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_health_damaged(amount: int, _remaining: int) -> void:
	_flash_damage()
	damaged.emit(amount)
	if sfx != null:
		sfx.play_hurt()


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
	if sfx != null:
		sfx.play_death()
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


## Every swing in a chain gets its own voice, so a fast three-hit combo is not
## silent after the first press.
func _on_combo_hit_started(_index: int) -> void:
	if sfx != null:
		sfx.play_attack()


func _on_combo_ended() -> void:
	_is_moving = false
	_manual_animation = "idle"
	if sword_hitbox != null:
		sword_hitbox.deactivate()
