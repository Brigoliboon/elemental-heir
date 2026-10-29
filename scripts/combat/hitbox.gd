class_name Hitbox
extends Area2D
## A reusable damage area used by both the player's sword and enemy attacks.
##
## The owner enables it only during the active frames of an attack. Each target can
## only be hit once per activation, so a single swing cannot tick damage every frame.
## Hit detection uses physics bodies (CharacterBody2D); set collision_layer and
## collision_mask in the scene, or before adding a runtime-created hitbox.

signal hit_landed(target: Node2D)

## Damage dealt to targets that expose take_damage(amount).
@export var damage := 10
## Impulse (px/s) pushed into targets that accept take_damage(amount, knockback).
@export var knockback_force := 0.0
## Only nodes in this group are damaged. Leave empty to accept any body on the mask.
@export var target_group := "enemies"
## Maximum depth (feet y) difference for an attack to connect. Set to 0 to disable.
@export var depth_tolerance: float = 40.0
## The entity that owns this hitbox. If null, resolved by searching parents.
@export var attacker: Node2D
## Draw the hitbox in the editor/debug runs.
@export var debug_draw := false

var _active := false
var _hit_targets: Dictionary = {}


func _ready() -> void:
	monitoring = false
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _process(_delta: float) -> void:
	if debug_draw:
		queue_redraw()


func _draw() -> void:
	if not debug_draw:
		return
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var rect := child.shape as RectangleShape2D
			draw_rect(Rect2(-rect.size * 0.5, rect.size), Color(1.0, 0.25, 0.2, 0.35), true)
			draw_rect(Rect2(-rect.size * 0.5, rect.size), Color(1.0, 0.55, 0.2, 0.9), false, 2.0)


func is_active() -> bool:
	return _active


## Starts a new hit window. Clears the per-swing hit list and detects anything
## already overlapping the area.
func activate(damage_override: int = -1) -> void:
	if damage_override >= 0:
		damage = damage_override
	_active = true
	_hit_targets.clear()
	set_deferred("monitoring", true)
	call_deferred("_scan_overlaps")


func deactivate() -> void:
	if not _active:
		return
	_active = false
	set_deferred("monitoring", false)


func _scan_overlaps() -> void:
	if not _active:
		return
	for body in get_overlapping_bodies():
		_try_hit(body)


func _on_body_entered(body: Node2D) -> void:
	if _active:
		_try_hit(body)


func _on_area_entered(area: Area2D) -> void:
	if _active:
		_try_hit(area.get_parent())


func _try_hit(node: Node) -> void:
	if not _active or node == null or not is_instance_valid(node):
		return
	if target_group != "" and not node.is_in_group(target_group):
		return
	var id := node.get_instance_id()
	if _hit_targets.has(id):
		return
	# Verify depth alignment so attacks don't connect across different depth planes.
	if depth_tolerance > 0.0:
		var att := _get_attacker()
		if att != null and not DepthSort.is_in_depth(att, node, depth_tolerance):
			return
	_hit_targets[id] = true
	if node.has_method("take_damage"):
		node.take_damage(damage, _knockback_toward(node))
		hit_landed.emit(node as Node2D)


func _get_attacker() -> Node2D:
	if attacker != null:
		return attacker
	var p: Node = get_parent()
	while p != null:
		if p is CharacterBody2D or p.has_method("take_damage") or p.has_method("get_feet_y"):
			attacker = p as Node2D
			return attacker
		p = p.get_parent()
	return null


## Pushes the target away from the hitbox centre. Zero when no force is configured.
func _knockback_toward(node: Node) -> Vector2:
	if knockback_force <= 0.0 or not node is Node2D:
		return Vector2.ZERO
	var target := node as Node2D
	var away := target.global_position - global_position
	if away.length_squared() < 0.001:
		away = Vector2.RIGHT
	return away.normalized() * knockback_force
