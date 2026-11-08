extends Area2D
## Triggers a scene change when the player enters its collision shape at the right
## depth. The shape's x/y only defines the doorway; [member depth_ratio] says where
## the doorway sits inside the area's walkable band, so brushing past it in front
## of or behind the door no longer teleports the player.

@export_file("*.tscn") var target_scene := ""
## Depth inside the walkable band: 0 = far edge (back of the scene), 1 = near edge
## (bottom of the screen). Doors painted into the back wall use 0; exits walked
## down into use 1.
@export_range(0.0, 1.0) var depth_ratio := 0.0
## How far the feet may be from the doorway depth, in 1920x1080 world pixels.
## Scales with the background. 0 disables the depth check.
@export var depth_tolerance := 56.0
## Node path inside the target scene of the doorway this exit returns to, e.g.
## "InnEntrance/Inn". The player appears at that door instead of the target
## area's default spawn. Empty keeps the default spawn.
@export var entry_spawn_path := ""

var _armed := false
var _player: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Avoid firing when a scene spawns the player inside this area.
	get_tree().create_timer(0.5).timeout.connect(func(): _armed = true)


func _physics_process(_delta: float) -> void:
	if not _armed or target_scene == "":
		return
	if _player == null or not is_instance_valid(_player):
		return
	if is_player_in_depth(_player):
		_trigger()


## True when [param body]'s feet are close enough to the doorway's depth.
func is_player_in_depth(body: Node) -> bool:
	if body == null:
		return false
	if depth_tolerance <= 0.0:
		return true
	return absf(DepthSort.get_feet_y(body) - depth_anchor_y()) <= _world_tolerance()


## World-space depth of the doorway, taken from the owning area's walkable band.
func depth_anchor_y() -> float:
	var area := _find_area()
	if area == null:
		return global_position.y
	return lerpf(area.ground_far_y, area.ground_near_y, clampf(depth_ratio, 0.0, 1.0))


func _world_tolerance() -> float:
	var area := _find_area()
	if area == null or area.background == null:
		return depth_tolerance
	return depth_tolerance * area.background.scale.y / Area.DESIGN_BACKGROUND_SCALE


func _find_area() -> Area:
	var node := get_parent()
	while node != null:
		if node is Area:
			return node as Area
		node = node.get_parent()
	return null


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as Node2D


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null


func _trigger() -> void:
	_armed = false
	_player = null
	if not entry_spawn_path.is_empty():
		Area.set_entry_spawn(entry_spawn_path)
	get_tree().change_scene_to_file.call_deferred(target_scene)
