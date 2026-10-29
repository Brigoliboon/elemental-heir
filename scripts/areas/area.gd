class_name Area
extends Node2D
## A side-scrolling play area with depth: a background image scaled to fill the screen,
## a player Character who can run left/right and up/down inside a walkable ground band,
## a camera that follows and zooms with depth, and optional exits at the left and right
## edges that load another area.
## Obstacles: add a StaticBody2D with CollisionShape2D or CollisionPolygon2D children
## anywhere in the area. Draw the shape around the obstacle's footprint on the ground;
## the player's feet can't enter it and slide along its edge.

## Which edge the player should appear at in the next area ("left", "right" or "").
static var _entry_side := ""

const TITLE_SCENE := "res://scenes/title/title_screen.tscn"
## Distance from the Character origin down to its soles, in rig units (scale 1).
const FEET_OFFSET_LOCAL := Character.FEET_OFFSET_LOCAL

@export var area_name := ""
@export var background_texture: Texture2D

@export_group("Walkable ground")
## Top (far) edge of the walkable band, in background-image pixels.
@export var ground_far_px := 560.0
## Bottom (near) edge of the walkable band, in background-image pixels.
@export var ground_near_px := 690.0
## Where the player starts inside the band (0 = far edge, 1 = near edge).
@export_range(0.0, 1.0) var spawn_depth := 0.6
## Spawn x as a fraction of the area width (0 = left edge, 1 = right edge).
@export_range(0.0, 1.0) var spawn_x_ratio := 0.2
## How close (screen px) the player can get to a left/right edge.
@export var edge_margin := 110.0
## Radius (screen px) of the player's feet footprint used against obstacles.
@export var feet_radius := 16.0

@export_group("Depth look")
## Character scale at the far edge and at the near edge of the band.
@export var far_character_scale := 1.5
@export var near_character_scale := 2.0
## Camera zoom when the player is far (zoomed in) and near (zoomed out).
@export var far_zoom := 1.25
@export var near_zoom := 1.0
## How quickly the camera zoom catches up (higher is snappier).
@export var zoom_follow := 4.0

@export_group("Exits")
@export_file("*.tscn") var exit_left_scene := ""
@export_file("*.tscn") var exit_right_scene := ""

@export_group("Death")
## Seconds the player stays down before respawning at the area spawn point.
@export var respawn_delay := 2.0

@export_group("Debug")
## Draw the feet footprint (the circle tested against obstacles) while running.
@export var show_feet_footprint := false

@onready var background: Sprite2D = $Background
@onready var player: Character = $Player
@onready var camera: Camera2D = $Camera
@onready var area_label: Label = $HUD/UI/AreaLabel
@onready var debug_label: Label = $HUD/UI/DebugLabel
@onready var left_button: Button = $HUD/UI/MoveControls/LeftButton
@onready var right_button: Button = $HUD/UI/MoveControls/RightButton
@onready var up_button: Button = $HUD/UI/MoveControls/UpButton
@onready var down_button: Button = $HUD/UI/MoveControls/DownButton
@onready var attack_button: Button = $HUD/UI/AttackButton
@onready var block_button: Button = $HUD/UI/BlockButton
@onready var back_button: Button = $HUD/UI/BackButton
@onready var health_bar: ProgressBar = $HUD/UI/PlayerHealth/HealthBar
@onready var health_label: Label = $HUD/UI/PlayerHealth/HealthLabel
@onready var death_label: Label = $HUD/UI/DeathLabel

var world_width := 0.0
## Screen-space y of the far and near edges of the walkable band (where feet touch).
var ground_far_y := 0.0
var ground_near_y := 0.0

var _feet_y := 0.0
var _held := {"left": false, "right": false, "up": false, "down": false}
var _leaving := false
var _player_dead := false
## Obstacle footprints in world space: [Shape2D, Transform2D] or a PackedVector2Array polygon.
var _blockers: Array = []
var _feet_shape := CircleShape2D.new()
var _feet_debug: Node2D


