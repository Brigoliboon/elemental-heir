class_name DepthOverlay
extends Sprite2D
## Gives a sprite a depth index based on the bottom edge of its art, so characters
## can walk behind it (when farther up the screen) or in front of it (nearer down).
##
## Attach to scene props such as the fountain overlay. The anchor is the sprite's
## bottom edge by default; use depth_offset to nudge it (positive = nearer/front).

## Extra pixels added to the calculated bottom edge before converting to z-index.
@export var depth_offset := 0.0
## Recalculate every frame. Leave off for static props.
@export var follow_position := false


func _ready() -> void:
	_apply_depth()
	set_process(follow_position)


func _process(_delta: float) -> void:
	_apply_depth()


## World-space y of the sprite's bottom edge, scaled by its current transform.
func depth_y() -> float:
	if texture == null:
		return global_position.y + depth_offset
	var scaled_height := absf(texture.get_height() * global_scale.y)
	var bottom := (global_position.y + scaled_height * 0.5) if centered else (global_position.y + scaled_height)
	return bottom + depth_offset


func _apply_depth() -> void:
	z_index = DepthSort.z_for_y(depth_y())
