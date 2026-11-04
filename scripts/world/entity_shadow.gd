class_name EntityShadow
extends Node2D

@export var shadow_size := Vector2(80.0, 24.0)
@export_range(0.0, 1.0, 0.01) var opacity := 0.30
@export_range(0.0, 1.0, 0.01) var softness := 0.62

var _texture: GradientTexture2D


func _ready() -> void:
	z_as_relative = true
	z_index = -1
	_build_texture()
	queue_redraw()


func _build_texture() -> void:
	var edge := clampf(softness, 0.01, 0.99)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, edge, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 1.0),
		Color(0.0, 0.0, 0.0, 0.75),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	_texture = GradientTexture2D.new()
	_texture.gradient = gradient
	_texture.width = 128
	_texture.height = 128
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(1.0, 0.5)


func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(
		_texture,
		Rect2(-shadow_size * 0.5, shadow_size),
		false,
		Color(0.0, 0.0, 0.0, opacity)
	)
