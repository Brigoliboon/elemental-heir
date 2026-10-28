class_name WarriorSideAnimations
extends RefCounted
## Builds the warrior side-view clips (idle, walk, attacks) procedurally on top of a
## CharacterRig. All motion tuning for this rig lives in the constants below.

const IDLE_LOOP := 2.0
const WALK_LOOP := 0.95
const TAU := 6.28318530718
const WALK_KEY_COUNT := 8
const WALK_LEAN_BASE := 6.0
const WALK_LEAN_SWAY := 1.0
const WALK_PELVIS_ROT := 2.0
const MAX_TORSO_LEAN := 15
const WALK_ARM_AMP := 2
const WALK_BOB_TABLE := [0.3, 0.15, 0.0, 0.15, 0.3, 0.15, 0.0, 0.15]
const WALK_THIGH_R := [-28.0, -18.0, -5.0, 14.0, 28.0, 16.0, -2.0, -20.0]
const WALK_KNEE_R := [3.0, 8.0, 6.0, 4.0, 5.0, 16.0, 25.0, 11.0]
const WALK_FOOT_R := [-10.0, -2.0, 0.0, 2.0, 7.0, 10.0, 7.0, -7.0]
const GUARD_UPPER_ARM_R := -5
const GUARD_FOREARM_R := 0.0
const GUARD_HAND_R := 6.0
const GUARD_SWORD_WORLD := -128.0
const IDLE_LEAN := 6
const IDLE_COMPRESSION := 0.0
const IDLE_BOB := 0.0
const HEAD_LOOK_UP := 2.5
const HEAD_BOB_COUNTER := 0.35
# Run cycle: 8 keys per loop, index 0 = right foot landing in front, the left leg runs
# half a cycle behind. Thigh/knee/foot are degrees like the walk tables; knee folds high
# during the recovery swing. Bob is +y down (rig px), low at mid-stance, up in flight.
const RUN_LOOP := 0.62
## Hip tilts forward into the run (deg); the legs are counter-rotated so they keep
## their stride. The torso bends on top of that (RUN_LEAN_BASE, relative to the hip)
## and crunches a little more each time a foot lands (RUN_TORSO_CRUNCH deg per px of bob).
const RUN_PELVIS_TILT := 9.0
const RUN_TORSO_CRUNCH := 1.0
const RUN_LEAN_BASE := 9.0
const RUN_LEAN_SWAY := 0.5
## Hip rock with the stride (deg at full front stride). The legs ride on the hip, so the
## thigh table is a bit smaller than the on-screen stride (about -40..+34 deg).
const RUN_PELVIS_ROT := 5.0
const RUN_THIGH_R := [-35.0, -24.0, -7.0, 13.0, 29.0, 11.0, -20.0, -37.0]
const RUN_KNEE_R := [10.0, 14.0, 12.0, 8.0, 18.0, 70.0, 88.0, 40.0]
const RUN_FOOT_R := [-8.0, 0.0, 0.0, 10.0, 22.0, 18.0, 4.0, -10.0]
const RUN_BOB_TABLE := [0.1, 0.25, 0.15, 0.0, 0.1, 0.25, 0.15, 0.0]
## Near (sword) arm pump, far (buckler) arm swing, far forearm bend (deg).
const RUN_SWORD_ARM_AMP := 18.0
## How much the blade itself sways with the arm swing (deg, world).
const RUN_SWORD_SWAY := 6.0
const RUN_FAR_ARM_AMP := 12.0
const RUN_FAR_FOREARM := -22.0
## Multiplier on the stride-derived run speed, if the feet look like they slide.
const RUN_SPEED_SCALE := 1.0

var _rig: CharacterRig


func _init(rig: CharacterRig) -> void:
	_rig = rig


## Returns a library with "idle", "walk" and one clip per AttackData (named by its id).
func build_library(attacks: Array[AttackData]) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _make_idle_animation())
	library.add_animation("walk", _make_walk_animation())
	library.add_animation("run", _make_run_animation())
	for attack in attacks:
		library.add_animation(attack.id, _make_attack_animation(attack))
	return library


