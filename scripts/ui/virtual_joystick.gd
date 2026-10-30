class_name HudJoystick
extends Control
## On-screen movement stick. The frame and knob are TextureRects created from the
## exported art, and dragging the knob emits an analog direction in [-1, 1].

@export var frame_texture: Texture2D
@export var knob_texture: Texture2D
## Knob diameter as a fraction of the smaller control dimension.
@export_range(0.1, 0.8, 0.01) var knob_ratio := 0.36
## Fraction of the travel radius ignored around the center.
@export_range(0.0, 0.8, 0.01) var deadzone := 0.15
## Gap between the knob's travel edge and the frame edge.
@export var edge_padding := 8.0

## Current stick direction. Length is 0 at rest and 1 at the travel limit.
var direction := Vector2.ZERO

var frame: TextureRect
var knob: TextureRect

var _dragging := false
var _active_touch := -1
var _knob_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	_ensure_visuals()
	_update_visuals()
	reset()


## Updates the stick from a local control-space position. Public so tests and
## other input sources can drive the same deadzone/clamping behavior.
func update_from_local(local_position: Vector2) -> void:
	_ensure_visuals()
	var center := size * 0.5
	var offset := local_position - center
	var radius := _travel_radius()
	var dead := radius * deadzone
	var length := offset.length()
	if length <= dead:
		direction = Vector2.ZERO
		_knob_offset = Vector2.ZERO
	else:
		var strength := clampf((length - dead) / maxf(1.0, radius - dead), 0.0, 1.0)
		direction = offset.normalized() * strength
		_knob_offset = offset.normalized() * minf(length, radius)
	_apply_knob_position()


## Centers the stick and clears its direction.
func reset() -> void:
	direction = Vector2.ZERO
	_knob_offset = Vector2.ZERO
	_dragging = false
	_active_touch = -1
	_apply_knob_position()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _dragging and get_global_rect().has_point(event.position):
				_dragging = true
				_active_touch = event.index
				update_from_local(event.position - global_position)
				get_viewport().set_input_as_handled()
		elif event.index == _active_touch:
			reset()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		if event.index == _active_touch:
			update_from_local(event.position - global_position)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _dragging and get_global_rect().has_point(event.position):
				_dragging = true
				update_from_local(event.position - global_position)
				get_viewport().set_input_as_handled()
		elif _dragging:
			reset()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _dragging:
		update_from_local(event.position - global_position)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()


func _on_resized() -> void:
	_update_visuals()


func _ensure_visuals() -> void:
	if frame == null:
		frame = get_node_or_null("Frame") as TextureRect
		if frame == null:
			frame = TextureRect.new()
			frame.name = "Frame"
			add_child(frame)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.texture = frame_texture

	if knob == null:
		knob = get_node_or_null("Knob") as TextureRect
		if knob == null:
			knob = TextureRect.new()
			knob.name = "Knob"
			add_child(knob)
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		knob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		knob.texture = knob_texture


func _update_visuals() -> void:
	_ensure_visuals()
	if frame == null or knob == null:
		return
	frame.position = Vector2.ZERO
	frame.size = size
	var diameter := maxf(1.0, minf(size.x, size.y) * knob_ratio)
	knob.size = Vector2(diameter, diameter)
	_apply_knob_position()


func _apply_knob_position() -> void:
	if knob == null:
		return
	knob.position = size * 0.5 + _knob_offset - knob.size * 0.5


func _travel_radius() -> float:
	var diameter := knob.size.x if knob != null else 0.0
	return maxf(1.0, minf(size.x, size.y) * 0.5 - diameter * 0.5 - edge_padding)
