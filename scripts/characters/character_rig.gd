class_name CharacterRig
extends RefCounted
## Builds a Skeleton2D at runtime from a pivots.json cut-out rig and keeps the rest pose
## data that animation builders need.

var parts: Dictionary = {}
var bones: Dictionary = {}
var rest_rotation_deg: Dictionary = {}
var rest_position: Dictionary = {}
var base_scale := 1.0

var _config: CharacterConfig
var _skeleton: Skeleton2D


func _init(config: CharacterConfig, skeleton: Skeleton2D) -> void:
	_config = config
	_skeleton = skeleton
	base_scale = config.base_scale


func build() -> void:
	_load_parts(_config.pivots_path)
	for part_name in parts.keys():
		_ensure_bone(str(part_name))


func _load_parts(pivots_path: String) -> void:
	var text := FileAccess.get_file_as_string(pivots_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Could not parse rig pivots JSON: %s" % pivots_path)
		return
	var data: Dictionary = parsed
	parts = data["parts"]


func _ensure_bone(part_name: String) -> Bone2D:
	if bones.has(part_name):
		return bones[part_name]

	var data: Dictionary = parts[part_name]
	var bone := Bone2D.new()
	bone.name = part_name
	bone.set_autocalculate_length_and_angle(false)
	bone.length = 10.0
	bone.rotation = deg_to_rad(float(data["rest_rotation_local_deg"]))
	rest_rotation_deg[part_name] = float(data["rest_rotation_local_deg"])

	var parent_name: Variant = data.get("parent")
	var parent_bone: Bone2D = null
	if parent_name == null:
		var pivot_in_canvas: Array = data["pivot_in_rest_canvas"]
		bone.position = Vector2(float(pivot_in_canvas[0]), float(pivot_in_canvas[1]))
	else:
		parent_bone = _ensure_bone(str(parent_name))
		var parent_data: Dictionary = parts[str(parent_name)]
		var attach: Array = data["attach_point_in_parent"]
		var parent_pivot: Array = parent_data["pivot"]
		bone.position = Vector2(
			float(attach[0]) - float(parent_pivot[0]),
			float(attach[1]) - float(parent_pivot[1])
		)
	if parent_name != null:
		bone.position *= part_scale(str(parent_name))
	if part_name == "thigh_l":
		bone.position.x += _config.far_leg_x_offset
	rest_position[part_name] = bone.position

	# Runtime-created Bone2D nodes have a zero Transform2D for `rest`. Skeleton2D
	# inverts it when setting up bones, so give it the JSON rest transform.
	bone.rest = Transform2D(bone.rotation, bone.position)

	if parent_bone == null:
		_skeleton.add_child(bone)
	else:
		parent_bone.add_child(bone)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_as_relative = false
	sprite.z_index = int(_config.draw_order.get(part_name, int(data["z_index"])))
	var pivot: Array = data["pivot"]
	sprite.offset = Vector2(-float(pivot[0]), -float(pivot[1]))
	sprite.texture = load(_config.part_dir + str(data["file"]))
	sprite.scale = part_scale(part_name)
	bone.add_child(sprite)

	bones[part_name] = bone
	return bone


## Lengthwise stretch for a part's sprite and its child attach points.
func part_scale(part_name: String) -> Vector2:
	if part_name == "thigh_l" or part_name == "thigh_r":
		return Vector2(1.0, _config.thigh_length_scale)
	return Vector2.ONE


## A joint's offset from the part's pivot in part space, including the part's stretch.
func joint_vector(part_name: String, joint_name: String) -> Vector2:
	var data: Dictionary = parts[part_name]
	var pivot: Array = data["pivot"]
	var joint: Array = data["joints"][joint_name]
	var offset := Vector2(float(joint[0]) - float(pivot[0]), float(joint[1]) - float(pivot[1]))
	return offset * part_scale(part_name)


## NodePath (relative to the character root) of a part's bone.
func part_path(part_name: String) -> String:
	var segments: Array = []
	var current := part_name
	while parts.has(current):
		segments.push_front(current)
		var parent: Variant = parts[current].get("parent")
		if parent == null:
			break
		current = str(parent)
	return "Skeleton2D/" + "/".join(PackedStringArray(segments))