func _make_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = IDLE_LOOP
	animation.loop_mode = Animation.LOOP_LINEAR

	var times: Array = [0.0, IDLE_LOOP * 0.25, IDLE_LOOP * 0.5, IDLE_LOOP * 0.75, IDLE_LOOP]
	var bob_values: Array = [0.0, -IDLE_BOB, 0.0, IDLE_BOB, 0.0]
	var scale_y_values: Array = [1.0, 1.0, 1.0, 1.0, 1.0]
	var lean_values: Array = [IDLE_LEAN, IDLE_LEAN + 0.5, IDLE_LEAN, IDLE_LEAN - 0.5, IDLE_LEAN]
	var arm_l_values: Array = [0.0, 1.4, 0.0, -1.4, 0.0]
	var arm_r_sway: Array = [0.0, -1.1, 0.0, 1.1, 0.0]
	var forearm_l_values: Array = [-1.0, 0.9, -1.0, -2.9, -1.0]
	var forearm_r_sway: Array = [0.0, -1.6, 0.0, 1.6, 0.0]
	var upper_arm_r_values: Array = []
	var forearm_r_values: Array = []
	var hand_r_values: Array = []
	var sword_values: Array = []

	var square_l: Array = _leg_square_offsets("thigh_l", "shin_l")
	var square_r: Array = _leg_square_offsets("thigh_r", "shin_r")

	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
	var shin_l_rot: Array = []
	var shin_r_rot: Array = []
	var foot_l_rot: Array = []
	var foot_r_rot: Array = []
	var torso_rot: Array = []
	var pelvis_rot: Array = []
	var pelvis_pos: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var torso_scale: Array = []
	var thigh_l_scale: Array = []
	var thigh_r_scale: Array = []
	var pelvis_rest: Vector2 = _rig.rest_position["pelvis"]
	var head_rest: Vector2 = _rig.rest_position["head"]

	for i in range(times.size()):
		var breath := float(bob_values[i])
		var body_offset := IDLE_COMPRESSION + breath
		var lean := clampf(float(lean_values[i]), -MAX_TORSO_LEAN, MAX_TORSO_LEAN)
		var pelvis_angle := 0.0
		var thigh_walk_l := 0.0
		var knee_l := 0.0
		var thigh_walk_r := 0.0
		var knee_r := 0.0
		var scale_y := float(scale_y_values[i])

		thigh_l_rot.append(float(square_l[0]) + thigh_walk_l)
		shin_l_rot.append(float(square_l[1]) + knee_l)
		foot_l_rot.append(float(square_l[2]) - thigh_walk_l - knee_l)
		thigh_r_rot.append(float(square_r[0]) + thigh_walk_r)
		shin_r_rot.append(float(square_r[1]) + knee_r)
		foot_r_rot.append(float(square_r[2]) - thigh_walk_r - knee_r)

		var guard_upper := GUARD_UPPER_ARM_R + float(arm_r_sway[i])
		var guard_forearm := GUARD_FOREARM_R + float(forearm_r_sway[i])
		var guard_sword := GUARD_SWORD_WORLD + sin(TAU * float(i) / 4.0)
		upper_arm_r_values.append(guard_upper)
		forearm_r_values.append(guard_forearm)
		hand_r_values.append(GUARD_HAND_R)
		sword_values.append(_guard_sword_offset(
			lean, pelvis_angle, guard_upper, guard_forearm, GUARD_HAND_R, guard_sword
		))

		torso_rot.append(lean)
		pelvis_rot.append(pelvis_angle)
		pelvis_pos.append(pelvis_rest + Vector2(0.0, body_offset))
		torso_scale.append(Vector2(1.0, scale_y))
		thigh_l_scale.append(Vector2(1.0, 1.0 / scale_y))
		thigh_r_scale.append(Vector2(1.0, 1.0 / scale_y))
		head_rot.append(-lean - pelvis_angle - HEAD_LOOK_UP + 0.35 * sin(TAU * float(i) / 4.0))
		head_pos.append(head_rest + Vector2(0.0, -HEAD_BOB_COUNTER * breath))

	_add_rotation_track(animation, "torso", times, torso_rot)
	_add_rotation_track(animation, "pelvis", times, pelvis_rot)
	_add_rotation_track(animation, "head", times, head_rot)
	_add_rotation_track(animation, "thigh_l", times, thigh_l_rot)
	_add_rotation_track(animation, "thigh_r", times, thigh_r_rot)
	_add_rotation_track(animation, "shin_l", times, shin_l_rot)
	_add_rotation_track(animation, "shin_r", times, shin_r_rot)
	_add_rotation_track(animation, "foot_l", times, foot_l_rot)
	_add_rotation_track(animation, "foot_r", times, foot_r_rot)
	_add_rotation_track(animation, "upper_arm_l", times, arm_l_values)
	_add_rotation_track(animation, "upper_arm_r", times, upper_arm_r_values)
	_add_rotation_track(animation, "forearm_l", times, forearm_l_values)
	_add_rotation_track(animation, "forearm_r", times, forearm_r_values)
	_add_rotation_track(animation, "hand_r", times, hand_r_values)
	_add_rotation_track(animation, "sword", times, sword_values)
	_add_position_track(animation, "pelvis", times, pelvis_pos)
	_add_position_track(animation, "head", times, head_pos)
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
	var pelvis_rot: Array = []
	var pelvis_pos: Array = []
	var torso_scale: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
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
	var hand_r: Array = []
	var sword_rot: Array = []

	var square_l: Array = _leg_square_offsets("thigh_l", "shin_l")
	var square_r: Array = _leg_square_offsets("thigh_r", "shin_r")
	var pelvis_rest: Vector2 = _rig.rest_position["pelvis"]
	var head_rest: Vector2 = _rig.rest_position["head"]

	for i in range(WALK_KEY_COUNT + 1):
		var idx := i % WALK_KEY_COUNT
		var phase := TAU * float(idx) / float(WALK_KEY_COUNT)
		var right_idx := idx
		var left_idx := (idx + 4) % WALK_KEY_COUNT
		var thigh_walk_r := float(WALK_THIGH_R[right_idx])
		var knee_r := float(WALK_KNEE_R[right_idx])
		var foot_r_angle := float(WALK_FOOT_R[right_idx])
		var thigh_walk_l := float(WALK_THIGH_R[left_idx])
		var knee_l := float(WALK_KNEE_R[left_idx])
		var foot_l_angle := float(WALK_FOOT_R[left_idx])
		var lean := clampf(WALK_LEAN_BASE + WALK_LEAN_SWAY * sin(phase), -MAX_TORSO_LEAN, MAX_TORSO_LEAN)
		var pelvis_angle := _pelvis_walk_angle(thigh_walk_r)
		var torso_angle := clampf(lean - pelvis_angle, -MAX_TORSO_LEAN, MAX_TORSO_LEAN)
		var bob := float(WALK_BOB_TABLE[idx])
		var arm_swing := WALK_ARM_AMP * cos(phase)

		times.append(WALK_LOOP * float(i) / float(WALK_KEY_COUNT))
		torso_rot.append(torso_angle)
		pelvis_rot.append(pelvis_angle)
		pelvis_pos.append(pelvis_rest + Vector2(0.0, bob))
		torso_scale.append(Vector2.ONE)
		head_rot.append(-torso_angle - pelvis_angle - HEAD_LOOK_UP + 0.4 * sin(phase * 2.0))
		head_pos.append(head_rest + Vector2(0.0, -HEAD_BOB_COUNTER * bob))

		thigh_l_rot.append(float(square_l[0]) + thigh_walk_l)
		thigh_r_rot.append(float(square_r[0]) + thigh_walk_r)
		thigh_l_scale.append(Vector2.ONE)
		thigh_r_scale.append(Vector2.ONE)
		shin_l_rot.append(float(square_l[1]) + knee_l)
		shin_r_rot.append(float(square_r[1]) + knee_r)
		foot_l_rot.append(float(square_l[2]) - thigh_walk_l - knee_l + foot_l_angle)
		foot_r_rot.append(float(square_r[2]) - thigh_walk_r - knee_r + foot_r_angle)

		var guard_upper := GUARD_UPPER_ARM_R + 2.0 * sin(phase)
		var guard_forearm := GUARD_FOREARM_R - 1.5 * sin(phase)
		var guard_sword := GUARD_SWORD_WORLD + 1.5 * cos(phase)
		arm_l.append(-arm_swing)
		arm_r.append(guard_upper)
		forearm_l.append(-6.0 + 4.0 * sin(phase))
		forearm_r.append(guard_forearm)
		hand_r.append(GUARD_HAND_R)
		sword_rot.append(_guard_sword_offset(
			torso_angle, pelvis_angle, guard_upper, guard_forearm, GUARD_HAND_R, guard_sword
		))

	_add_rotation_track(animation, "torso", times, torso_rot)
	_add_rotation_track(animation, "pelvis", times, pelvis_rot)
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
	_add_rotation_track(animation, "hand_r", times, hand_r)
	_add_rotation_track(animation, "sword", times, sword_rot)
	_add_position_track(animation, "pelvis", times, pelvis_pos)
	_add_position_track(animation, "head", times, head_pos)
	_add_scale_track(animation, "torso", times, torso_scale)
	_add_scale_track(animation, "thigh_l", times, thigh_l_scale)
	_add_scale_track(animation, "thigh_r", times, thigh_r_scale)
	return animation


