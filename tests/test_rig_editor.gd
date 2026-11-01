extends RefCounted
## The rig editor moves bones in memory and leaves pivots.json alone until Save.


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://scenes/tests/rig_editor.tscn") as PackedScene
	if packed == null:
		failures.append("rig_editor.tscn did not load")
		return failures

	var editor := packed.instantiate() as RigEditor
	tree.root.add_child(editor)
	await tree.process_frame

	if editor.rig == null or not editor.rig.bones.has("pelvis"):
		failures.append("rig editor should build the pelvis root")
		editor.queue_free()
		return failures
	var torso_sprite := editor.rig.bones["torso"].get_node_or_null("Sprite") as Sprite2D
	if torso_sprite == null or torso_sprite.texture == null:
		failures.append("rig editor should draw the torso from the png on disk")
	if editor._anim_player == null or not editor._anim_player.has_animation("idle"):
		failures.append("animation preview should include idle")
	elif not editor._anim_player.has_animation("walk") or not editor._anim_player.has_animation("run") or not editor._anim_player.has_animation("block"):
		failures.append("animation preview should include walk, run and block")
	else:
		editor._toggle_playback()
		if not editor._anim_player.is_playing() or editor._anim_player.current_animation != "idle":
			failures.append("animation preview should play the selected clip")
		editor._hold_rest_pose()
		if editor._anim_player.is_playing():
			failures.append("Rest should stop the animation preview")

	var source_before := FileAccess.get_file_as_string(editor.config.pivots_path)
	var order_before := FileAccess.get_file_as_string(editor.config.resource_path)
	var before: Vector2 = editor.rig.rest_position["torso"]
	editor._move_bone_to("torso", editor.rig.bones["torso"].global_position + Vector2(editor.editor_scale * 4.0, 0))
	var after: Vector2 = editor.rig.rest_position["torso"]
	if not is_equal_approx(after.x, before.x + 4.0):
		failures.append("dragging a bone should move it in rig pixels")

	var pivot_before := float(editor._parts()["torso"]["pivot"][0])
	editor._slide_pivot_by("torso", Vector2(2, 0))
	if not is_equal_approx(float(editor._parts()["torso"]["pivot"][0]), pivot_before - 2.0):
		failures.append("sliding the art should move the pivot the other way")

	editor._move_joint_to(
		"torso",
		"shoulder_r",
		editor._joint_global("torso", "shoulder_r") + Vector2(0, editor.editor_scale * 3.0)
	)
	var joint: Array = editor._parts()["torso"]["joints"]["shoulder_r"]
	var attach: Array = editor._parts()["upper_arm_r"]["attach_point_in_parent"]
	if not is_equal_approx(float(attach[0]), float(joint[0])) or not is_equal_approx(float(attach[1]), float(joint[1])):
		failures.append("moving a socket should carry the child attached to it")

	var back_name := ""
	var back_index := 999999
	for part_name in editor._parts().keys():
		var file_name: Variant = editor._parts()[part_name].get("file")
		if file_name == null or str(file_name) == "":
			continue
		var draw_index := editor._index_of(str(part_name))
		if draw_index < back_index:
			back_index = draw_index
			back_name = str(part_name)
	editor._select_part(back_name)
	editor._nudge_index(true)
	if editor._index_of(back_name) <= back_index:
		failures.append("In front should raise the draw index of the rearmost part")
	var stacked_sprite := editor.rig.bones[back_name].get_node_or_null("Sprite") as Sprite2D
	if stacked_sprite == null or stacked_sprite.z_index != editor._index_of(back_name):
		failures.append("sprite z_index should follow the draw index")

	var source_after := FileAccess.get_file_as_string(editor.config.pivots_path)
	if source_before != source_after:
		failures.append("rig editor must not write pivots.json until Save")
	var order_after := FileAccess.get_file_as_string(editor.config.resource_path)
	if order_before != order_after:
		failures.append("rig editor must not write draw_order until Save")

	editor.queue_free()
	await tree.process_frame
	return failures
