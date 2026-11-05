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
signal energy_changed(current: float, maximum: float)
## Fires when a skill actually starts, after cost and cooldown checks.
signal skill_started(skill: PlayerSkill)
## Fires after the primary-skill order changes, so HUD buttons can rebind.
signal skill_loadout_changed

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
## How quickly player knockback bleeds off, in px/s per second.
const KNOCKBACK_DECAY := 1400.0
## Rig units the floating damage text sits above the head bone.
const DAMAGE_TEXT_LIFT := 28.0
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
## Energy pool for skills. Refills from CharacterData.energy_regen.
var energy := 0.0
var max_energy := 100.0
## Placeholder until the evolution system lands; Iron Will reads it for its tiers.
var evolution_tier := 1
## Impulse from enemy hits. Decays every frame in move_2d().
var knockback_velocity := Vector2.ZERO
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
## Skill id -> seconds left before the slot is ready again.
var _cooldowns: Dictionary = {}
## The skill currently playing, or null when the character is free.
var _active_skill: PlayerSkill
## Guards the one-shot effect so a clip that outlives its hit window cannot double-cast.
var _active_skill_effect_done := false
## Buff source id -> Array[Dictionary] { "buff": StatBuff, "left": float }.
var _buff_entries: Dictionary = {}
## Defensive effect source id -> { "damage_scale", "knockback_immune", "reflect", "left" }.
var _effect_entries: Dictionary = {}
## Presentation tint restored after damage flashes; buffs can change it.
var _active_tint := Color.WHITE
## Ground covered since the last footstep, in world pixels.
var _step_distance := 0.0
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
	anim_player.add_animation_library("", animations.build_library(config.attacks, config.skills))
	anim_player.animation_finished.connect(_on_animation_finished)
	combo = AttackCombo.new(anim_player, config)
	combo.combo_ended.connect(_on_combo_ended)
	if sfx != null:
		combo.hit_started.connect(_on_combo_hit_started)
	render_scale = config.base_scale
	evolution_tier = maxi(1, config.evolution_tier)
	max_energy = float(maxi(1, config.max_energy))
	energy = max_energy
	_build_sword_hitbox()
	_apply_scale()
	anim_player.play("idle")


func _process(delta: float) -> void:
	_update_sword_hitbox()
	_tick_energy(delta)
	_tick_cooldowns(delta)
	_tick_buffs(delta)
	_tick_effects(delta)
	_update_skill_effect()
	if sfx != null:
		# Vocalize only while genuinely idle, not mid-swing, guard or run.
		sfx.idle_enabled = not _is_dead and not _is_moving and not _is_blocking and not is_busy()


func is_attacking() -> bool:
	return combo != null and combo.is_attacking()


## True while a skill clip is playing.
func is_casting_skill() -> bool:
	return _active_skill != null


## Movement, attacks and skills all share this lock. A skill and a combo are
## mutually exclusive so their clips cannot fight over the AnimationPlayer.
func is_busy() -> bool:
	return is_attacking() or is_casting_skill()


## Runs the character by direction (-1, 0, 1); idle when 0. Ignored mid-attack.
func move(direction: int, delta: float) -> void:
	move_2d(Vector2(direction, 0), delta)


## Runs left/right (x) and up/down through the scene's depth (y); idle when zero.
## Ignored mid-attack. Knockback still moves the body while a swing is locked out.
func move_2d(direction: Vector2, delta: float) -> void:
	if config == null or _is_dead:
		return
	_apply_knockback(delta)
	if is_busy() or _is_blocking:
		return
	if direction != Vector2.ZERO:
		_is_moving = true
		if direction.x != 0.0:
			set_facing(direction.x > 0.0)
		var speed := run_speed * render_scale / config.base_scale
		var step := direction.normalized() * speed * delta
		step.y *= depth_speed_ratio
		position += step
		_advance_footsteps(step.length())
		if anim_player.current_animation != "run":
			anim_player.play("run", 0.08)
	elif _is_moving:
		_is_moving = false
		_manual_animation = "idle"
		anim_player.play("idle")
	elif _manual_animation != "" and anim_player.current_animation != _manual_animation:
		anim_player.play(_manual_animation)


func attack() -> void:
	if _is_blocking or _is_dead or is_casting_skill():
		return
	if combo != null:
		combo.press()


## Raise or lower the guard. While blocking, incoming damage is reduced and
## movement/attacks are ignored. Safe to call every frame while held.
func block(on: bool = true) -> void:
	if _is_dead or is_casting_skill():
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


