class_name RigEditor
extends Node2D
## Visual editor for a cut-out rig. Open scenes/tests/rig_editor.tscn and press F6.
## Drag a yellow pivot to move that bone. Shift+drag slides the sprite on the bone.
## Drag a cyan socket to move a joint; the child hung on that socket follows.
## Q/E rotates the selection, arrows nudge it, [ ] changes draw order.
## Space plays the selected clip. Ctrl+S writes pivots.json.

const THEME := preload("res://themes/cinzel_dark_theme.tres")
const DEFAULT_CONFIG := preload("res://resources/characters/warrior.tres")
const BONE_COLOR := Color(0.93, 0.78, 0.42, 0.95)
const JOINT_COLOR := Color(0.45, 0.86, 0.95, 0.95)
const SELECT_COLOR := Color(1.0, 0.95, 0.62, 1.0)
const HIT_RADIUS := 18.0

@export var config: CharacterData

var editor_scale := 5.0
var rig: CharacterRig

var _doc: Dictionary = {}
var _skeleton: Skeleton2D
var _overlay: HandleOverlay
var _textures: Dictionary = {}
var _pan := Vector2.ZERO
var _selected := "torso"
var _selected_joint := ""
var _dirty := false
var _undo: Array[Dictionary] = []
var _drag_kind := ""
var _drag_part := ""
var _drag_joint := ""
var _drag_start_mouse := Vector2.ZERO
var _drag_start_global := Vector2.ZERO
var _drag_start_doc: Dictionary = {}
var _drag_moved := false
var _panning := false
var _status: Label
var _part_list: ItemList
var _anim_player: AnimationPlayer
var _clip_button: OptionButton
var _play_button: Button
var _time_slider: HSlider
var _time_label: Label
var _seeking := false
var _ignore_slider := false


func _ready() -> void:
	if config == null:
		config = DEFAULT_CONFIG
	_build_chrome()
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton2D"
	add_child(_skeleton)
	_overlay = HandleOverlay.new()
	_overlay.name = "Handles"
	_overlay.z_index = 100
	add_child(_overlay)
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	_anim_player.process_priority = -10
	add_child(_anim_player)
	rig = CharacterRig.new(config, _skeleton)
	_load_from_disk()
	_place_view()
	get_viewport().size_changed.connect(_place_view)
	_select_part(_selected if _parts().has(_selected) else _root_part())