func _ready() -> void:
	_layout_background()
	_collect_blockers()
	_place_player()
	area_label.text = area_name
	_bind_player_health()
	_bind_hold(left_button, "left")
	_bind_hold(right_button, "right")
	_bind_hold(up_button, "up")
	_bind_hold(down_button, "down")
	attack_button.pressed.connect(player.attack)
	block_button.button_down.connect(func() -> void: player.block(true))
	block_button.button_up.connect(func() -> void: player.block(false))
	back_button.pressed.connect(_go_to.bind(TITLE_SCENE, ""))
	if show_feet_footprint:
		get_tree().debug_collisions_hint = true
		_feet_debug = Node2D.new()
		_feet_debug.name = "FeetFootprintDebug"
		_feet_debug.z_index = 100
		_feet_debug.draw.connect(_draw_feet_footprint)
		add_child(_feet_debug)


func _bind_hold(button: Button, key: String) -> void:
	button.button_down.connect(func() -> void: _held[key] = true)
	button.button_up.connect(func() -> void: _held[key] = false)


## Mirrors the player's shared Health into the HUD and reacts to death.
func _bind_player_health() -> void:
	_on_player_health_changed(player.current_health, player.max_health)
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)


func _on_player_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP %d / %d" % [current, maximum]


func _on_player_died() -> void:
	if _player_dead:
		return
	_player_dead = true
	for key in _held.keys():
		_held[key] = false
	death_label.visible = true
	_respawn_after_delay()


## Waits out the death pause, then restores the player at the area spawn point.
func _respawn_after_delay() -> void:
	if respawn_delay > 0.0:
		await get_tree().create_timer(respawn_delay).timeout
	if not is_inside_tree() or not is_instance_valid(player):
		return
	player.revive()
	_place_player()
	_player_dead = false
	death_label.visible = false


func _layout_background() -> void:
	var view := get_viewport_rect().size
	if background_texture == null:
		push_error("%s has no background_texture" % name)
		world_width = view.x
		ground_far_y = view.y * 0.6
		ground_near_y = view.y * 0.9
		return
	var tex_size := background_texture.get_size()
	var bg_scale := maxf(view.y / tex_size.y, view.x / tex_size.x)
	background.texture = background_texture
	background.centered = false
	background.scale = Vector2(bg_scale, bg_scale)
	# Anchor the bottom of the image to the bottom of the screen.
	background.position = Vector2(0.0, view.y - tex_size.y * bg_scale)
	world_width = tex_size.x * bg_scale
	ground_far_y = background.position.y + ground_far_px * bg_scale
	ground_near_y = background.position.y + ground_near_px * bg_scale
	camera.limit_left = 0
	camera.limit_right = int(world_width)
	camera.limit_top = int(background.position.y)
	camera.limit_bottom = int(view.y)


## 0 at the far edge of the band, 1 at the near edge.
func depth_ratio() -> float:
	if is_equal_approx(ground_near_y, ground_far_y):
		return 1.0
	return clampf((_feet_y - ground_far_y) / (ground_near_y - ground_far_y), 0.0, 1.0)


func _place_player() -> void:
	var x := world_width * spawn_x_ratio
	if _entry_side == "left":
		x = edge_margin * 2.0
	elif _entry_side == "right":
		x = world_width - edge_margin * 2.0
	_feet_y = lerpf(ground_far_y, ground_near_y, spawn_depth)
	player.position.x = x
	if _entry_side == "right":
		player.set_facing(false)
	_entry_side = ""
	_apply_depth()
	camera.zoom = Vector2.ONE * lerpf(far_zoom, near_zoom, depth_ratio())
	camera.position = _camera_target()
	camera.reset_smoothing()


func _process(delta: float) -> void:
	if _leaving:
		return
	if _player_dead:
		camera.position = _camera_target()
		return
	var direction := Vector2.ZERO
	if _held["left"] or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if _held["right"] or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if _held["up"] or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if _held["down"] or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	# Character.move_2d moves its origin; track the feet so depth scaling stays grounded.
	var before := player.position
	var old_feet := Vector2(before.x, _feet_y)
	player.move_2d(direction, delta)
	var new_feet := Vector2(player.position.x, _feet_y + player.position.y - before.y)
	new_feet.y = clampf(new_feet.y, ground_far_y, ground_near_y)
	new_feet.x = clampf(new_feet.x, edge_margin, maxf(edge_margin, world_width - edge_margin))
	new_feet = _resolve_obstacles(old_feet, new_feet)
	player.position.x = new_feet.x
	_feet_y = new_feet.y
	_apply_depth()

	var target_zoom := lerpf(far_zoom, near_zoom, depth_ratio())
	var z := lerpf(camera.zoom.x, target_zoom, clampf(zoom_follow * delta, 0.0, 1.0))
	camera.zoom = Vector2(z, z)
	camera.position = _camera_target()
	_check_exits(direction.x)
	if _feet_debug != null:
		_feet_debug.queue_redraw()