## Number of active skill slots this character's data provides.
func skill_slots() -> int:
	return config.skills.size() if config != null else 0


## The skill equipped in `slot`, or null when the slot is empty.
func skill_in_slot(slot: int) -> PlayerSkill:
	if config == null or slot < 0 or slot >= config.skills.size():
		return null
	return config.skills[slot]


## Looks a skill up by id. Used by input bindings and HUD overlays.
func skill_by_id(id: StringName) -> PlayerSkill:
	if config == null:
		return null
	for skill in config.skills:
		if skill != null and skill.id == id:
			return skill
	return null


## Moves an owned skill into a primary slot (0-2) by reordering the loadout.
## The first slots feed the HUD buttons and number keys, so swapping a skill in
## pushes the previous occupant down the list rather than losing it.
func equip_skill_at(skill: PlayerSkill, slot: int) -> bool:
	if config == null or skill == null:
		return false
	var from := config.skills.find(skill)
	if from < 0:
		return false
	var target := clampi(slot, 0, config.skills.size() - 1)
	if from == target:
		return true
	config.skills.remove_at(from)
	config.skills.insert(target, skill)
	skill_loadout_changed.emit()
	return true


## Casts the skill equipped in `slot`. Returns false when the slot is empty or the
## cast was rejected, so UI and tests can tell the difference from a silent no-op.
func use_skill(slot: int) -> bool:
	return cast_skill(skill_in_slot(slot))


## True when the skill could start right now: not dead, idle, off cooldown, enough
## energy, unlocked and baked into the animation library.
func can_cast_skill(skill: PlayerSkill) -> bool:
	if skill == null or _is_dead or config == null or _active_skill != null:
		return false
	if level < skill.unlock_level:
		return false
	if cooldown_left(skill) > 0.0 or energy + 0.001 < float(skill.energy_cost):
		return false
	return anim_player != null and anim_player.has_animation(skill.id)


## Starts a skill: spends energy, puts the slot on cooldown and plays the clip.
## The effect itself fires at `hit_start` so wind-ups read before the impact.
func cast_skill(skill: PlayerSkill) -> bool:
	if not can_cast_skill(skill):
		return false

	if _is_blocking:
		block(false)
	if is_attacking() and combo != null:
		combo.cancel()

	energy = maxf(0.0, energy - float(skill.energy_cost))
	energy_changed.emit(energy, max_energy)
	_cooldowns[skill.id] = skill.effective_cooldown(_cooldown_reduction())

	_active_skill = skill
	_active_skill_effect_done = false
	_manual_animation = skill.id
	anim_player.speed_scale = maxf(0.05, skill.animation_speed)
	anim_player.play(skill.id, config.attack_blend)
	skill_started.emit(skill)
	if sfx != null:
		if not skill.cast_sounds.is_empty():
			sfx.play_streams(skill.id, skill.cast_sounds)
		else:
			sfx.play_animation(skill.id)
	return true


## Seconds left before `skill` is ready. 0 when ready or unbound.
func cooldown_left(skill: PlayerSkill) -> float:
	if skill == null:
		return 0.0
	return float(_cooldowns.get(skill.id, 0.0))


## Full cooldown for `skill` after cooldown reduction. Used by the HUD sweep.
func cooldown_total(skill: PlayerSkill) -> float:
	if skill == null:
		return 0.0
	return skill.effective_cooldown(_cooldown_reduction())


## Applies one or more timed stat buffs. A later call with the same source
## replaces the previous buffs, so recasting never stacks the same effect.
func apply_buffs(buffs: Array[StatBuff], source_id: StringName) -> void:
	remove_buff_source(source_id)
	if stats == null:
		return
	for i in buffs.size():
		var buff := buffs[i]
		if buff == null:
			continue
		var entry_source := StringName("%s:%d" % [source_id, i])
		stats.add_modifier(entry_source, buff.stat, buff.flat, buff.pct)
		_buff_entries[entry_source] = {
			"buff": buff,
			"left": buff.seconds if buff.seconds > 0.0 else 0.0,
		}
	_refresh_buff_tint()


## Removes every buff owned by `source_id`, including the per-buff sub-sources.
func remove_buff_source(source_id: StringName) -> void:
	var prefix := String(source_id) + ":"
	for key in _buff_entries.keys():
		if key == source_id or String(key).begins_with(prefix):
			_buff_entries.erase(key)
			if stats != null:
				stats.remove_modifier(key)
	_refresh_buff_tint()


## Plays a looping clip ("idle", "walk" or "run") in place. Ignored mid-attack.
func play_manual(anim_name: String) -> void:
	if is_busy() or _is_dead:
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


