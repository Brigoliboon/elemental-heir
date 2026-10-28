extends Node2D

const PIVOTS_PATH := "res://assets/characters/warrior/t1_side/warrior_t1_side/pivots.json"
const PART_DIR := "res://assets/characters/warrior/t1_side/warrior_t1_side/"
const BASE_SCALE := 3.0
const IDLE_LOOP := 2.0
const WALK_LOOP := 0.95
const TAU := 6.28318530718
const WALK_KEY_COUNT := 8
const WALK_LEAN_BASE := 10.0
const WALK_LEAN_SWAY := 1.0
const WALK_ARM_AMP := 23.0
const WALK_BOB_TABLE := [0.0, 1.4, 0.0, -1.4, 0.0, 1.4, 0.0, -1.4]
const WALK_THIGH_R := [-28.0, -18.0, -5.0, 14.0, 28.0, 16.0, -2.0, -20.0]
const WALK_KNEE_R := [6.0, 16.0, 12.0, 8.0, 10.0, 34.0, 52.0, 22.0]
const WALK_ROLL_R := [-8.0, 0.0, 0.0, 6.0, 14.0, -2.0, -4.0, -10.0]
const IDLE_LEAN := 4.5
const IDLE_COMPRESSION := 0.8
const IDLE_BOB := 0.6
const HEAD_LOOK_UP := 2.5
const HEAD_BOB_COUNTER := 0.35
const CHARACTER_MARGIN := 130.0

@onready var character_root: Node2D = $CharacterRoot
@onready var skeleton: Skeleton2D = $CharacterRoot/Skeleton2D
@onready var anim_player: AnimationPlayer = $CharacterRoot/AnimationPlayer
@onready var idle_button: Button = %IdleButton
@onready var walk_button: Button = %WalkButton
@onready var facing_button: Button = %FacingButton
@onready var back_button: Button = %BackButton
@onready var left_button: Button = %LeftButton
@onready var right_button: Button = %RightButton

var _parts: Dictionary = {}
var _bones: Dictionary = {}
var _rest_rotation_deg: Dictionary = {}
var _rest_position: Dictionary = {}
var _facing_right := true
var _manual_animation := "idle"
var _is_moving := false
var _left_held := false
var _right_held := false
var _walk_speed := 230.0


func _ready() -> void:
	_load_rig_data()
	for part_name in _parts.keys():
		_ensure_bone(str(part_name))

	_walk_speed = _compute_walk_speed()
	_build_animations()
	anim_player.play("idle")

	idle_button.pressed.connect(_on_idle_pressed)
	walk_button.pressed.connect(_on_walk_pressed)
	facing_button.pressed.connect(_on_facing_pressed)
	back_button.pressed.connect(_on_back_pressed)
	left_button.button_down.connect(_on_left_down)
	left_button.button_up.connect(_on_left_up)
	right_button.button_down.connect(_on_right_down)
	right_button.button_up.connect(_on_right_up)
	_update_facing_label()


func _process(delta: float) -> void:
	var direction := 0
	if _left_held or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= 1
	if _right_held or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += 1

	if direction != 0:
		_is_moving = true
		_set_facing(direction > 0)
		character_root.position.x += float(direction) * _walk_speed * delta
		_clamp_character()
		if anim_player.current_animation != "walk":
			anim_player.play("walk")
	elif _is_moving:
		_is_moving = false
		_manual_animation = "idle"
		anim_player.play("idle")
	elif _manual_animation != "" and anim_player.current_animation != _manual_animation:
		anim_player.play(_manual_animation)