func _make_run_animation() -> Animation:
	var animation := Animation.new()
	animation.length = RUN_LOOP
	animation.loop_mode = Animation.LOOP_LINEAR

	var times: Array = []
	var torso_rot: Array = []
	var pelvis_rot: Array = []
	var pelvis_pos: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
	var shin_l_rot: Array = []
	var shin_r_rot: Array = []
	var foot_l_rot: Array = []
	var foot_r_rot: Array = []
	var arm_l: Array = []
	var arm_r: Array = []
	var forearm_l: Array = []
	var forearm_r: Array = []
	var hand_r: Array = []
	var sword_rot: Array = []
	var ones: Array = []

	var square_l: Array = _leg_square_offsets("thigh_l", "shin_l")
	var square_r: Array = _leg_square_offsets("thigh_r", "shin_r")
	var pelvis_rest: Vector2 = _rig.rest_position["pelvis"]
	var head_rest: Vector2 = _rig.rest_position["head"]
	var key_count := RUN_THIGH_R.size()

	for i in range(key_count + 1):
		var idx := i % key_count
		var phase := TAU * float(idx) / float(key_count)
		var left_idx := (idx + key_count / 2) % key_count
		var thigh_walk_r := float(RUN_THIGH_R[idx])
		var knee_r := float(RUN_KNEE_R[idx])
		var thigh_walk_l := float(RUN_THIGH_R[left_idx])
		var knee_l := float(RUN_KNEE_R[left_idx])
		var bob := float(RUN_BOB_TABLE[idx])
		var pelvis_swing := RUN_PELVIS_ROT * thigh_walk_r / absf(float(RUN_THIGH_R[0]))
		var pelvis_angle := RUN_PELVIS_TILT + pelvis_swing
		var torso_angle := clampf(
			RUN_LEAN_BASE + RUN_LEAN_SWAY * sin(phase * 2.0) + RUN_TORSO_CRUNCH * maxf(bob, 0.0) - pelvis_swing,
			-MAX_TORSO_LEAN, MAX_TORSO_LEAN
		)
		var thigh_local_r := thigh_walk_r - RUN_PELVIS_TILT
		var thigh_local_l := thigh_walk_l - RUN_PELVIS_TILT
		var swing := cos(phase)

		times.append(RUN_LOOP * float(i) / float(key_count))
		torso_rot.append(torso_angle)
		pelvis_rot.append(pelvis_angle)
		pelvis_pos.append(pelvis_rest + Vector2(0.0, bob))
		head_rot.append(-torso_angle - pelvis_angle - HEAD_LOOK_UP + 0.5 * sin(phase * 2.0))
		head_pos.append(head_rest + Vector2(0.0, -HEAD_BOB_COUNTER * bob))
		ones.append(Vector2.ONE)

		thigh_l_rot.append(float(square_l[0]) + thigh_local_l)
		thigh_r_rot.append(float(square_r[0]) + thigh_local_r)
		shin_l_rot.append(float(square_l[1]) + knee_l)
		shin_r_rot.append(float(square_r[1]) + knee_r)
		foot_l_rot.append(
			float(square_l[2]) - thigh_local_l - knee_l + float(RUN_FOOT_R[left_idx]) - RUN_PELVIS_TILT
		)
		foot_r_rot.append(
			float(square_r[2]) - thigh_local_r - knee_r + float(RUN_FOOT_R[idx]) - RUN_PELVIS_TILT
		)

		# Arms pump opposite to their own-side leg; the sword stays at the guard angle.
		var guard_upper := GUARD_UPPER_ARM_R + RUN_SWORD_ARM_AMP * swing
		var guard_forearm := GUARD_FOREARM_R - 0.5 * RUN_SWORD_ARM_AMP * swing
		arm_l.append(-RUN_FAR_ARM_AMP * swing)
		forearm_l.append(RUN_FAR_FOREARM + 4.0 * sin(phase))
		arm_r.append(guard_upper)
		forearm_r.append(guard_forearm)
		hand_r.append(GUARD_HAND_R)
		sword_rot.append(_guard_sword_offset(
			torso_angle, pelvis_angle, guard_upper, guard_forearm, GUARD_HAND_R,
			GUARD_SWORD_WORLD + RUN_SWORD_SWAY * swing
		))

	_add_rotation_track(animation, "torso", times, torso_rot)
	_add_rotation_track(animation, "pelvis", times, pelvis_rot)
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
	_add_rotation_track(animation, "hand_r", times, hand_r)
	_add_rotation_track(animation, "sword", times, sword_rot)
	_add_position_track(animation, "pelvis", times, pelvis_pos)
	_add_position_track(animation, "head", times, head_pos)
	_add_scale_track(animation, "torso", times, ones)
	_add_scale_track(animation, "thigh_l", times, ones)
	_add_scale_track(animation, "thigh_r", times, ones)
	return animation