## World-space point where this character's floating damage text starts, just
## above the head. Follows the rig so it stays put when the character is scaled.
func damage_number_anchor() -> Vector2:
	if rig != null:
		var head := rig.bones.get("head") as Bone2D
		if head != null:
			return head.global_position + Vector2(0.0, -DAMAGE_TEXT_LIFT * render_scale)
	return global_position


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


## Turns the sword hitbox on only during the active window of the current attack or
## sword skill. A skill can also override the damage multiplier and impact flash.
func _update_sword_hitbox() -> void:
	if sword_hitbox == null or config == null:
		return

	var data := _current_hit_clip()
	var multiplier := 1.0
	var flash_color := Color(0.0, 0.0, 0.0, 0.0)
	var flash_seconds := 0.0
	if _active_skill != null and data == _active_skill:
		multiplier = _active_skill.damage_multiplier
		flash_color = _active_skill.hit_flash_color
		flash_seconds = _active_skill.hit_flash_seconds

	var active := false
	if data != null and anim_player.current_animation == data.id:
		var length := anim_player.current_animation_length
		var t := anim_player.current_animation_position
		active = length > 0.0 and t >= data.hit_start * length and t <= data.hit_end * length

	sword_hitbox.damage_multiplier = multiplier
	sword_hitbox.flash_color = flash_color
	sword_hitbox.flash_seconds = flash_seconds
	if active:
		if not sword_hitbox.is_active():
			sword_hitbox.activate(data.damage if data.damage > 0 else -1)
	elif sword_hitbox.is_active():
		sword_hitbox.deactivate()


## The clip that owns the sword right now: a sword skill takes priority, otherwise
## the combo hit playing. Buff and area skills never drive the blade.
func _current_hit_clip() -> AttackData:
	if _active_skill != null and _active_skill.uses_sword:
		return _active_skill
	return _current_attack_data()


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
## mitigated by this character's defence, then reduced by the guard and any active
## defensive buff. `source` is the attacker, used for reflection and attribution.
func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO, source: Node = null) -> void:
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
	amount = maxi(0, roundi(float(amount) * _damage_taken_scale()))
	if amount > 0 and source != null and _reflect_fraction() > 0.0:
		var reflected := maxi(1, roundi(float(amount) * _reflect_fraction()))
		if source.has_method("take_damage"):
			source.take_damage(reflected)
	if health.take_damage(amount) and knockback != Vector2.ZERO and not _is_knockback_immune():
		knockback_velocity += knockback


## Source-aware entry point used by [Hitbox] so reflection knows who hit us. Kept
## separate from `take_damage` so simple callers and test doubles stay two-arg.
func take_hit(amount: int, knockback: Vector2 = Vector2.ZERO, source: Node = null) -> void:
	take_damage(amount, knockback, source)


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


## Restores a health value carried over from the previous area.
func set_health(value: int) -> void:
	if health != null:
		health.set_current_health(value)


## Restores full health and clears the death visual. Areas call this on respawn.
func revive() -> void:
	if health == null:
		return
	health.reset()
	_is_dead = false
	_is_moving = false
	_is_blocking = false
	_clear_skill_state()
	_cooldowns.clear()
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	if skeleton != null:
		skeleton.modulate = Color.WHITE
	var shadow := get_node_or_null("Shadow") as EntityShadow
	if shadow != null:
		shadow.modulate = Color.WHITE
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
	var sword = load("res://resources/items/weapons/swords/default_sword.tres")
	var buckler = load("res://resources/items/weapons/swords/default_buckler.tres")
	if sword != null:
		inventory.add_item(sword, 1)
	if buckler != null:
		inventory.add_item(buckler, 1)
	var holy = load("res://resources/items/weapons/swords/holy_sword.tres")
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
	if amount > 0:
		_spawn_damage_number(amount, Color(1.0, 0.3, 0.3))
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
	node.global_position = damage_number_anchor()
	# Sit just in front of this character but still behind anyone nearer the camera.
	node.z_index = DepthSort.z_for_y(get_feet_y()) + 1
	node.setup(amount, color)


func _on_health_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_moving = false
	_is_blocking = false
	if combo != null:
		combo.cancel()
	_clear_skill_state()
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
	_flash_tween.tween_property(skeleton, "modulate", _active_tint, 0.18)


func _play_death_fade() -> void:
	if skeleton == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(skeleton, "modulate", Color(1.0, 1.0, 1.0, 0.25), 0.45)
	var shadow := get_node_or_null("Shadow") as EntityShadow
	if shadow != null:
		_death_tween.parallel().tween_property(shadow, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.45)