func _load_rig_data() -> void:
	var text := FileAccess.get_file_as_string(PIVOTS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Could not parse warrior pivots JSON: %s" % PIVOTS_PATH)
		return
	var data: Dictionary = parsed
	_parts = data["parts"]


func _ensure_bone(part_name: String) -> Bone2D:
	if _bones.has(part_name):
		return _bones[part_name]

	var data: Dictionary = _parts[part_name]
	var bone := Bone2D.new()
	bone.name = part_name
	bone.set_autocalculate_length_and_angle(false)
	bone.length = 10.0
	bone.rotation = deg_to_rad(float(data["rest_rotation_local_deg"]))
	_rest_rotation_deg[part_name] = float(data["rest_rotation_local_deg"])

	var parent_name: Variant = data.get("parent")
	var parent_bone: Bone2D = null
	if parent_name == null:
		var pivot_in_canvas: Array = data["pivot_in_rest_canvas"]
		bone.position = Vector2(float(pivot_in_canvas[0]), float(pivot_in_canvas[1]))
	else:
		parent_bone = _ensure_bone(str(parent_name))
		var parent_data: Dictionary = _parts[str(parent_name)]
		var attach: Array = data["attach_point_in_parent"]
		var parent_pivot: Array = parent_data["pivot"]
		bone.position = Vector2(
			float(attach[0]) - float(parent_pivot[0]),
			float(attach[1]) - float(parent_pivot[1])
		)
	_rest_position[part_name] = bone.position

	# Runtime-created Bone2D nodes have a zero Transform2D for `rest`. Skeleton2D
	# inverts it when setting up bones, so give it the JSON rest transform.
	bone.rest = Transform2D(bone.rotation, bone.position)

	if parent_bone == null:
		skeleton.add_child(bone)
	else:
		parent_bone.add_child(bone)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_as_relative = false
	sprite.z_index = int(data["z_index"])
	var pivot: Array = data["pivot"]
	sprite.offset = Vector2(-float(pivot[0]), -float(pivot[1]))
	sprite.texture = load(PART_DIR + str(data["file"]))
	bone.add_child(sprite)

	_bones[part_name] = bone
	return bone


func _build_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _make_idle_animation())
	library.add_animation("walk", _make_walk_animation())
	anim_player.add_animation_library("", library)


func _make_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = IDLE_LOOP
	animation.loop_mode = Animation.LOOP_LINEAR

	var times: Array = [0.0, IDLE_LOOP * 0.25, IDLE_LOOP * 0.5, IDLE_LOOP * 0.75, IDLE_LOOP]
	var bob_values: Array = [0.0, -IDLE_BOB, 0.0, IDLE_BOB, 0.0]
	var scale_y_values: Array = [1.0, 1.012, 1.0, 0.996, 1.0]
	var lean_values: Array = [IDLE_LEAN, IDLE_LEAN + 0.5, IDLE_LEAN, IDLE_LEAN - 0.5, IDLE_LEAN]
	var arm_l_values: Array = [0.0, 1.4, 0.0, -1.4, 0.0]
	var arm_r_values: Array = [0.0, -1.1, 0.0, 1.1, 0.0]
	var forearm_l_values: Array = [-1.0, 0.9, -1.0, -2.9, -1.0]
	var forearm_r_values: Array = [-1.0, -2.7, -1.0, 0.7, -1.0]
	var sword_values: Array = [36.0, 35.0, 36.0, 37.0, 36.0]

	var square_l: Array = _leg_square_offsets("thigh_l", "shin_l")
	var square_r: Array = _leg_square_offsets("thigh_r", "shin_r")
	var metrics_l: Array = _leg_metrics("thigh_l", "shin_l")
	var metrics_r: Array = _leg_metrics("thigh_r", "shin_r")

	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
	var shin_l_rot: Array = []
	var shin_r_rot: Array = []
	var foot_l_rot: Array = []
	var foot_r_rot: Array = []
	var torso_pos: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var thigh_l_pos: Array = []
	var torso_scale: Array = []
	var thigh_l_scale: Array = []
	var thigh_r_scale: Array = []
	var torso_rest: Vector2 = _rest_position["torso"]
	var head_rest: Vector2 = _rest_position["head"]
	var thigh_l_rest: Vector2 = _rest_position["thigh_l"]

	for i in range(times.size()):
		var breath := float(bob_values[i])
		var body_offset := IDLE_COMPRESSION + breath
		var lean := float(lean_values[i])
		var pose_l: Array = _solve_grounded_leg(
			float(metrics_l[0]), float(metrics_l[1]),
			float(metrics_l[0]) + float(metrics_l[1]) - body_offset
		)
		var pose_r: Array = _solve_grounded_leg(
			float(metrics_r[0]), float(metrics_r[1]),
			float(metrics_r[0]) + float(metrics_r[1]) - body_offset
		)
		var thigh_walk_l := float(pose_l[0])
		var knee_l := float(pose_l[1])
		var thigh_walk_r := float(pose_r[0])
		var knee_r := float(pose_r[1])
		var scale_y := float(scale_y_values[i])

		thigh_l_rot.append(float(square_l[0]) + thigh_walk_l - lean)
		shin_l_rot.append(float(square_l[1]) + knee_l)
		foot_l_rot.append(float(square_l[2]) - thigh_walk_l - knee_l)
		thigh_r_rot.append(float(square_r[0]) + thigh_walk_r - lean)
		shin_r_rot.append(float(square_r[1]) + knee_r)
		foot_r_rot.append(float(square_r[2]) - thigh_walk_r - knee_r)

		torso_pos.append(torso_rest + Vector2(0.0, body_offset))
		torso_scale.append(Vector2(1.0, scale_y))
		thigh_l_pos.append(thigh_l_rest.rotated(deg_to_rad(-lean)))
		thigh_l_scale.append(Vector2(1.0, 1.0 / scale_y))
		thigh_r_scale.append(Vector2(1.0, 1.0 / scale_y))
		head_rot.append(-lean - HEAD_LOOK_UP + 0.35 * sin(TAU * float(i) / 4.0))
		head_pos.append(head_rest + Vector2(0.0, -HEAD_BOB_COUNTER * breath))

	_add_rotation_track(animation, "torso", times, lean_values)
	_add_rotation_track(animation, "head", times, head_rot)
	_add_rotation_track(animation, "thigh_l", times, thigh_l_rot)
	_add_rotation_track(animation, "thigh_r", times, thigh_r_rot)
	_add_rotation_track(animation, "shin_l", times, shin_l_rot)
	_add_rotation_track(animation, "shin_r", times, shin_r_rot)
	_add_rotation_track(animation, "foot_l", times, foot_l_rot)
	_add_rotation_track(animation, "foot_r", times, foot_r_rot)
	_add_rotation_track(animation, "upper_arm_l", times, arm_l_values)
	_add_rotation_track(animation, "upper_arm_r", times, arm_r_values)
	_add_rotation_track(animation, "forearm_l", times, forearm_l_values)
	_add_rotation_track(animation, "forearm_r", times, forearm_r_values)
	_add_rotation_track(animation, "sword", times, sword_values)
	_add_position_track(animation, "torso", times, torso_pos)
	_add_position_track(animation, "head", times, head_pos)
	_add_position_track(animation, "thigh_l", times, thigh_l_pos)
	_add_scale_track(animation, "torso", times, torso_scale)
	_add_scale_track(animation, "thigh_l", times, thigh_l_scale)
	_add_scale_track(animation, "thigh_r", times, thigh_r_scale)
	return animation