# Builds one attack clip from AttackData. Keys are offsets from the guard pose; with
# rigid_sword the blade stays locked to the hand at its guard grip.
func _make_attack_animation(attack: AttackData) -> Animation:
	var length := attack.length
	var keys: Array = attack.keys
	var rigid_sword := attack.rigid_sword
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE

	var times: Array = []
	var torso_rot: Array = []
	var pelvis_rot: Array = []
	var pelvis_pos: Array = []
	var head_rot: Array = []
	var head_pos: Array = []
	var thigh_l_rot: Array = []
	var thigh_r_rot: Array = []
	var shin_l_rot: Array = []
	var shin_r_rot: Array = []
	var foot_l_rot: Array = []
	var foot_r_rot: Array = []
	var arm_l: Array = []
	var forearm_l: Array = []
	var arm_r: Array = []
	var forearm_r: Array = []
	var hand_r: Array = []
	var sword_rot: Array = []
	var ones: Array = []

	var pelvis_rest: Vector2 = _rig.rest_position["pelvis"]
	var head_rest: Vector2 = _rig.rest_position["head"]
	var guard_grip := _guard_sword_offset(
		IDLE_LEAN, 0.0, GUARD_UPPER_ARM_R, GUARD_FOREARM_R, GUARD_HAND_R, GUARD_SWORD_WORLD
	)

	for key in keys:
		var px := float(key["px"])
		var py := float(key["py"])
		var lean := clampf(IDLE_LEAN + float(key["lean"]), -MAX_TORSO_LEAN, MAX_TORSO_LEAN)
		var upper := GUARD_UPPER_ARM_R + float(key["arm"])
		var fore := GUARD_FOREARM_R + float(key["fore"])
		var hand := GUARD_HAND_R + float(key["hand"])
		var leg_l: Array = _planted_leg("thigh_l", "shin_l", px, py)
		var leg_r: Array = _planted_leg("thigh_r", "shin_r", px, py)

		times.append(length * float(key["t"]))
		torso_rot.append(lean)
		pelvis_rot.append(0.0)
		pelvis_pos.append(pelvis_rest + Vector2(px, py))
		head_rot.append(-lean - HEAD_LOOK_UP)
		head_pos.append(head_rest)
		thigh_l_rot.append(leg_l[0])
		shin_l_rot.append(leg_l[1])
		foot_l_rot.append(leg_l[2])
		thigh_r_rot.append(leg_r[0])
		shin_r_rot.append(leg_r[1])
		foot_r_rot.append(leg_r[2])
		arm_l.append(0.5 * float(key["lean"]))
		forearm_l.append(-1.0)
		arm_r.append(upper)
		forearm_r.append(fore)
		hand_r.append(hand)
		if rigid_sword:
			sword_rot.append(guard_grip)
		else:
			sword_rot.append(_guard_sword_offset(
				lean, 0.0, upper, fore, hand, GUARD_SWORD_WORLD + float(key["sword"])
			))
		ones.append(Vector2.ONE)

	_add_rotation_track(animation, "torso", times, torso_rot)
	_add_rotation_track(animation, "pelvis", times, pelvis_rot)
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
	_add_rotation_track(animation, "hand_r", times, hand_r)
	_add_rotation_track(animation, "sword", times, sword_rot)
	_add_position_track(animation, "pelvis", times, pelvis_pos)
	_add_position_track(animation, "head", times, head_pos)
	_add_scale_track(animation, "torso", times, ones)
	_add_scale_track(animation, "thigh_l", times, ones)
	_add_scale_track(animation, "thigh_r", times, ones)
	return animation