## Hands the surface over from the scene. Steps stay silent until a set arrives.
func set_footsteps(set: FootstepSet) -> void:
	_step_distance = 0.0
	if sfx != null:
		sfx.footsteps = set


## Plays the next step once the character has covered a stride of ground. Distance
## rather than time keeps the cadence honest at any speed.
func _advance_footsteps(distance: float) -> void:
	if sfx == null or sfx.footsteps == null:
		return
	var stride := maxf(1.0, sfx.footsteps.stride_pixels)
	_step_distance += distance
	if _step_distance < stride:
		return
	_step_distance -= stride
	sfx.play_footstep()


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


## Drops every skill-owned modifier and returns playback to normal. Used by death
## and revive so a buff never survives into the next life.
func _clear_skill_state() -> void:
	_active_skill = null
	_active_skill_effect_done = true
	_effect_entries.clear()
	for key in _buff_entries.keys():
		if stats != null:
			stats.remove_modifier(key)
	_buff_entries.clear()
	_active_tint = Color.WHITE
	if anim_player != null:
		anim_player.speed_scale = 1.0


# ---------------------------------------------------------------------------
# Skill runtime
# ---------------------------------------------------------------------------

## Refills energy. The HUD reads the signal, so it stays smooth without polling.
func _tick_energy(delta: float) -> void:
	if _is_dead or config == null:
		return
	if energy >= max_energy:
		return
	energy = minf(max_energy, energy + maxf(0.0, config.energy_regen) * delta)
	energy_changed.emit(energy, max_energy)


