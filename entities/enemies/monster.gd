extends CharacterBody2D
class_name Monster
## A data-driven enemy. [MonsterData] supplies the stats, AI tuning and the skill
## list; this script only runs the loop: acquire a target, chase, pick a skill that
## passes its gates, cast it, and resolve the payload at the hit window.
##
## Any rank can equip any skill. Summoned monsters are ordinary Monster scenes, so
## a buffed General is just a General scene plus [StatBuff]s.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died
## Emitted when the monster starts casting a skill. Useful for debug overlays.
signal skill_cast(skill: MonsterSkill, animation: StringName)

@export var config: EnemyData
## Rarity chosen by the area spawn table. -1 uses the data resource's own rarity.
@export var spawn_rarity: int = -1
@export var attack_cooldown: float = 1.0
## Distance at which the monster considers the player in attack range.
@export var attack_range: float = 135.0
## Minimum distance to maintain from the player (prevents crowding/overlapping).
@export var min_attack_space: float = 85.0
## Preferred spacing from the target when moving to attack.
@export var attack_space: float = 110.0
## Maximum depth (feet y) difference to consider in attack range.
@export var attack_depth_tolerance: float = 30.0
## Distance at which the monster notices the player (matches the Attack Radius area).
@export var aggro_radius: float = 325.0
## Once the monster reaches attack range, keep chasing even when the player leaves
## aggro_radius. Disable to leash the monster at its notice radius.
@export var chase_after_engage := true
## Root-to-feet offset used as the monster's depth anchor.
@export var depth_foot_offset: float = 80.0
## How quickly a hit's knockback impulse bleeds off (px/s per second).
@export var knockback_decay: float = 1200.0
## Time the corpse fades before the monster is removed from the scene.
@export var death_fade_seconds: float = 0.35
## Presentation tint restored after damage flashes and used as the base for buffs.
@export var base_tint := Color.WHITE
## Seed used for loot and gold rolls. 0 randomises; any other value makes the
## roll reproducible (tests, QA bug reports, seeded encounters).
@export var loot_seed: int = 0
## Print every loot roll in debug builds and keep the lines in `loot_log`.
@export var log_loot := true

@export_group("Attack")
## Fraction of the attack clip where the default hitbox is live.
@export_range(0.0, 1.0) var attack_hit_start := 0.35
@export_range(0.0, 1.0) var attack_hit_end := 0.65
## Hitbox offset from the monster origin, mirrored with facing.
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
## Movement multiplier from a slow pulse. 1.0 is normal speed.
var _slow_factor := 1.0
var _slow_left := 0.0
## Seconds left face-down after a ground slam. AI and movement pause while > 0.
var _knockdown_left := 0.0
## +1 facing right, -1 facing left.
var facing_sign := 1.0
## True for monsters created by a SummonSkill; they award no experience.
var summoned := false
var summoner: Node2D = null

var max_health: int:
	get: return health.max_health if health != null else 0
var current_health: int:
	get: return health.current_health if health != null else 0

var _is_dead := false
## Human-readable lines from the most recent loot roll, kept for QA and tests.
var loot_log: Array[String] = []
var _flash_tween: Tween
var _legacy_skill: MeleeSkill
var _casting_skill: MonsterSkill = null
var _casting_animation: StringName = &""
var _cast_effect_done := false
var _global_cooldown_left := 0.0
## skill resource -> seconds remaining
var _skill_cooldowns: Dictionary = {}
## skill resource -> lifetime casts
var _skill_casts: Dictionary = {}
## SummonSkill -> Array[Node] of summons owned by that skill
var _summons: Dictionary = {}
## buff source id -> Array[Dictionary] { "buff": StatBuff, "left": float }
var _buff_entries: Dictionary = {}
## AuraPassive -> { target instance id: Monster }
var _aura_targets: Dictionary = {}
var _aura_timers: Dictionary = {}
var _active_tint := Color.WHITE
var _warned: Dictionary = {}
## Duplicated at runtime so per-cast geometry changes do not leak between instances.
var _attack_shape: RectangleShape2D
var _default_hitbox_size := Vector2(176.0, 154.0)
var _default_depth_tolerance := 40.0
## SummonSkill -> spawns waiting on their telegraph, counted against max_alive.
var _pending_summons: Dictionary = {}
## GroundTargetSkill capture: target reference, impact point and whether it is valid.
var _cast_target: Node2D
var _cast_target_position := Vector2.ZERO
var _has_cast_target_position := false
## True after the monster first reaches attack range; keeps it chasing afterwards.
var _engaged := false
## Visible telegraph for a GroundTargetSkill, cleared when the cast resolves.
var _cast_marker: GroundTargetMarker


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if config == null:
		push_error("%s has no MonsterData" % name)
	_apply_config()
	_ensure_name_label()
	_ensure_stats()
	_ensure_health()
	_ensure_sfx()
	_prepare_hitbox()
	_build_legacy_skill()
	_validate_data()

	attack_radius.body_entered.connect(_on_attack_radius_body_entered)
	attack_radius.body_exited.connect(_on_attack_radius_body_exited)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	var rarity_tint := EnemyData.rarity_tint(effective_rarity())
	if rarity_tint != Color.WHITE:
		base_tint *= rarity_tint
	_active_tint = base_tint
	animated_sprite.modulate = _active_tint