# Two-bone IK: keeps the ankle where it is in the guard stance while the hip moves
# by (dx, dy). Returns [thigh, shin, foot] rotation offsets; the foot stays flat.
func _planted_leg(thigh_name: String, shin_name: String, dx: float, dy: float) -> Array:
	var metrics: Array = _leg_metrics(thigh_name, shin_name)
	var a := float(metrics[0])
	var b := float(metrics[1])
	var square: Array = _leg_square_offsets(thigh_name, shin_name)
	var target := Vector2(-dx, a + b - dy)
	var reach := clampf(target.length(), absf(a - b) + 0.001, a + b)
	var cos_knee := clampf((reach * reach - a * a - b * b) / (2.0 * a * b), -1.0, 1.0)
	var knee := acos(cos_knee)
	var target_angle := atan2(-target.x, target.y)
	var thigh := target_angle - atan2(b * sin(knee), a + b * cos(knee))
	var thigh_deg := rad_to_deg(thigh)
	var knee_deg := rad_to_deg(knee)
	return [
		float(square[0]) + thigh_deg,
		float(square[1]) + knee_deg,
		float(square[2]) - thigh_deg - knee_deg,
	]


func _leg_metrics(thigh_name: String, shin_name: String) -> Array:
	var a := _rig.joint_vector(thigh_name, "knee").length()
	var b := _rig.joint_vector(shin_name, "ankle").length()
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