func _tick_cooldowns(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for id in _cooldowns.keys():
		var left := float(_cooldowns[id]) - delta
		if left <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left


## Fires the skill effect once the clip reaches its hit frame. Using the animation
## position instead of a parallel timer keeps the effect in sync with the wind-up,
## even when `animation_speed` slows the clip down.
func _update_skill_effect() -> void:
	var skill := _active_skill
	if skill == null or _active_skill_effect_done:
		return
	if anim_player.current_animation != skill.id:
		return
	var length := anim_player.current_animation_length
	if length <= 0.0 or anim_player.current_animation_position < skill.hit_start * length:
		return
	_resolve_skill_effect()


func _resolve_skill_effect() -> void:
	if _active_skill_effect_done:
		return
	_active_skill_effect_done = true
	var skill := _active_skill
	if skill == null:
		return
	if skill is SelfBuffSkill:
		_apply_self_buff(skill as SelfBuffSkill)
	elif skill is GroundSlamSkill:
		_apply_ground_slam(skill as GroundSlamSkill)


## Clears the skill lock when its clip ends. Also resolves a skipped effect so a
## very short clip can never swallow its own buff.
func _on_animation_finished(anim_name: StringName) -> void:
	if _active_skill == null or anim_name != _active_skill.id:
		return
	if not _active_skill_effect_done:
		_resolve_skill_effect()
	_active_skill = null
	anim_player.speed_scale = 1.0
	_manual_animation = "idle"
	anim_player.play("idle", config.recover_blend if config != null else 0.12)


func _apply_self_buff(skill: SelfBuffSkill) -> void:
	var source := _skill_source(skill)
	apply_buffs(skill.buffs, source)

	var reflect := skill.tier3_reflect_fraction if evolution_tier >= 3 else 0.0
	if not is_equal_approx(skill.damage_taken_multiplier, 1.0) or skill.knockback_immune or reflect > 0.0:
		_effect_entries[source] = {
			"damage_scale": clampf(skill.damage_taken_multiplier, 0.0, 1.0),
			"knockback_immune": skill.knockback_immune,
			"reflect": reflect,
			"left": skill.duration,
		}

	if evolution_tier >= 2 and skill.tier2_heal_fraction > 0.0:
		heal(roundi(float(max_health) * skill.tier2_heal_fraction))
	if skill.slow_radius > 0.0:
		_slow_nearby(skill)
	_spawn_shockwave(_feet_position(), maxf(skill.slow_radius, 140.0), skill.pulse_color, true)


func _apply_ground_slam(skill: GroundSlamSkill) -> void:
	var center := _feet_position()
	_spawn_shockwave(center, skill.radius, skill.pulse_color, false)
	var hitbox := _spawn_area_hitbox(center, skill)
	if hitbox != null and skill.knockdown:
		hitbox.hit_landed.connect(func(target: Node2D) -> void:
			if is_instance_valid(target) and target.has_method("knock_down"):
				target.knock_down(skill.knockdown_seconds))


## Applies the shout's slow to enemies inside the pulse. Depth matters, so a mob
## on another plane is not tagged by a shockwave it visually missed.
func _slow_nearby(skill: SelfBuffSkill) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if not node.has_method("apply_slow"):
			continue
		var enemy := node as Node2D
		if absf(enemy.global_position.x - global_position.x) > skill.slow_radius:
			continue
		if not DepthSort.is_in_depth(self, enemy, 80.0):
			continue
		enemy.apply_slow(skill.slow_factor, skill.slow_seconds)


## Detached circular hitbox centred on the ground. It uses the same collision
## layers as the sword so area damage and melee cannot hit different groups.
func _spawn_area_hitbox(center: Vector2, skill: GroundSlamSkill) -> Hitbox:
	var parent := get_parent()
	if parent == null:
		return null
	var anchor := Node2D.new()
	anchor.name = "SkillImpact"
	parent.add_child(anchor)
	anchor.global_position = center

	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 8  # Player_Attacks
	hitbox.collision_mask = 4  # Enemies
	hitbox.damage = int(stats.get_stat(Stats.ATTACK)) if stats != null else config.attack_damage
	hitbox.damage_multiplier = skill.damage_multiplier
	hitbox.knockback_force = skill.knockback
	hitbox.target_group = "enemies"
	hitbox.attacker = self
	hitbox.depth_origin = anchor
	hitbox.depth_tolerance = skill.hit_depth_tolerance

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = skill.radius
	shape.shape = circle
	hitbox.add_child(shape)
	anchor.add_child(hitbox)
	hitbox.activate()

	var tree := get_tree()
	if tree != null:
		var lifetime := maxf(0.05, skill.active_seconds)
		tree.create_timer(lifetime).timeout.connect(func() -> void:
			if is_instance_valid(hitbox):
				hitbox.deactivate()
			if is_instance_valid(anchor):
				anchor.queue_free()
		)
	return hitbox


func _spawn_shockwave(center: Vector2, radius: float, color: Color, both_sides: bool) -> void:
	if color.a <= 0.0:
		return
	var parent := get_parent()
	if parent == null:
		return
	var wave := Shockwave.new()
	wave.name = "Shockwave"
	wave.radius = radius
	wave.color = color
	wave.both_sides = both_sides
	parent.add_child(wave)
	wave.global_position = center
	wave.z_index = DepthSort.z_for_y(center.y) - 1


func _feet_position() -> Vector2:
	return Vector2(global_position.x, get_feet_y())


func _skill_source(skill: PlayerSkill) -> StringName:
	return StringName("skill:%s" % skill.id)


func _cooldown_reduction() -> float:
	return stats.get_stat(Stats.COOLDOWN_REDUCTION) if stats != null else 0.0


func _damage_taken_scale() -> float:
	var scale := 1.0
	for entry in _effect_entries.values():
		scale *= clampf(float(entry["damage_scale"]), 0.0, 1.0)
	return scale


func _is_knockback_immune() -> bool:
	for entry in _effect_entries.values():
		if bool(entry["knockback_immune"]):
			return true
	return false


func _reflect_fraction() -> float:
	var best := 0.0
	for entry in _effect_entries.values():
		best = maxf(best, float(entry["reflect"]))
	return best


func _tick_effects(delta: float) -> void:
	if _effect_entries.is_empty():
		return
	for source in _effect_entries.keys():
		var entry: Dictionary = _effect_entries[source]
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			_effect_entries.erase(source)


func _tick_buffs(delta: float) -> void:
	if _buff_entries.is_empty():
		return
	for key in _buff_entries.keys():
		var entry: Dictionary = _buff_entries[key]
		var left := float(entry["left"])
		if left <= 0.0:
			continue  # permanent until its source is cleared
		left -= delta
		if left <= 0.0:
			_buff_entries.erase(key)
			if stats != null:
				stats.remove_modifier(key)
		else:
			entry["left"] = left
	_refresh_buff_tint()


## Picks the tint of the last non-white buff, mirroring the monster behaviour so a
## buffed player is readable at a glance. Damage flashes return to this tint.
func _refresh_buff_tint() -> void:
	var tint := Color.WHITE
	for entry in _buff_entries.values():
		var buff := entry["buff"] as StatBuff
		if buff != null and buff.tint != Color.WHITE:
			tint = buff.tint
	_active_tint = tint
	if skeleton != null:
		skeleton.modulate = tint


func _apply_knockback(delta: float) -> void:
	if knockback_velocity == Vector2.ZERO:
		return
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	position += knockback_velocity * delta
