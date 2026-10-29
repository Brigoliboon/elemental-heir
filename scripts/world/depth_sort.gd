class_name DepthSort
extends RefCounted
## Converts a world-space depth anchor (normally the y of an entity's feet) into a
## canvas z-index. Smaller y = farther up/back = lower index; larger y = nearer/down
## = higher index. All depth-aware entities and overlays use this one mapping so they
## can correctly pass in front of or behind each other.
##
## Godot's canvas z-index range is -4096..4096, which comfortably covers a 1080p
## stage plus off-screen margins.

const MIN_Z_INDEX := -4096
const MAX_Z_INDEX := 4096


static func z_for_y(world_y: float) -> int:
	return clampi(roundi(world_y), MIN_Z_INDEX, MAX_Z_INDEX)


## Assigns the depth index directly on any CanvasItem (CharacterBody2D, Sprite2D,
## Area2D, ...) from its depth anchor.
static func apply(item: CanvasItem, depth_y: float) -> void:
	if item == null:
		return
	item.z_index = z_for_y(depth_y)


## Resolves the world-space feet/depth y coordinate for an entity or node.
static func get_feet_y(node: Node) -> float:
	if node == null:
		return 0.0
	if node.has_method("get_feet_y"):
		return node.get_feet_y()
	if node is Node2D:
		return (node as Node2D).global_position.y
	return 0.0


## Returns true if two entities are within the given depth tolerance.
## A tolerance <= 0 disables the check.
static func is_in_depth(a: Node, b: Node, tolerance: float) -> bool:
	if tolerance <= 0.0 or a == null or b == null:
		return true
	return absf(get_feet_y(a) - get_feet_y(b)) <= tolerance