func _pelvis_walk_angle(thigh_walk_deg: float) -> float:
	return WALK_PELVIS_ROT * thigh_walk_deg / absf(float(WALK_THIGH_R[0]))


func compute_walk_speed() -> float:
	var metrics_l: Array = _leg_metrics("thigh_l", "shin_l")
	var metrics_r: Array = _leg_metrics("thigh_r", "shin_r")
	var front_pelvis := _pelvis_walk_angle(float(WALK_THIGH_R[0]))
	var back_pelvis := _pelvis_walk_angle(float(WALK_THIGH_R[4]))
	var right_front := _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]),
		float(WALK_THIGH_R[0]) + front_pelvis, float(WALK_KNEE_R[0])
	)
	var right_back := _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]),
		float(WALK_THIGH_R[4]) + back_pelvis, float(WALK_KNEE_R[4])
	)
	var left_front := _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]),
		float(WALK_THIGH_R[0]) + back_pelvis, float(WALK_KNEE_R[0])
	)
	var left_back := _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]),
		float(WALK_THIGH_R[4]) + front_pelvis, float(WALK_KNEE_R[4])
	)
	var step := ((right_front - right_back) + (left_front - left_back)) * 0.5
	return step * _rig.base_scale * 2.0 / WALK_LOOP


## Ground speed (px/s) that matches the run stride, same method as the walk.
func compute_run_speed() -> float:
	var metrics_l: Array = _leg_metrics("thigh_l", "shin_l")
	var metrics_r: Array = _leg_metrics("thigh_r", "shin_r")
	var front := float(RUN_THIGH_R[0])
	var back := float(RUN_THIGH_R[4])
	var front_pelvis := RUN_PELVIS_ROT * front / absf(front)
	var back_pelvis := RUN_PELVIS_ROT * back / absf(front)
	var right_step := _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]), front + front_pelvis, float(RUN_KNEE_R[0])
	) - _ankle_forward_offset(
		float(metrics_r[0]), float(metrics_r[1]), back + back_pelvis, float(RUN_KNEE_R[4])
	)
	var left_step := _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]), front + back_pelvis, float(RUN_KNEE_R[0])
	) - _ankle_forward_offset(
		float(metrics_l[0]), float(metrics_l[1]), back + front_pelvis, float(RUN_KNEE_R[4])
	)
	var step := (right_step + left_step) * 0.5
	return step * _rig.base_scale * 2.0 / RUN_LOOP * RUN_SPEED_SCALE