func _draw_feet_footprint() -> void:
	var feet := Vector2(player.position.x, _feet_y)
	_feet_debug.draw_circle(feet, feet_radius, Color(0.2, 1.0, 0.4, 0.3))
	_feet_debug.draw_arc(feet, feet_radius, 0.0, TAU, 32, Color(0.2, 1.0, 0.4, 0.9), 2.0)


func _collect_blockers() -> void:
	_blockers.clear()
	_feet_shape.radius = feet_radius
	for body in find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			if child is CollisionShape2D and child.shape != null and not child.disabled:
				_blockers.append([child.shape, child.global_transform])
			elif child is CollisionPolygon2D and not child.disabled and child.polygon.size() >= 3:
				_blockers.append(child.global_transform * child.polygon)


## True if the feet at this world position overlap any obstacle.
func is_blocked(feet: Vector2) -> bool:
	var feet_xform := Transform2D(0.0, feet)
	for blocker in _blockers:
		if blocker is PackedVector2Array:
			if Geometry2D.is_point_in_polygon(feet, blocker):
				return true
		elif blocker[0].collide(blocker[1], _feet_shape, feet_xform):
			return true
	return false


## Keeps the feet out of obstacles, sliding along x or depth when only one axis is blocked.
func _resolve_obstacles(from: Vector2, to: Vector2) -> Vector2:
	if _blockers.is_empty() or not is_blocked(to):
		return to
	if not is_blocked(Vector2(to.x, from.y)):
		return Vector2(to.x, from.y)
	if not is_blocked(Vector2(from.x, to.y)):
		return Vector2(from.x, to.y)
	return from


## Scales the character for its depth and stands it on the current feet line.
## Also sets z_index so that characters farther up (farther back) render behind
## those closer down (nearer to camera), giving proper sprite overlap.
func _apply_depth() -> void:
	var s := lerpf(far_character_scale, near_character_scale, depth_ratio())
	player.set_render_scale(s)
	player.position.y = _feet_y - FEET_OFFSET_LOCAL * s
	# One shared y -> z mapping for the whole game: farther up = lower index.
	player.z_index = DepthSort.z_for_y(_feet_y)


func _camera_target() -> Vector2:
	# Frame the character's upper body; Camera2D limits keep the view inside the image.
	var s := player.render_scale
	return Vector2(player.position.x, _feet_y - FEET_OFFSET_LOCAL * s * 0.5)


func _print_debug() -> void:
	var s := player.render_scale
	var health_str := "%d/%d" % [player.current_health, player.max_health]
	var blocking := player.is_blocking()
	var blocking_str := "blocking" if blocking else "idle"
	var debug_str := "[DEBUG] %s | pos=(%.0f, %.0f) | feet_y=%.0f | scale=%.2f | z_index=%d | depth_ratio=%.2f | render_scale=%.2f | %s | health=%s" % [
		player.name,
		player.position.x,
		player.position.y,
		_feet_y,
		s,
		player.z_index,
		depth_ratio(),
		s,
		blocking_str,
		health_str,
	]
	debug_label.text = debug_str


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_J or event.keycode == KEY_Z:
			if event.pressed:
				player.attack()
		if event.keycode == KEY_K:
			player.block(event.pressed)
		if event.keycode == KEY_I and event.pressed:
			_print_debug()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		player.block(event.pressed)


func _check_exits(direction_x: float) -> void:
	if direction_x < 0.0 and exit_left_scene != "" and player.position.x <= edge_margin + 1.0:
		_go_to(exit_left_scene, "right")
	elif direction_x > 0.0 and exit_right_scene != "" and player.position.x >= world_width - edge_margin - 1.0:
		_go_to(exit_right_scene, "left")


func _go_to(scene_path: String, entry_side: String) -> void:
	if _leaving:
		return
	_leaving = true
	_entry_side = entry_side
	get_tree().change_scene_to_file.call_deferred(scene_path)