func _make_walk_animation() -> Animation:
	var animation := Animation.new()
	animation.length = WALK_LOOP
	animation.loop_mode = Animation.LOOP_LINEAR

	var times: Array = []
	var torso_rot: Array = []
	var torso_pos: Array = []
	var torso_scale: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
	var thigh_l_pos: Array = []
	var thigh_l_scale: Array = []
	var thigh_r_scale: Array = []
	var shin_l_rot: Array = []
	var shin_r_rot: Array = []
	var foot_l_rot: Array = []
	var foot_r_rot: Array = []
	var arm_l: Array = []
	var arm_r: Array = []
	var forearm_l: Array = []
	var forearm_r: Array = []
	var sword_rot: Array = []

	var square_l: Array = _leg_square_offsets("thigh_l", "shin_l")
	var square_r: Array = _leg_square_offsets("thigh_r", "shin_r")
	var torso_rest: Vector2 = _rest_position["torso"]
	var head_rest: Vector2 = _rest_position["head"]
	var thigh_l_rest: Vector2 = _rest_position["thigh_l"]

	for i in range(WALK_KEY_COUNT + 1):
		var idx := i % WALK_KEY_COUNT
		var phase := TAU * float(idx) / float(WALK_KEY_COUNT)
		var lean := WALK_LEAN_BASE + WALK_LEAN_SWAY * sin(phase)
		var bob := float(WALK_BOB_TABLE[idx])
		var right_idx := idx
		var left_idx := (idx + 4) % WALK_KEY_COUNT
		var thigh_walk_r := float(WALK_THIGH_R[right_idx])
		var knee_r := float(WALK_KNEE_R[right_idx])
		var roll_r := float(WALK_ROLL_R[right_idx])
		var thigh_walk_l := float(WALK_THIGH_R[left_idx])
		var knee_l := float(WALK_KNEE_R[left_idx])
		var roll_l := float(WALK_ROLL_R[left_idx])
		var arm_swing := WALK_ARM_AMP * cos(phase)

		times.append(WALK_LOOP * float(i) / float(WALK_KEY_COUNT))
		torso_rot.append(lean)
		torso_pos.append(torso_rest + Vector2(0.0, bob))
		torso_scale.append(Vector2.ONE)
		head_rot.append(-lean - HEAD_LOOK_UP + 0.4 * sin(phase * 2.0))
		head_pos.append(head_rest + Vector2(0.0, -HEAD_BOB_COUNTER * bob))

		thigh_l_rot.append(float(square_l[0]) + thigh_walk_l - lean)
		thigh_r_rot.append(float(square_r[0]) + thigh_walk_r - lean)
		thigh_l_pos.append(thigh_l_rest.rotated(deg_to_rad(-lean)))
		thigh_l_scale.append(Vector2.ONE)
		thigh_r_scale.append(Vector2.ONE)
		shin_l_rot.append(float(square_l[1]) + knee_l)
		shin_r_rot.append(float(square_r[1]) + knee_r)
		foot_l_rot.append(float(square_l[2]) - thigh_walk_l - knee_l + roll_l)
		foot_r_rot.append(float(square_r[2]) - thigh_walk_r - knee_r + roll_r)

		arm_r.append(arm_swing)
		arm_l.append(-arm_swing)
		forearm_r.append(-6.0 - 4.0 * sin(phase))
		forearm_l.append(-6.0 + 4.0 * sin(phase))
		sword_rot.append(0.0)

	_add_rotation_track(animation, "torso", times, torso_rot)
	_add_rotation_track(animation, "head", times, head_rot)
	_add_rotation_track(animation, "thigh_l", times, thigh_l_rot)
	_add_rotation_track(animation, "thigh_r", times, thigh_r_rot)
	_add_rotation_track(animation, "shin_l", times, shin_l_rot)
	_add_rotation_track(animation, "shin_r", times, shin_r_rot)
	_add_rotation_track(animation, "foot_l", times, foot_l_rot)
	_add_rotation_track(animation, "foot_r", times, foot_r_rot)
	_add_rotation_track(animation, "upper_arm_l", times, arm_l)
	_add_rotation_track(animation, "upper_arm_r", times, arm_r)
	_add_rotation_track(animation, "forearm_l", times, forearm_l)
	_add_rotation_track(animation, "forearm_r", times, forearm_r)
	_add_rotation_track(animation, "sword", times, sword_rot)
	_add_position_track(animation, "torso", times, torso_pos)
	_add_position_track(animation, "head", times, head_pos)
	_add_position_track(animation, "thigh_l", times, thigh_l_pos)
	_add_scale_track(animation, "torso", times, torso_scale)
	_add_scale_track(animation, "thigh_l", times, thigh_l_scale)
	_add_scale_track(animation, "thigh_r", times, thigh_r_scale)
	return animation