func _apply_config() -> void:
	var data := config as MonsterData
	if data == null:
		return
	attack_cooldown = data.attack_cooldown
	attack_range = data.attack_range
	min_attack_space = data.min_attack_space
	attack_space = data.attack_space
	attack_depth_tolerance = data.depth_tolerance
	aggro_radius = data.aggro_radius
	chase_after_engage = data.chase_after_engage


func _ensure_name_label() -> void:
	var label := get_node_or_null("NameLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "NameLabel"
		add_child(label)

	var bar := get_node_or_null("HealthBar") as Node2D
	var bar_top := bar.position.y if bar != null else -120.0
	label.position = Vector2(-90.0, bar_top - 34.0)
	label.size = Vector2(180.0, 28.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 2
	label.text = config.enemy_name if config != null else name
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", EnemyData.rarity_tint(effective_rarity()))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)


func _ensure_stats() -> void:
	stats = get_node_or_null("Stats") as Stats
	if stats == null:
		stats = Stats.new()
		stats.name = "Stats"
		add_child(stats)
	if config != null:
		stats.configure(config, config.level)
		_apply_rarity_modifiers()
		attack_damage = int(stats.get_stat(Stats.ATTACK))
		move_speed = stats.get_stat(Stats.MOVE_SPEED)


## Spawn rarity scales the combat stat block through the shared Stats pipeline.
func _apply_rarity_modifiers() -> void:
	var multiplier := EnemyData.rarity_multiplier(effective_rarity())
	if is_equal_approx(multiplier, 1.0):
		return
	var pct := multiplier - 1.0
	stats.add_modifier(&"spawn_rarity", Stats.MAX_HEALTH, 0.0, pct)
	stats.add_modifier(&"spawn_rarity", Stats.ATTACK, 0.0, pct)
	stats.add_modifier(&"spawn_rarity", Stats.DEFENCE, 0.0, pct)


## -1 follows the data resource; spawn tables pass an explicit rarity.
func effective_rarity() -> int:
	if spawn_rarity >= 0:
		return spawn_rarity
	return config.rarity if config != null else EnemyData.Rarity.NORMAL


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
	# A monster with no voice set is intentionally silent; do not warn about every
	# swing. A configured set still reports its own missing slots.
	sfx.muted = config == null or config.sfx == null


func _prepare_hitbox() -> void:
	attack_hitbox.damage = attack_damage
	attack_hitbox.target_group = "player"
	attack_hitbox.attacker = self
	var shape_node := attack_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		_attack_shape = (shape_node.shape as RectangleShape2D).duplicate() as RectangleShape2D
		shape_node.shape = _attack_shape
		_default_hitbox_size = _attack_shape.size
	_default_depth_tolerance = attack_hitbox.depth_tolerance
	_reset_hitbox_geometry()
	attack_hitbox.deactivate()
	_update_hitbox_position()


## Fallback used when a monster has no configured basic attack. Keeps older
## EnemyData-only scenes and direct `attack_player()` callers working.
func _build_legacy_skill() -> void:
	_legacy_skill = MeleeSkill.new()
	_legacy_skill.id = &"basic"
	_legacy_skill.animation = &"attack"
	_legacy_skill.hit_start = attack_hit_start
	_legacy_skill.hit_end = attack_hit_end
	_legacy_skill.damage_multiplier = 1.0


func _validate_data() -> void:
	var data := config as MonsterData
	if data == null:
		return
	if data.basic_attack == null:
		push_warning("%s has no basic_attack; using the legacy attack" % name)
	for skill in data.all_skills():
		if skill == null:
			push_warning("%s has a null skill in its data" % name)
			continue
		var animation := _resolve_animation(skill)
		if animation == &"":
			_warn_once(&"anim:%d" % skill.get_instance_id(), "%s skill '%s' has no usable animation" % [name, skill.id])
		var problem := skill.validate()
		if problem != "":
			_warn_once(&"skill:%d" % skill.get_instance_id(), "%s skill '%s': %s" % [name, skill.id, problem])
	for passive in data.passives:
		if passive == null:
			continue
		var problem := passive.validate()
		if problem != "":
			_warn_once(&"passive:%d" % passive.get_instance_id(), "%s passive '%s': %s" % [name, passive.id, problem])


func _warn_once(key: StringName, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


func _physics_process(delta: float) -> void:
	if config == null or _is_dead:
		return

	_tick_timers(delta)

	if _knockdown_left > 0.0:
		velocity = knockback_velocity
		_move_with_knockback(delta)
		_apply_depth()
		return

	if is_attacking:
		_update_cast_hit()
		_update_cast_marker()
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
		if chase_after_engage and dist_x <= attack_range:
			_engaged = true

		if in_depth and in_attack_range:
			velocity = knockback_velocity
			_play_idle_animation()
			if attack_timer <= 0.0:
				_try_attack(target)
		elif in_depth and dist_x < min_attack_space:
			# Too close to the player: back up to maintain attack space
			var back_dir := -facing_sign
			velocity = Vector2(back_dir * move_speed * 0.6 * _slow_factor, 0.0) + knockback_velocity
			_play_move_animation()
		else:
			# Navigate towards the attack space point in front of the target
			var target_x := target.global_position.x - facing_sign * attack_space
			var move_dx := target_x - global_position.x
			var direction := Vector2(move_dx, delta_y).normalized()
			velocity = direction * move_speed * _slow_factor + knockback_velocity
			_play_move_animation()
	else:
		velocity = knockback_velocity
		_play_idle_animation()

	_move_with_knockback(delta)
	_apply_depth()


func _tick_timers(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer = maxf(0.0, attack_timer - delta)
	if _global_cooldown_left > 0.0:
		_global_cooldown_left = maxf(0.0, _global_cooldown_left - delta)

	for skill in _skill_cooldowns.keys():
		_skill_cooldowns[skill] = maxf(0.0, float(_skill_cooldowns[skill]) - delta)

	if _slow_left > 0.0:
		_slow_left = maxf(0.0, _slow_left - delta)
		if _slow_left <= 0.0:
			_slow_factor = 1.0
	if _knockdown_left > 0.0:
		_knockdown_left = maxf(0.0, _knockdown_left - delta)

	_tick_buffs(delta)
	_tick_passives(delta)


func _try_attack(target: Node2D) -> void:
	var special := _pick_special(target)
	if special != null:
		_cast_skill(special, false, target)
		return
	var basic := _basic_skill()
	if basic != null:
		_cast_skill(basic, true, target)


## Returns the highest-priority eligible special skill, breaking ties by weight.
## Basic attacks are handled separately so they never starve specials.
func _pick_special(target: Node2D) -> MonsterSkill:
	var data := config as MonsterData
	if data == null or data.skills.is_empty() or _global_cooldown_left > 0.0:
		return null

	var health_ratio := float(current_health) / float(maxi(1, max_health))
	var distance := _ground_distance_to(target)
	var candidates: Array[MonsterSkill] = []
	var best_priority := -2147483648

	for skill in data.skills:
		if skill == null:
			continue
		var cooldown_left := float(_skill_cooldowns.get(skill, 0.0))
		var casts := int(_skill_casts.get(skill, 0))
		if not skill.is_available(cooldown_left, casts, health_ratio, distance):
			continue
		if skill is SummonSkill and not _summon_has_room(skill as SummonSkill):
			continue
		if skill.priority > best_priority:
			best_priority = skill.priority
			candidates.clear()
			candidates.append(skill)
		elif skill.priority == best_priority:
			candidates.append(skill)

	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	var total_weight := 0.0
	for skill in candidates:
		total_weight += maxf(0.0, skill.weight)
	if total_weight <= 0.0:
		return candidates[0]
	var roll := randf() * total_weight
	for skill in candidates:
		roll -= maxf(0.0, skill.weight)
		if roll <= 0.0:
			return skill
	return candidates[-1]


func _basic_skill() -> MonsterSkill:
	var data := config as MonsterData
	if data != null and data.basic_attack != null:
		return data.basic_attack
	return _legacy_skill


## Kept for existing callers and tests: always performs the basic attack.
func attack_player() -> void:
	if not is_instance_valid(player_in_range):
		player_in_range = null
		return
	var basic := _basic_skill()
	if basic == null:
		return
	_cast_skill(basic, true, player_in_range)


func _cast_skill(skill: MonsterSkill, is_basic := false, target: Node2D = null) -> void:
	var animation := _resolve_animation(skill)
	if animation == &"":
		_warn_once(&"missing:%d" % skill.get_instance_id(), "%s cannot cast '%s': no animation" % [name, skill.id])
		return

	_casting_skill = skill
	_casting_animation = animation
	_cast_effect_done = false
	is_attacking = true
	attack_timer = attack_cooldown
	_cast_target = target
	_has_cast_target_position = false
	_clear_cast_marker()
	if skill is GroundTargetSkill:
		var ground := skill as GroundTargetSkill
		if ground.lock_at_cast:
			_capture_ground_target(target)
		_start_cast_marker(ground)
	animated_sprite.speed_scale = maxf(0.05, _cast_animation_speed(skill))
	_reset_hitbox_geometry()
	if skill is MeleeSkill:
		_prepare_melee(skill as MeleeSkill)

	if not is_basic:
		_global_cooldown_left = _global_cooldown()
		_skill_casts[skill] = int(_skill_casts.get(skill, 0)) + 1
		var reduction := 0.0
		if stats != null:
			reduction = stats.get_stat(Stats.COOLDOWN_REDUCTION)
		_skill_cooldowns[skill] = skill.effective_cooldown(reduction)

	animated_sprite.play(animation)
	if sfx != null:
		sfx.idle_enabled = false
		sfx.play_animation(animation)
	skill_cast.emit(skill, animation)


func _global_cooldown() -> float:
	var data := config as MonsterData
	return data.global_cooldown if data != null else 0.0


func _resolve_animation(skill: MonsterSkill) -> StringName:
	var override := _animation_override(skill)
	if override != null and override.animation != &"" and _has_animation(override.animation):
		return override.animation
	if _has_animation(skill.animation):
		return skill.animation
	if _has_animation(&"attack"):
		return &"attack"
	return &""


## Playback speed for a cast, including a per-monster override when one is set.
func _cast_animation_speed(skill: MonsterSkill) -> float:
	var override := _animation_override(skill)
	if override != null and override.animation_speed > 0.0:
		return override.animation_speed
	return skill.animation_speed


func _animation_override(skill: MonsterSkill) -> SkillAnimationOverride:
	var data := config as MonsterData
	if data == null:
		return null
	return data.animation_override_for(skill)


func _has_animation(animation: StringName) -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	if animation == &"":
		return false
	return animated_sprite.sprite_frames.has_animation(animation)


## Enables the damage area only while the cast is between hit_start and hit_end.
func _update_cast_hit() -> void:
	if _casting_skill == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.animation != _casting_animation:
		return

	var frame_count := animated_sprite.sprite_frames.get_frame_count(_casting_animation)
	var progress := float(animated_sprite.frame) / float(maxi(frame_count - 1, 1))

	if not _cast_effect_done and progress >= _casting_skill.hit_start:
		_cast_effect_done = true
		_execute_effect(_casting_skill)

	if _casting_skill is MeleeSkill:
		var should_hit := progress >= _casting_skill.hit_start and progress <= _casting_skill.hit_end
		if should_hit:
			if not attack_hitbox.is_active():
				attack_hitbox.activate()
		elif attack_hitbox.is_active():
			attack_hitbox.deactivate()


func _execute_effect(skill: MonsterSkill) -> void:
	if skill is BuffSkill:
		_apply_skill_buffs(skill as BuffSkill)
	elif skill is SummonSkill:
		_summon(skill as SummonSkill)
	elif skill is AoESkill:
		_execute_aoe(skill as AoESkill)
	elif skill is GroundTargetSkill:
		_finish_cast_marker()
		_execute_ground_target(skill as GroundTargetSkill)


## Radial burst centred on the caster's feet at the moment the effect resolves.
func _execute_aoe(skill: AoESkill) -> void:
	var center := Vector2(
		global_position.x + skill.offset.x * facing_sign,
		get_feet_y() + skill.offset.y
	)
	_spawn_area_hitbox(center, skill)


## Radial hit on the position captured for a ground-targeted skill. When the
## skill does not lock at cast, the target is re-sampled at impact time.
func _execute_ground_target(skill: GroundTargetSkill) -> void:
	var target := _cast_target
	var center := _cast_target_position
	var has_center := _has_cast_target_position

	if not skill.lock_at_cast or not has_center:
		if not is_instance_valid(target):
			target = _get_target_player()
		if is_instance_valid(target):
			center = _impact_point_of(target)
			has_center = true
	if not has_center:
		center = Vector2(global_position.x, get_feet_y())
	_spawn_area_hitbox(center, skill)


## World-space feet point used as an impact centre. Keeps x at the target's body
## and y at its depth anchor so circular hitboxes line up with the depth check.
func _impact_point_of(target: Node2D) -> Vector2:
	if not is_instance_valid(target):
		return Vector2(global_position.x, get_feet_y())
	return Vector2(target.global_position.x, DepthSort.get_feet_y(target))


func _capture_ground_target(target: Node2D) -> void:
	_cast_target = target
	if is_instance_valid(target):
		_cast_target_position = _impact_point_of(target)
		_has_cast_target_position = true
	else:
		_has_cast_target_position = false


## Creates the visible ground telegraph at the captured impact point. Tracking
## skills move it every physics frame until the effect resolves.
func _start_cast_marker(skill: GroundTargetSkill) -> void:
	if not skill.show_marker:
		return
	var parent := get_parent()
	if parent == null:
		return
	var center := _cast_target_position
	if not _has_cast_target_position:
		center = _current_ground_target_point()
	var marker := GroundTargetMarker.new()
	marker.radius = skill.radius
	marker.color = skill.marker_color
	parent.add_child(marker)
	marker.global_position = center
	marker.z_index = DepthSort.z_for_y(center.y) - 1
	_cast_marker = marker


func _update_cast_marker() -> void:
	if not is_instance_valid(_cast_marker):
		_cast_marker = null
		return
	var skill := _casting_skill as GroundTargetSkill
	if skill == null or skill.lock_at_cast:
		return
	var target := _cast_target
	if not is_instance_valid(target):
		target = _get_target_player()
		_cast_target = target
	if not is_instance_valid(target):
		return
	var point := _impact_point_of(target)
	_cast_marker.global_position = point
	_cast_marker.z_index = DepthSort.z_for_y(point.y) - 1


func _current_ground_target_point() -> Vector2:
	var target := _cast_target
	if not is_instance_valid(target):
		target = _get_target_player()
	if is_instance_valid(target):
		return _impact_point_of(target)
	return Vector2(global_position.x, get_feet_y())


## Flashes the telegraph at the hit frame. The marker frees itself afterwards.
func _finish_cast_marker() -> void:
	if is_instance_valid(_cast_marker):
		_cast_marker.flash()
	_cast_marker = null


func _clear_cast_marker() -> void:
	if is_instance_valid(_cast_marker):
		_cast_marker.queue_free()
	_cast_marker = null


## Builds a detached, short-lived circular [Hitbox] at `center`. The marker node
## supplies the depth reference; the hitbox itself uses the monster for stats and
## damage attribution.
func _spawn_area_hitbox(center: Vector2, skill: RadialSkill) -> void:
	var parent := get_parent()
	if parent == null:
		return

	var anchor := Node2D.new()
	anchor.name = "SkillImpact"
	parent.add_child(anchor)
	anchor.global_position = center

	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = attack_hitbox.collision_layer
	hitbox.collision_mask = attack_hitbox.collision_mask
	hitbox.damage = attack_damage
	hitbox.target_group = "player"
	hitbox.attacker = self
	hitbox.depth_origin = anchor
	hitbox.damage_multiplier = skill.damage_multiplier
	hitbox.knockback_force = skill.knockback
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


func _apply_skill_buffs(skill: BuffSkill) -> void:
	var source := _source_for(skill)
	apply_buffs(skill.buffs, source)
	if skill.heal_fraction > 0.0 and health != null:
		health.heal(roundi(float(health.max_health) * skill.heal_fraction))


func _source_for(skill: MonsterSkill) -> StringName:
	return &"skill:%d:%d" % [get_instance_id(), skill.get_instance_id()]


func _prepare_melee(skill: MeleeSkill) -> void:
	attack_hitbox.damage_multiplier = skill.damage_multiplier
	attack_hitbox.knockback_force = skill.knockback
	attack_hitbox.depth_tolerance = skill.hit_depth_tolerance
	if _attack_shape != null:
		_attack_shape.size = skill.hitbox_size
	attack_hitbox.position = Vector2(absf(skill.hitbox_offset.x) * facing_sign, skill.hitbox_offset.y)


func _reset_hitbox_geometry() -> void:
	attack_hitbox.damage_multiplier = 1.0
	attack_hitbox.knockback_force = 0.0
	attack_hitbox.depth_tolerance = _default_depth_tolerance
	if _attack_shape != null:
		_attack_shape.size = _default_hitbox_size
	attack_hitbox.position = Vector2(absf(attack_hitbox_offset.x) * facing_sign, attack_hitbox_offset.y)


func _summon_has_room(skill: SummonSkill) -> bool:
	if skill.max_alive <= 0:
		return true
	return _living_summons(skill) + _pending_for(skill) < skill.max_alive


func _pending_for(skill: SummonSkill) -> int:
	return int(_pending_summons.get(skill, 0))


func _living_summons(skill: SummonSkill) -> int:
	if not _summons.has(skill):
		return 0
	var living: Array[Node] = []
	for node in _summons[skill]:
		# Check validity before the typed call: a freed node no longer satisfies
		# the `Node` parameter type, so passing it would raise a type error.
		if is_instance_valid(node) and _is_living_summon(node):
			living.append(node)
	_summons[skill] = living
	return living.size()


func _is_living_summon(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node.has_method("is_dead") and node.call("is_dead"):
		return false
	return true


func _summon(skill: SummonSkill) -> void:
	if skill.summon_scene == null:
		_warn_once(&"summon:%d" % skill.get_instance_id(), "%s summon '%s' has no scene" % [name, skill.id])
		return

	var live := _living_summons(skill) + _pending_for(skill)
	var allowed := skill.count
	if skill.max_alive > 0:
		allowed = mini(allowed, skill.max_alive - live)
	if allowed <= 0:
		return

	for index in allowed:
		var spawn_position := _summon_position(skill, index, allowed)
		if skill.spawn_telegraph > 0.0:
			_telegraph_summon(skill, spawn_position)
		else:
			_spawn_summon(skill, spawn_position)


func _summon_position(skill: SummonSkill, index: int, total: int) -> Vector2:
	var angle := (TAU * float(index) / float(maxi(1, total))) + randf_range(-0.35, 0.35)
	var offset := Vector2(cos(angle), sin(angle) * 0.45) * skill.spawn_radius
	return global_position + offset


func _telegraph_summon(skill: SummonSkill, spawn_position: Vector2) -> void:
	_pending_summons[skill] = _pending_for(skill) + 1
	var telegraph := SpawnTelegraph.new()
	telegraph.name = "SpawnTelegraph"
	var parent := get_parent()
	if parent == null:
		_pending_summons[skill] = maxi(0, _pending_for(skill) - 1)
		telegraph.queue_free()
		return
	parent.add_child(telegraph)
	telegraph.global_position = spawn_position
	telegraph.z_index = DepthSort.z_for_y(spawn_position.y) - 1
	telegraph.setup(34.0, skill.spawn_telegraph)
	telegraph.finished.connect(func() -> void:
		_pending_summons[skill] = maxi(0, _pending_for(skill) - 1)
		if is_instance_valid(self) and not _is_dead:
			_spawn_summon(skill, spawn_position)
	)


func _spawn_summon(skill: SummonSkill, spawn_position: Vector2) -> void:
	if skill.summon_scene == null or _is_dead:
		return
	var node := skill.summon_scene.instantiate()
	if node == null:
		return
	var parent := get_parent()
	if parent == null:
		node.queue_free()
		return
	parent.add_child(node)
	if node is Node2D:
		(node as Node2D).global_position = spawn_position
	if node is Monster:
		var monster := node as Monster
		monster.mark_summoned(self)
		if not skill.buffs.is_empty():
			monster.apply_buffs(skill.buffs, &"summon")
	else:
		_warn_once(&"summonscene:%d" % skill.get_instance_id(), "%s summon scene is not a Monster" % name)

	if not _summons.has(skill):
		_summons[skill] = []
	_summons[skill].append(node)


func _force_summon(skill: SummonSkill, spawn_position: Vector2) -> void:
	## Test/debug hook: bypass the telegraph but keep the cap and buff logic.
	_spawn_summon(skill, spawn_position)


## Marks this monster as a summon so it awards no experience and follows its
## summoner's lifetime.
func mark_summoned(owner_node: Node2D) -> void:
	summoned = true
	summoner = owner_node


func is_summoned() -> bool:
	return summoned


func apply_buffs(buffs: Array[StatBuff], source_id: StringName) -> void:
	remove_buff_source(source_id)
	var entries: Array[Dictionary] = []
	for buff in buffs:
		if buff == null:
			continue
		if stats != null:
			stats.add_modifier(source_id, buff.stat, buff.flat, buff.pct)
		entries.append({
			"buff": buff,
			"left": buff.seconds if buff.seconds > 0.0 else 0.0,
			"permanent": buff.seconds <= 0.0,
		})
	if entries.is_empty():
		return
	_buff_entries[source_id] = entries
	_refresh_buff_visuals()
	_sync_health_to_stats()


func remove_buff_source(source_id: StringName) -> void:
	if not _buff_entries.has(source_id):
		return
	_buff_entries.erase(source_id)
	if stats != null:
		stats.remove_modifier(source_id)
	_refresh_buff_visuals()
	_sync_health_to_stats()


func _tick_buffs(delta: float) -> void:
	if _buff_entries.is_empty():
		return
	var expired: Array[StringName] = []
	for source in _buff_entries.keys():
		var entries: Array = _buff_entries[source]
		var still_running: Array[Dictionary] = []
		for entry in entries:
			if bool(entry["permanent"]):
				still_running.append(entry)
				continue
			entry["left"] = float(entry["left"]) - delta
			if float(entry["left"]) > 0.0:
				still_running.append(entry)
		if still_running.is_empty():
			expired.append(source)
		else:
			_buff_entries[source] = still_running
	for source in expired:
		remove_buff_source(source)


func _refresh_buff_visuals() -> void:
	var tint := base_tint
	for entries in _buff_entries.values():
		for entry in entries:
			var buff := entry["buff"] as StatBuff
			if buff != null and buff.tint != Color.WHITE:
				tint = buff.tint
	_active_tint = tint
	if animated_sprite != null and (_flash_tween == null or not _flash_tween.is_valid()):
		animated_sprite.modulate = _active_tint


func _sync_health_to_stats() -> void:
	if health == null or stats == null:
		return
	var desired := int(stats.get_stat(Stats.MAX_HEALTH))
	if desired != health.max_health:
		health.set_max_health(desired, true)


func _tick_passives(delta: float) -> void:
	var data := config as MonsterData
	if data == null or data.passives.is_empty() or get_tree() == null:
		return
	for passive in data.passives:
		if passive is AuraPassive:
			_tick_aura(passive as AuraPassive, delta)


func _tick_aura(passive: AuraPassive, delta: float) -> void:
	if not _aura_timers.has(passive):
		_aura_timers[passive] = 0.0
	_aura_timers[passive] = float(_aura_timers[passive]) - delta
	if float(_aura_timers[passive]) > 0.0:
		return
	_aura_timers[passive] = maxf(0.05, passive.tick_seconds)

	var source := _aura_source(passive)
	var current: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self and not passive.affect_self:
			continue
		if not (node is Monster) or not node.is_inside_tree():
			continue
		var ally := node as Monster
		if ally.is_dead():
			continue
		if _ground_distance_to(ally) > passive.radius:
			continue
		current[ally.get_instance_id()] = ally
		ally.apply_buffs(passive.buffs, source)

	var previous: Dictionary = _aura_targets.get(passive, {})
	for id in previous.keys():
		if current.has(id):
			continue
		var target = previous[id]
		if is_instance_valid(target):
			target.remove_buff_source(source)
	_aura_targets[passive] = current


func _aura_source(passive: AuraPassive) -> StringName:
	return &"aura:%d:%d" % [get_instance_id(), passive.get_instance_id()]


func _clear_auras() -> void:
	for passive in _aura_targets.keys():
		var source := _aura_source(passive as AuraPassive)
		for target in _aura_targets[passive].values():
			if is_instance_valid(target):
				target.remove_buff_source(source)
	_aura_targets.clear()


func _despawn_summons() -> void:
	for skill in _summons.keys():
		if skill is SummonSkill and not (skill as SummonSkill).despawn_with_summoner:
			continue
		for node in _summons[skill]:
			if is_instance_valid(node):
				node.queue_free()
	_summons.clear()
	_pending_summons.clear()


## World-space y coordinate of the monster's feet (depth anchor).
func get_feet_y() -> float:
	return global_position.y + depth_foot_offset * scale.y


## World-space point where this monster's floating damage text starts, just above the
## health bar so the number never covers the creature or its bar.
func damage_number_anchor() -> Vector2:
	var bar := get_node_or_null("HealthBar") as Node2D
	if bar != null:
		return bar.global_position + Vector2(0.0, -24.0)
	return Vector2(global_position.x, get_feet_y() - 120.0)


func _move_with_knockback(delta: float) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	if velocity != Vector2.ZERO:
		move_and_slide()


## Depth index: lower on screen (larger y) renders in front.
func _apply_depth() -> void:
	z_index = DepthSort.z_for_y(get_feet_y())


func _get_target_player() -> Node2D:
	if is_instance_valid(player_in_range):
		if _engaged or _ground_distance_to(player_in_range) <= aggro_radius:
			return player_in_range
		player_in_range = null

	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	if _engaged or _ground_distance_to(player) <= aggro_radius:
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
	# A skill may have moved the hitbox this frame; keep the offset it set.
	if _casting_skill is MeleeSkill and is_attacking:
		var melee := _casting_skill as MeleeSkill
		attack_hitbox.position = Vector2(absf(melee.hitbox_offset.x) * facing_sign, melee.hitbox_offset.y)
		return
	attack_hitbox.position = Vector2(absf(attack_hitbox_offset.x) * facing_sign, attack_hitbox_offset.y)


func _idle_animation() -> StringName:
	var data := config as MonsterData
	var wanted: StringName = data.idle_animation if data != null else &"default"
	return wanted if _has_animation(wanted) else &"default"


func _walk_animation() -> StringName:
	var data := config as MonsterData
	var wanted: StringName = data.walk_animation if data != null else &"walk"
	if _has_animation(wanted):
		return wanted
	return &"default" if _has_animation(&"default") else &"walk"


func _play_move_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
	if sfx != null:
		sfx.idle_enabled = false
	var anim := _walk_animation()
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _play_idle_animation() -> void:
	if animated_sprite.sprite_frames == null:
		return
	if sfx != null:
		sfx.idle_enabled = true
	var anim := _idle_animation()
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _on_attack_radius_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = body
		attack_timer = minf(attack_timer, 0.35)


func _on_attack_radius_body_exited(body: Node2D) -> void:
	if body == player_in_range:
		player_in_range = null


func _on_animation_finished() -> void:
	if _casting_skill == null:
		return
	if animated_sprite.animation != _casting_animation:
		return
	is_attacking = false
	_cast_effect_done = false
	_casting_skill = null
	_casting_animation = &""
	_cast_target = null
	_has_cast_target_position = false
	_clear_cast_marker()
	animated_sprite.speed_scale = 1.0
	attack_hitbox.deactivate()
	_reset_hitbox_geometry()
	_play_idle_animation()
	if sfx != null:
		sfx.idle_enabled = true


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0 or health == null or not health.is_alive() or health.is_invulnerable():
		return
	if stats != null:
		amount = Damage.final_damage(float(amount), stats.get_stat(Stats.DEFENCE))
	if health.take_damage(amount) and not _is_dead and knockback != Vector2.ZERO:
		knockback_velocity += knockback


## Source-aware entry point used by [Hitbox]. The monster does not reflect yet, but
## sharing the signature keeps every damage target interchangeable.
func take_hit(amount: int, knockback: Vector2 = Vector2.ZERO, _source: Node = null) -> void:
	take_damage(amount, knockback)


## Public impact flash so a skill can paint a white hit without reusing the red
## damage flash. Falls back to the active buff tint when it ends.
func flash_impact(color: Color = Color.WHITE, seconds := 0.18) -> void:
	if animated_sprite == null or _is_dead:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	animated_sprite.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(animated_sprite, "modulate", _active_tint, maxf(0.02, seconds))


## Slows movement for a moment. Repeated pulses refresh the timer without stacking.
func apply_slow(factor: float, seconds: float) -> void:
	if _is_dead or seconds <= 0.0:
		return
	_slow_factor = clampf(factor, 0.05, 1.0)
	_slow_left = maxf(_slow_left, seconds)


## Generals and Guardians shrug off knockdowns. Normal mobs are the "small
## enemies" a ground slam sends to the floor.
func can_be_knocked_down() -> bool:
	var data := config as MonsterData
	if data == null:
		return true
	return data.rank == MonsterData.Rank.NORMAL and not data.knockdown_immune


## Interrupts the current cast and drops the monster for `seconds`, with a short
## tilt so the state reads on screen. The AI resumes automatically.
func knock_down(seconds: float) -> void:
	if _is_dead or seconds <= 0.0 or not can_be_knocked_down():
		return
	_knockdown_left = maxf(_knockdown_left, seconds)
	is_attacking = false
	_casting_skill = null
	_casting_animation = &""
	_cast_effect_done = false
	_clear_cast_marker()
	attack_hitbox.deactivate()
	_reset_hitbox_geometry()
	knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	if animated_sprite != null:
		animated_sprite.speed_scale = 1.0
	_play_idle_animation()
	if animated_sprite != null:
		var tween := create_tween()
		tween.tween_property(animated_sprite, "rotation", -0.22, 0.12)
		tween.tween_interval(maxf(0.05, seconds - 0.18))
		tween.tween_property(animated_sprite, "rotation", 0.0, 0.15)


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
	node.global_position = damage_number_anchor()
	# Sit just in front of this monster but still behind anyone nearer the camera.
	node.z_index = DepthSort.z_for_y(get_feet_y()) + 1
	node.setup(amount, color)


func _on_health_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	is_attacking = false
	_casting_skill = null
	_engaged = false
	_clear_cast_marker()
	knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	attack_hitbox.deactivate()
	attack_radius.set_deferred("monitoring", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_physics_process(false)
	_clear_auras()
	_despawn_summons()
	_award_experience()
	_drop_loot()
	if sfx != null:
		sfx.play_death()
	died.emit()
	_play_death_fade()


## Rolls this monster's loot table and spawns the results as walk-over pickups
## around its feet. Summons never drop loot so a summoner cannot be farmed
## indirectly.
func _drop_loot() -> void:
	if summoned or config == null:
		return
	var roller := _make_loot_roller(loot_seed)
	roller.source_name = config.enemy_name
	roller.verbose = log_loot
	var drops := roller.roll(config.loot_table, effective_rarity())
	loot_log = roller.log_lines
	if drops.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return
	var feet := Vector2(global_position.x, get_feet_y())
	LootSpawner.spawn_drops(parent, feet, drops, roller.rng)


## Rolls the loot table without spawning anything. `seed_value` <= 0 falls back
## to [member loot_seed]; a positive value reproduces that exact roll.
func roll_loot(seed_value: int = -1) -> Array[Dictionary]:
	if config == null:
		return []
	var roller := _make_loot_roller(seed_value)
	roller.source_name = config.enemy_name
	roller.verbose = log_loot
	var drops := roller.roll(config.loot_table, effective_rarity())
	loot_log = roller.log_lines.duplicate()
	return drops


func _make_loot_roller(seed_value: int) -> LootRoller:
	var effective := seed_value
	if effective <= 0:
		effective = loot_seed
	return LootRoller.new(effective if effective > 0 else -1)


## Grants EnemyData.xp_reward to the player when this monster dies. Summons are
## worth nothing so a summoner cannot be farmed.
func _award_experience() -> void:
	if summoned or config == null or config.xp_reward <= 0 or get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_experience"):
		var reward := int(round(config.xp_reward * EnemyData.rarity_multiplier(effective_rarity())))
		player.add_experience(maxi(1, reward))


func _flash_damage() -> void:
	if _is_dead:
		return
	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(animated_sprite, "modulate", _active_tint, 0.18)


## Fades the whole corpse (sprite and health bar) and removes it from the scene.
func _play_death_fade() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), death_fade_seconds)
	tween.tween_callback(queue_free)