func _process(_delta: float) -> void:
	if _anim_player == null or not _anim_player.is_playing():
		return
	if not _seeking:
		_sync_slider()
	if _overlay != null:
		_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.ctrl_pressed:
			_zoom(1.1)
		else:
			_rotate_selected(-1.0 if not event.shift_pressed else -5.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.ctrl_pressed:
			_zoom(1.0 / 1.1)
		else:
			_rotate_selected(1.0 if not event.shift_pressed else 5.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_panning = event.pressed
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position, event.shift_pressed)
		else:
			_end_drag()
		return
	if event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			_place_view()
			_overlay.queue_redraw()
		elif _drag_kind != "":
			_apply_drag(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func draw_handles(canvas: Node2D) -> void:
	if rig == null:
		return
	var font := ThemeDB.fallback_font
	for part_name in rig.parts.keys():
		var bone: Bone2D = rig.bones.get(part_name)
		if bone == null:
			continue
		var at := canvas.to_local(bone.global_position)
		var parent := bone.get_parent()
		if parent is Bone2D:
			canvas.draw_line(canvas.to_local(parent.global_position), at, Color(BONE_COLOR, 0.55), 2.0)
		var selected := str(part_name) == _selected
		canvas.draw_circle(at, 8.0 if selected else 4.5, SELECT_COLOR if selected else BONE_COLOR)
		if selected:
			canvas.draw_string(font, at + Vector2(10, -10), str(part_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, SELECT_COLOR)
			var joints: Dictionary = rig.parts[part_name].get("joints", {})
			for joint_name in joints.keys():
				var joint_at := canvas.to_local(_joint_global(str(part_name), str(joint_name)))
				var joint_selected := str(joint_name) == _selected_joint
				canvas.draw_line(at, joint_at, Color(JOINT_COLOR, 0.45), 1.5)
				canvas.draw_circle(joint_at, 7.0 if joint_selected else 5.0, Color.WHITE if joint_selected else JOINT_COLOR)
				canvas.draw_string(font, joint_at + Vector2(8, 4), str(joint_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, JOINT_COLOR)


func _build_chrome() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.layer = -10
	var background := ColorRect.new()
	background.color = Color(0.025, 0.03, 0.045)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)
	add_child(background_layer)

	var ui := CanvasLayer.new()
	ui.layer = 10
	var panel := PanelContainer.new()
	panel.theme = THEME
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -380.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Rig editor"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	box.add_child(_status)

	_part_list = ItemList.new()
	_part_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_part_list.custom_minimum_size = Vector2(0, 240)
	_part_list.focus_mode = Control.FOCUS_NONE
	_part_list.item_selected.connect(_on_part_selected)
	box.add_child(_part_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(_make_button("Save", _save))
	buttons.add_child(_make_button("Reload", _load_from_disk))
	buttons.add_child(_make_button("Back", _back))

	var order_buttons := HBoxContainer.new()
	order_buttons.add_theme_constant_override("separation", 8)
	box.add_child(order_buttons)
	order_buttons.add_child(_make_button("Behind", func() -> void: _nudge_index(false)))
	order_buttons.add_child(_make_button("In front", func() -> void: _nudge_index(true)))

	_build_preview(ui)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.text = "Yellow point: move the bone. Shift+drag it: slide the art on the bone. Cyan point: move a socket, and the part hung there follows.\nThe list is draw order, front at the top. In front / Behind, or [ and ], swaps with the neighbor.\nArrows nudge. Shift+arrows slide the art. Q/E or the wheel rotates. Space plays the selected clip. Right-drag pans. Ctrl+wheel zooms. Ctrl+S saves. Ctrl+Z undoes."
	box.add_child(help)
	add_child(ui)


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _build_preview(layer: CanvasLayer) -> void:
	var bar := PanelContainer.new()
	bar.theme = THEME
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 16.0
	bar.offset_top = -132.0
	bar.offset_right = -400.0
	bar.offset_bottom = -16.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	bar.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	_clip_button = OptionButton.new()
	_clip_button.focus_mode = Control.FOCUS_NONE
	_clip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip_button.item_selected.connect(func(_index: int) -> void:
		_hold_rest_pose()
		_sync_slider_range()
	)
	row.add_child(_clip_button)

	_play_button = _make_button("Play", _toggle_playback)
	_play_button.custom_minimum_size = Vector2(110, 0)
	row.add_child(_play_button)
	var rest := _make_button("Rest", _hold_rest_pose)
	rest.custom_minimum_size = Vector2(110, 0)
	row.add_child(rest)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	box.add_child(time_row)
	_time_slider = HSlider.new()
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.min_value = 0.0
	_time_slider.max_value = 1.0
	_time_slider.step = 0.01
	_time_slider.drag_started.connect(func() -> void: _seeking = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _seeking = false)
	_time_slider.value_changed.connect(_on_seek)
	time_row.add_child(_time_slider)
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(92, 0)
	_time_label.text = "0.00s"
	time_row.add_child(_time_label)


func _root_part() -> String:
	for part_name in _parts().keys():
		if _parts()[part_name].get("parent") == null:
			return str(part_name)
	if _parts().is_empty():
		return ""
	return str(_parts().keys()[0])


func _rebuild_animation_library() -> void:
	if _anim_player == null or rig == null or rig.parts.is_empty():
		return
	var playing := _anim_player.is_playing()
	var clip := _selected_clip()
	var time := _anim_player.current_animation_position if playing else 0.0
	_anim_player.stop(true)
	if _anim_player.has_animation_library(&""):
		_anim_player.remove_animation_library(&"")
	var animations := WarriorSideAnimations.new(rig)
	_anim_player.add_animation_library(&"", animations.build_library(config.attacks))
	_fill_clips(clip)
	if playing and _anim_player.has_animation(clip):
		_anim_player.play(clip)
		_anim_player.seek(time, true)
		_play_button.text = "Pause"
	else:
		_play_button.text = "Play"
		_sync_slider_range()


func _fill_clips(preferred: String) -> void:
	if _clip_button == null or _anim_player == null:
		return
	_clip_button.clear()
	var names := _anim_player.get_animation_list()
	for clip_name in names:
		_clip_button.add_item(clip_name)
	var index := names.find(preferred)
	if index < 0:
		index = names.find("idle")
	_clip_button.select(0 if index < 0 else index)


func _selected_clip() -> String:
	if _clip_button == null or _clip_button.item_count == 0:
		return ""
	return _clip_button.get_item_text(_clip_button.selected)


func _toggle_playback() -> void:
	var clip := _selected_clip()
	if clip == "" or _anim_player == null:
		return
	if _anim_player.is_playing() and _anim_player.current_animation == clip:
		_anim_player.pause()
		_play_button.text = "Play"
		return
	if _anim_player.assigned_animation == clip and not _anim_player.is_playing():
		_anim_player.play()
	else:
		_anim_player.play(clip)
	_play_button.text = "Pause"
	_sync_slider_range()


func _hold_rest_pose() -> void:
	if _anim_player != null:
		_anim_player.stop(true)
	if _play_button != null:
		_play_button.text = "Play"
	if rig == null:
		return
	for part_name in rig.bones.keys():
		var bone: Bone2D = rig.bones[part_name]
		bone.position = rig.rest_position[part_name]
		bone.rotation = deg_to_rad(float(rig.rest_rotation_deg[part_name]))
	_sync_slider()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_seek(value: float) -> void:
	if _ignore_slider or _anim_player == null:
		return
	var clip := _selected_clip()
	if clip == "":
		return
	if _anim_player.current_animation != clip:
		_anim_player.play(clip)
		_anim_player.pause()
		_play_button.text = "Play"
	_anim_player.seek(value, true)
	_sync_time_label(value)
	if _overlay != null:
		_overlay.queue_redraw()


func _sync_slider() -> void:
	if _time_slider == null or _anim_player == null:
		return
	_sync_slider_range()
	var time := 0.0
	if _anim_player.is_playing() or _anim_player.assigned_animation != &"":
		time = _anim_player.current_animation_position
	_time_slider.set_value_no_signal(time)
	_sync_time_label(time)


func _sync_slider_range() -> void:
	if _time_slider == null or _anim_player == null:
		return
	var clip := _selected_clip()
	var length := 1.0
	if clip != "" and _anim_player.has_animation(clip):
		length = maxf(_anim_player.get_animation(clip).length, 0.01)
	_ignore_slider = true
	_time_slider.max_value = length
	_ignore_slider = false


func _sync_time_label(time: float) -> void:
	if _time_label == null:
		return
	_time_label.text = "%.2fs" % time


func _load_from_disk() -> void:
	_textures.clear()
	_undo.clear()
	_dirty = false
	var text := FileAccess.get_file_as_string(config.pivots_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Could not read %s" % config.pivots_path)
		return
	_set_doc(parsed)
	# The game paints with CharacterData.draw_order. Keep the working copy on that order
	# so Save writes the indexes you see, not the older numbers in the pivot file.
	for part_name in _parts().keys():
		if config.draw_order.has(part_name):
			_parts()[part_name]["z_index"] = int(config.draw_order[part_name])
	_fill_part_list()


func _fill_part_list() -> void:
	if _part_list == null:
		return
	_part_list.clear()
	for part_name in _stacked_parts():
		_part_list.add_item("%d  %s" % [_index_of(part_name), part_name])
		_part_list.set_item_metadata(_part_list.item_count - 1, part_name)
	var fallback := _selected if _parts().has(_selected) else str(_parts().keys()[0])
	_select_part(fallback)


func _set_doc(doc: Dictionary) -> void:
	_doc = doc
	rig.parts = _parts()
	rig.rebuild()
	_apply_textures()
	if _drag_kind == "":
		_rebuild_animation_library()
	_refresh_status()
	if _overlay != null:
		_overlay.queue_redraw()


func _parts() -> Dictionary:
	return _doc.get("parts", {})


func _apply_textures() -> void:
	for part_name in _parts().keys():
		var bone: Bone2D = rig.bones.get(part_name)
		if bone == null:
			continue
		var sprite := bone.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var file_name: Variant = _parts()[part_name].get("file")
		if file_name == null:
			continue
		var texture := _texture_for(str(file_name))
		if texture != null:
			sprite.texture = texture


func _texture_for(file_name: String) -> Texture2D:
	if _textures.has(file_name):
		return _textures[file_name]
	var image := Image.load_from_file(ProjectSettings.globalize_path(config.part_dir + file_name))
	if image == null:
		push_warning("Rig editor could not read %s" % file_name)
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[file_name] = texture
	return texture


func _place_view() -> void:
	if _skeleton == null:
		return
	var view := get_viewport_rect().size
	if view.x < 2.0 or view.y < 2.0:
		view = Vector2(1920, 1080)
	var focus := Vector2(36, 70)
	_skeleton.scale = Vector2.ONE * editor_scale
	_skeleton.position = view * 0.5 - Vector2(170, 0) - focus * editor_scale + _pan
	if _overlay != null:
		_overlay.queue_redraw()


func _zoom(factor: float) -> void:
	editor_scale = clampf(editor_scale * factor, 1.5, 16.0)
	_place_view()


func _begin_drag(screen: Vector2, slide_art: bool) -> void:
	var hit := _closest_handle(screen)
	if hit.is_empty():
		return
	_hold_rest_pose()
	_drag_part = str(hit["part"])
	_drag_joint = str(hit.get("joint", ""))
	_drag_kind = "pivot" if slide_art and str(hit["kind"]) == "bone" else str(hit["kind"])
	_select_part(_drag_part)
	if _drag_kind == "joint":
		_selected_joint = _drag_joint
	_drag_start_mouse = screen
	_drag_start_doc = _doc.duplicate(true)
	_drag_moved = false
	if _drag_kind == "joint":
		_drag_start_global = _joint_global(_drag_part, _drag_joint)
	else:
		_drag_start_global = rig.bones[_drag_part].global_position


func _apply_drag(screen: Vector2) -> void:
	var delta := (screen - _drag_start_mouse) / editor_scale
	delta = Vector2(round(delta.x), round(delta.y))
	_set_doc(_drag_start_doc.duplicate(true))
	if delta == Vector2.ZERO:
		return
	_drag_moved = true
	_dirty = true
	match _drag_kind:
		"pivot":
			_slide_pivot_by(_drag_part, delta)
		"bone":
			_move_bone_to(_drag_part, _drag_start_global + delta * editor_scale)
		"joint":
			_move_joint_to(_drag_part, _drag_joint, _drag_start_global + delta * editor_scale)


func _end_drag() -> void:
	var moved := _drag_moved
	if moved:
		_undo.append(_drag_start_doc)
		if _undo.size() > 40:
			_undo.pop_front()
	_drag_kind = ""
	_drag_moved = false
	if moved:
		_rebuild_animation_library()


func _closest_handle(screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := HIT_RADIUS
	for part_name in rig.parts.keys():
		var bone: Bone2D = rig.bones.get(part_name)
		if bone == null:
			continue
		var distance := screen.distance_to(bone.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = {"kind": "bone", "part": part_name}
		if str(part_name) != _selected:
			continue
		var joints: Dictionary = rig.parts[part_name].get("joints", {})
		for joint_name in joints.keys():
			distance = screen.distance_to(_joint_global(str(part_name), str(joint_name)))
			if distance <= best_distance:
				best_distance = distance
				best = {"kind": "joint", "part": part_name, "joint": str(joint_name)}
	return best


func _joint_global(part_name: String, joint_name: String) -> Vector2:
	var bone: Bone2D = rig.bones[part_name]
	var data: Dictionary = _parts()[part_name]
	var pivot: Array = data["pivot"]
	var joint: Array = data["joints"][joint_name]
	var scale := rig.part_scale(part_name)
	var local := Vector2(
		(float(joint[0]) - float(pivot[0])) * scale.x,
		(float(joint[1]) - float(pivot[1])) * scale.y
	)
	return bone.to_global(local)


func _move_bone_to(part_name: String, global_point: Vector2) -> void:
	var data: Dictionary = _parts()[part_name]
	var parent_name: Variant = data.get("parent")
	if parent_name == null:
		var root_local := _skeleton.to_local(global_point)
		data["pivot_in_rest_canvas"] = [round(root_local.x), round(root_local.y)]
	else:
		var parent_bone: Bone2D = rig.bones[str(parent_name)]
		var local := parent_bone.to_local(global_point)
		if part_name == "thigh_l":
			local.x -= config.far_leg_x_offset
		var scale := rig.part_scale(str(parent_name))
		var parent_pivot: Array = _parts()[str(parent_name)]["pivot"]
		var attach := Vector2(
			local.x / scale.x + float(parent_pivot[0]),
			local.y / scale.y + float(parent_pivot[1])
		)
		attach = Vector2(round(attach.x), round(attach.y))
		data["attach_point_in_parent"] = [attach.x, attach.y]
		var joint_name: Variant = data.get("parent_joint")
		if joint_name != null:
			var joints: Dictionary = _parts()[str(parent_name)].get("joints", {})
			if joints.has(str(joint_name)):
				joints[str(joint_name)] = [attach.x, attach.y]
	_refresh_pose()


func _move_joint_to(part_name: String, joint_name: String, global_point: Vector2) -> void:
	var bone: Bone2D = rig.bones[part_name]
	var local := bone.to_local(global_point)
	var scale := rig.part_scale(part_name)
	var pivot: Array = _parts()[part_name]["pivot"]
	var joint := Vector2(
		local.x / scale.x + float(pivot[0]),
		local.y / scale.y + float(pivot[1])
	)
	joint = Vector2(round(joint.x), round(joint.y))
	_parts()[part_name]["joints"][joint_name] = [joint.x, joint.y]
	for child_name in _parts().keys():
		var child: Dictionary = _parts()[child_name]
		if str(child.get("parent")) == part_name and str(child.get("parent_joint")) == joint_name:
			child["attach_point_in_parent"] = [joint.x, joint.y]
	_refresh_pose()


func _slide_pivot_by(part_name: String, rig_delta: Vector2) -> void:
	var pivot: Array = _parts()[part_name]["pivot"]
	_parts()[part_name]["pivot"] = [
		round(float(pivot[0]) - rig_delta.x),
		round(float(pivot[1]) - rig_delta.y),
	]
	_refresh_pose()


func _refresh_pose() -> void:
	rig.parts = _parts()
	rig.rebuild()
	_apply_textures()
	if _drag_kind == "":
		_rebuild_animation_library()
	_refresh_status()
	if _overlay != null:
		_overlay.queue_redraw()


func _rotate_selected(degrees: float) -> void:
	if not _parts().has(_selected):
		return
	_push_undo()
	var data: Dictionary = _parts()[_selected]
	data["rest_rotation_local_deg"] = int(round(float(data["rest_rotation_local_deg"]) + degrees))
	_dirty = true
	_refresh_pose()


func _nudge_selected(rig_delta: Vector2, slide_art: bool) -> void:
	if not rig.bones.has(_selected) or rig_delta == Vector2.ZERO:
		return
	_push_undo()
	_dirty = true
	if slide_art:
		_slide_pivot_by(_selected, rig_delta)
	else:
		var bone: Bone2D = rig.bones[_selected]
		_move_bone_to(_selected, bone.global_position + rig_delta * editor_scale)


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_S and event.ctrl_pressed:
		_save()
		return
	if event.keycode == KEY_Z and event.ctrl_pressed:
		_undo_once()
		return
	if event.keycode == KEY_SPACE:
		_toggle_playback()
		return
	if event.keycode == KEY_Q:
		_rotate_selected(-1.0 if not event.shift_pressed else -5.0)
		return
	if event.keycode == KEY_E:
		_rotate_selected(1.0 if not event.shift_pressed else 5.0)
		return
	if event.keycode == KEY_BRACKETRIGHT or event.keycode == KEY_PAGEUP:
		_nudge_index(true)
		return
	if event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_PAGEDOWN:
		_nudge_index(false)
		return
	var nudge := Vector2.ZERO
	match event.keycode:
		KEY_LEFT:
			nudge = Vector2(-1, 0)
		KEY_RIGHT:
			nudge = Vector2(1, 0)
		KEY_UP:
			nudge = Vector2(0, -1)
		KEY_DOWN:
			nudge = Vector2(0, 1)
	if nudge != Vector2.ZERO:
		_nudge_selected(nudge, event.shift_pressed)


func _push_undo() -> void:
	_undo.append(_doc.duplicate(true))
	if _undo.size() > 40:
		_undo.pop_front()


func _undo_once() -> void:
	if _undo.is_empty():
		return
	_dirty = true
	_set_doc(_undo.pop_back())
	_copy_indexes_to_draw_order()
	_refresh_pose()
	_fill_part_list()


func _save() -> void:
	if _doc.is_empty():
		return
	_recompute_world_rotations()
	for part_name in _parts().keys():
		var bone: Bone2D = rig.bones.get(part_name)
		if bone == null:
			continue
		var canvas := _skeleton.to_local(bone.global_position)
		var data: Dictionary = _parts()[part_name]
		data["pivot_in_rest_canvas"] = [canvas.x, canvas.y]
		var pivot: Array = data["pivot"]
		data["rest_offset"] = [canvas.x - float(pivot[0]), canvas.y - float(pivot[1])]
		var sprite := bone.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null:
			var size := sprite.texture.get_size()
			data["size"] = [int(size.x), int(size.y)]
	var path := ProjectSettings.globalize_path(config.pivots_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string(JSON.stringify(_doc, "\t", false) + "\n")
	file.close()
	_write_draw_order()
	_dirty = false
	_refresh_status()


func _recompute_world_rotations() -> void:
	for part_name in _parts().keys():
		var world := 0.0
		var current: Variant = part_name
		while current != null and _parts().has(current):
			world += float(_parts()[current]["rest_rotation_local_deg"])
			current = _parts()[current].get("parent")
		_parts()[part_name]["rest_rotation_world_deg"] = world


func _refresh_status() -> void:
	if _status == null or not _parts().has(_selected):
		return
	var data: Dictionary = _parts()[_selected]
	var pivot: Array = data["pivot"]
	var parent: Variant = data.get("parent")
	var parent_text := "root" if parent == null else str(parent)
	var texture_text := "no sprite"
	var bone: Bone2D = rig.bones.get(_selected)
	if bone != null:
		var sprite := bone.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null:
			var size := sprite.texture.get_size()
			texture_text = "texture %d×%d" % [int(size.x), int(size.y)]
			if float(pivot[0]) < 0.0 or float(pivot[1]) < 0.0 or float(pivot[0]) > size.x or float(pivot[1]) > size.y:
				texture_text += " (pivot is outside the sprite)"
	var joint_text := ""
	if _selected_joint != "" and data.get("joints", {}).has(_selected_joint):
		var joint: Array = data["joints"][_selected_joint]
		joint_text = "\nsocket %s (%d, %d)" % [_selected_joint, int(joint[0]), int(joint[1])]
	_status.text = "%s   parent %s\npivot (%d, %d)   rot %d°\ndraw index %d\n%s%s%s" % [
		_selected,
		parent_text,
		int(pivot[0]),
		int(pivot[1]),
		int(data["rest_rotation_local_deg"]),
		_index_of(_selected),
		texture_text,
		joint_text,
		"\nunsaved changes" if _dirty else "",
	]


func _select_part(part_name: String) -> void:
	_selected = part_name
	if _part_list == null:
		return
	_part_list.set_block_signals(true)
	for index in _part_list.item_count:
		if str(_part_list.get_item_metadata(index)) == part_name:
			_part_list.select(index)
			break
	_part_list.set_block_signals(false)
	_refresh_status()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_part_selected(index: int) -> void:
	_selected_joint = ""
	_select_part(str(_part_list.get_item_metadata(index)))


## Higher draw indexes paint in front. Swaps the selection with the next part in that direction.
func _nudge_index(forward: bool) -> void:
	var ordered := _stacked_parts()
	var index := ordered.find(_selected)
	if index < 0:
		return
	var neighbor := index - 1 if forward else index + 1
	if neighbor < 0 or neighbor >= ordered.size():
		return
	_push_undo()
	var other := ordered[neighbor]
	var selected_index := _index_of(_selected)
	var other_index := _index_of(other)
	if selected_index == other_index:
		other_index = selected_index + (1 if forward else -1)
	_set_index(_selected, other_index)
	_set_index(other, selected_index)
	_dirty = true
	_fill_part_list()


func _stacked_parts() -> Array[String]:
	var names: Array[String] = []
	for part_name in _parts().keys():
		var file_name: Variant = _parts()[part_name].get("file")
		if file_name == null or str(file_name) == "":
			continue
		names.append(str(part_name))
	names.sort_custom(func(a: String, b: String) -> bool:
		var index_a := _index_of(a)
		var index_b := _index_of(b)
		if index_a == index_b:
			return a < b
		return index_a > index_b
	)
	return names


func _index_of(part_name: String) -> int:
	if config != null and config.draw_order.has(part_name):
		return int(config.draw_order[part_name])
	if _parts().has(part_name):
		return int(_parts()[part_name].get("z_index", 0))
	return 0


func _set_index(part_name: String, value: int) -> void:
	_parts()[part_name]["z_index"] = value
	if config != null:
		config.draw_order[part_name] = value
	var bone: Bone2D = rig.bones.get(part_name)
	if bone == null:
		return
	var sprite := bone.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.z_index = value


func _copy_indexes_to_draw_order() -> void:
	if config == null:
		return
	for part_name in _parts().keys():
		var file_name: Variant = _parts()[part_name].get("file")
		if file_name == null or str(file_name) == "":
			continue
		config.draw_order[str(part_name)] = int(_parts()[part_name].get("z_index", 0))


func _write_draw_order() -> void:
	if config == null or config.resource_path == "":
		return
	var changed := false
	for part_name in _parts().keys():
		var file_name: Variant = _parts()[part_name].get("file")
		if file_name == null or str(file_name) == "":
			continue
		var value := int(_parts()[part_name].get("z_index", 0))
		if int(config.draw_order.get(part_name, -99999)) != value:
			changed = true
		config.draw_order[str(part_name)] = value
	if not changed:
		return
	var text := FileAccess.get_file_as_string(config.resource_path)
	var start := text.find("draw_order = {")
	var close := text.find("}", start)
	if start < 0 or close < 0:
		push_error("Could not find draw_order in %s" % config.resource_path)
		return
	var names: Array[String] = []
	for part_name in _parts().keys():
		var file_name: Variant = _parts()[part_name].get("file")
		if file_name == null or str(file_name) == "":
			continue
		names.append(str(part_name))
	names.sort()
	var body := "draw_order = {\n"
	for part_name in names:
		body += "\"%s\": %d,\n" % [part_name, int(config.draw_order[part_name])]
	body += "}"
	text = text.substr(0, start) + body + text.substr(close + 1)
	var file := FileAccess.open(ProjectSettings.globalize_path(config.resource_path), FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % config.resource_path)
		return
	file.store_string(text)


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/tests/warrior_rig_test.tscn")


class HandleOverlay extends Node2D:
	func _draw() -> void:
		var editor := get_parent() as RigEditor
		if editor != null:
			editor.draw_handles(self)
