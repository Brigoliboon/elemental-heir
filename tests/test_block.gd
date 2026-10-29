extends RefCounted
## Validates the shield-based block pose: the buckler is forward-facing while the
## sword arm relaxes. Ensures the block animation builds and keys the expected bones.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var packed := load("res://entities/characters/warrior.tscn") as PackedScene
	if packed == null:
		failures.append("warrior.tscn did not load")
		return failures

	var player := packed.instantiate() as Character
	tree.root.add_child(player)
	await tree.process_frame

	if not player.anim_player.has_animation("block"):
		failures.append("player must have a 'block' animation")
		player.queue_free()
		await tree.process_frame
		return failures

	player.block(true)
	await tree.process_frame

	# World-space buckler should be roughly upright (< 20° from vertical).
	var buckler := player.rig.bones.get("buckler") as Bone2D
	if buckler == null:
		failures.append("rig must have a 'buckler' bone")
	else:
		var rot := absf(rad_to_deg(buckler.global_rotation))
		if rot > 20.0:
			failures.append("buckler should stay near upright (%.1f° world rotation)" % rot)

	# Sword arm should drop to its rest pose instead of guarding with the blade.
	var sword := player.rig.bones.get("sword") as Bone2D
	var upper_arm_r := player.rig.bones.get("upper_arm_r") as Bone2D
	if sword == null or upper_arm_r == null:
		failures.append("rig must have sword and upper_arm_r bones")
	else:
		var sword_rot := absf(rad_to_deg(sword.global_rotation))
		var upper_rot := absf(rad_to_deg(upper_arm_r.global_rotation))
		if sword_rot > 60.0 or upper_rot > 20.0:
			failures.append("sword arm should rest low (sword=%.1f°, upper_arm=%.1f°)" % [sword_rot, upper_rot])

	# Shield arm should be folded forward.
	var forearm_l := player.rig.bones.get("forearm_l") as Bone2D
	var hand_l := player.rig.bones.get("hand_l") as Bone2D
	if forearm_l != null and hand_l != null:
		var forearm_rot := rad_to_deg(forearm_l.global_rotation)
		if forearm_rot > -130.0:
			failures.append("forearm_l should be folded forward (%.1f° world)" % forearm_rot)

	# Toggling off returns to idle.
	player.block(false)
	await tree.process_frame
	if player.anim_player.current_animation != "idle":
		failures.append("block(false) must return to idle")

	# After returning to idle, buckler should be back to its rest rotation (upright).
	var buckler := player.rig.bones.get("buckler") as Bone2D
	if buckler != null:
		var rot := absf(rad_to_deg(buckler.global_rotation))
		if rot > 20.0:
			failures.append("buckler should return to upright after block ends (%.1f° world rotation)" % rot)

	player.queue_free()
	await tree.process_frame
	return failures