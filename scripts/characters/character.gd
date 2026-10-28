class_name Character
extends Node2D
## A rigged side-view character. Builds its skeleton and clips from a CharacterConfig and
## exposes a small API (move, attack, facing) for whatever controls it. Later systems such
## as status and inventory should be added here as their own components.

signal facing_changed(facing_right: bool)

## Horizontal center of the rig in source-art pixels. The skeleton is shifted by this so the
## body center sits on the Character origin; facing flips mirror `scale.x`, so without it
## the whole body jumps sideways by twice this offset every time the character turns.
const RIG_CENTER_X := 31.0
## Distance from the Character origin down to the soles, in rig units (scale 1).
const FEET_OFFSET_LOCAL := 141.7

## Ground shadow drawn behind the rig, in rig units (scale 1).
const SHADOW_RADIUS := 18.0
const SHADOW_FLATTEN := 0.35
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.3)

@export var config: CharacterConfig

var rig: CharacterRig
var animations: WarriorSideAnimations
var combo: AttackCombo
var walk_speed := 230.0
var run_speed := 360
var facing_right := true
## On-screen size of the rig. Defaults to config.base_scale; areas shrink or grow it
## with depth. Move speed follows it so the feet don't slide.
var render_scale := 3.0
## How fast the character moves up/down through the scene, relative to its run speed.
var depth_speed_ratio := 0.6

var _manual_animation := "idle"
var _is_moving := false

@onready var skeleton: Skeleton2D = $Skeleton2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if config == null:
		push_error("%s has no CharacterConfig" % name)
		return
	rig = CharacterRig.new(config, skeleton)
	rig.build()
	animations = WarriorSideAnimations.new(rig)
	walk_speed = animations.compute_walk_speed()
	run_speed = animations.compute_run_speed()
	anim_player.add_animation_library("", animations.build_library(config.attacks))
	combo = AttackCombo.new(anim_player, config)
	combo.combo_ended.connect(_on_combo_ended)
	render_scale = config.base_scale
	_apply_scale()
	anim_player.play("idle")


func is_attacking() -> bool:
	return combo != null and combo.is_attacking()


## Runs the character by direction (-1, 0, 1); idle when 0. Ignored mid-attack.
func move(direction: int, delta: float) -> void:
	move_2d(Vector2(direction, 0), delta)


## Runs left/right (x) and up/down through the scene's depth (y); idle when zero.
## Ignored mid-attack.
func move_2d(direction: Vector2, delta: float) -> void:
	if is_attacking():
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
	if combo != null:
		combo.press()


## Plays a looping clip ("idle", "walk" or "run") in place. Ignored mid-attack.
func play_manual(anim_name: String) -> void:
	if is_attacking():
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


func _draw() -> void:
	draw_set_transform(Vector2(0.0, FEET_OFFSET_LOCAL), 0.0, Vector2(1.0, SHADOW_FLATTEN))
	draw_circle(Vector2.ZERO, SHADOW_RADIUS, SHADOW_COLOR, true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func toggle_facing() -> void:
	set_facing(not facing_right)


func _on_combo_ended() -> void:
	_is_moving = false
	_manual_animation = "idle"