func _leg_metrics(thigh_name: String, shin_name: String) -> Array:
	var thigh_data: Dictionary = _parts[thigh_name]
	var shin_data: Dictionary = _parts[shin_name]
	var thigh_pivot: Array = thigh_data["pivot"]
	var thigh_knee: Array = thigh_data["joints"]["knee"]
	var shin_pivot: Array = shin_data["pivot"]
	var shin_ankle: Array = shin_data["joints"]["ankle"]
	var a := Vector2(
		float(thigh_knee[0]) - float(thigh_pivot[0]),
		float(thigh_knee[1]) - float(thigh_pivot[1])
	).length()
	var b := Vector2(
		float(shin_ankle[0]) - float(shin_pivot[0]),
		float(shin_ankle[1]) - float(shin_pivot[1])
	).length()
	return [a, b]


func _drop_for_knee(a: float, b: float, knee_deg: float) -> float:
	var knee := deg_to_rad(knee_deg)
	var thigh := atan2(-b * sin(knee), a + b * cos(knee))
	return a * cos(thigh) + b * cos(thigh + knee)


func _solve_grounded_leg(a: float, b: float, drop: float) -> Array:
	var maximum := a + b
	var minimum := _drop_for_knee(a, b, 78.0)
	var target := clampf(drop, minimum, maximum)
	var low := 0.0
	var high := 78.0
	for _iteration in range(26):
		var middle := (low + high) * 0.5
		if _drop_for_knee(a, b, middle) > target:
			low = middle
		else:
			high = middle
	var knee := (low + high) * 0.5
	var knee_rad := deg_to_rad(knee)
	var thigh := atan2(-b * sin(knee_rad), a + b * cos(knee_rad))
	return [rad_to_deg(thigh), knee]