func _leg_square_offsets(thigh_name: String, shin_name: String) -> Array:
	var thigh_offset := 90.0 - _joint_world_angle(thigh_name, "knee")
	var shin_offset := 90.0 - (_joint_world_angle(shin_name, "ankle") + thigh_offset)
	var foot_offset := -(thigh_offset + shin_offset)
	return [thigh_offset, shin_offset, foot_offset]


func _joint_world_angle(part_name: String, joint_name: String) -> float:
	var part_data: Dictionary = _rig.parts[part_name]
	var offset := _rig.joint_vector(part_name, joint_name)
	offset = offset.rotated(deg_to_rad(float(part_data["rest_rotation_world_deg"])))
	return rad_to_deg(atan2(offset.y, offset.x))


func _guard_sword_offset(
	lean: float, pelvis_rot: float, upper_off: float, forearm_off: float, hand_off: float, target_world: float
) -> float:
	var rest_sum := 0.0
	for part_name in ["upper_arm_r", "forearm_r", "hand_r", "sword"]:
		rest_sum += float(_rig.rest_rotation_deg[part_name])
	return target_world - (pelvis_rot + lean + rest_sum + upper_off + forearm_off + hand_off)




func _add_rotation_track(animation: Animation, part_name: String, times: Array, offsets_deg: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:rotation" % _rig.part_path(part_name)))
	var rest := float(_rig.rest_rotation_deg[part_name])
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], deg_to_rad(rest + offsets_deg[i]))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)


func _add_position_track(animation: Animation, part_name: String, times: Array, positions: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:position" % _rig.part_path(part_name)))
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], positions[i])
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)


func _add_scale_track(animation: Animation, part_name: String, times: Array, scales: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:scale" % _rig.part_path(part_name)))
	for i in range(times.size()):
		animation.track_insert_key(track, times[i], scales[i])
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	animation.track_set_interpolation_loop_wrap(track, true)