func _ankle_forward_offset(a: float, b: float, thigh_walk_deg: float, knee_deg: float) -> float:
	var thigh_angle := deg_to_rad(90.0 + thigh_walk_deg)
	var shin_angle := deg_to_rad(90.0 + thigh_walk_deg + knee_deg)
	return a * cos(thigh_angle) + b * cos(shin_angle)


func _compute_walk_speed() -> float:
	var metrics_l: Array = _leg_metrics("thigh_l", "shin_l")
	var metrics_r: Array = _leg_metrics("thigh_r", "shin_r")
	var right_front := _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]),
		float(WALK_THIGH_R[0]), float(WALK_KNEE_R[0])
	)
	var right_back := _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]),
		float(WALK_THIGH_R[4]), float(WALK_KNEE_R[4])
	)
	var left_front := _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]),
		float(WALK_THIGH_R[0]), float(WALK_KNEE_R[0])
	)
	var left_back := _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]),
		float(WALK_THIGH_R[4]), float(WALK_KNEE_R[4])
	)
	var step := ((right_front - right_back) + (left_front - left_back)) * 0.5
	return step * BASE_SCALE * 2.0 / WALK_LOOP


func _leg_square_offsets(thigh_name: String, shin_name: String) -> Array:
	var thigh_data: Dictionary = _parts[thigh_name]
	var shin_data: Dictionary = _parts[shin_name]
	var thigh_offset := 90.0 - _joint_world_angle(thigh_data, "knee")
	var shin_offset := 90.0 - (_joint_world_angle(shin_data, "ankle") + thigh_offset)
	var foot_offset := -(thigh_offset + shin_offset)
	return [thigh_offset, shin_offset, foot_offset]


func _joint_world_angle(part_data: Dictionary, joint_name: String) -> float:
	var pivot: Array = part_data["pivot"]
	var joint: Array = part_data["joints"][joint_name]
	var offset := Vector2(
		float(joint[0]) - float(pivot[0]),
		float(joint[1]) - float(pivot[1])
	)
	offset = offset.rotated(deg_to_rad(float(part_data["rest_rotation_world_deg"])))
	return rad_to_deg(atan2(offset.y, offset.x))


func _part_path(part_name: String) -> String:
	var segments: Array = []
	var current := part_name
	while _parts.has(current):
		segments.push_front(current)
		var parent: Variant = _parts[current].get("parent")
		if parent == null:
			break
		current = str(parent)
	return "Skeleton2D/" + "/".join(PackedStringArray(segments))


func _add_rotation_track(animation: Animation, part_name: String, times: Array, offsets_deg: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:rotation" % _part_path(part_name)))
	var rest := float(_rest_rotation_deg[part_name])
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], deg_to_rad(rest + offsets_deg[i]))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)


func _add_position_track(animation: Animation, part_name: String, times: Array, positions: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:position" % _part_path(part_name)))
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], positions[i])
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)


func _add_scale_track(animation: Animation, part_name: String, times: Array, scales: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:scale" % _part_path(part_name)))
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], scales[i])
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)


func _clamp_character() -> void:
	var viewport_width := get_viewport_rect().size.x
	var limit := maxf(CHARACTER_MARGIN, viewport_width - CHARACTER_MARGIN)
	character_root.position.x = clampf(character_root.position.x, CHARACTER_MARGIN, limit)


func _set_facing(right: bool) -> void:
	if _facing_right == right:
		return
	_facing_right = right
	character_root.scale.x = BASE_SCALE if _facing_right else -BASE_SCALE
	_update_facing_label()


func _on_left_down() -> void:
	_left_held = true


func _on_left_up() -> void:
	_left_held = false


func _on_right_down() -> void:
	_right_held = true


func _on_right_up() -> void:
	_right_held = false


func _on_idle_pressed() -> void:
	_manual_animation = "idle"
	anim_player.play("idle")


func _on_walk_pressed() -> void:
	_manual_animation = "walk"
	anim_player.play("walk")


func _on_facing_pressed() -> void:
	_facing_right = not _facing_right
	character_root.scale.x = BASE_SCALE if _facing_right else -BASE_SCALE
	_update_facing_label()


func _update_facing_label() -> void:
	facing_button.text = "Facing: Right" if _facing_right else "Facing: Left"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title/title_screen.tscn")
