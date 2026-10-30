extends Control

const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.0
const ZOOM_STEP := 0.1

@onready var background: TextureRect = $Background
@onready var back_button: Button = $BackButton
@onready var zoom_in: Button = $ZoomControls/ZoomIn
@onready var zoom_out: Button = $ZoomControls/ZoomOut


func _ready() -> void:
	background.scale = Vector2.ONE
	background.pivot_offset = background.size * 0.5
	back_button.pressed.connect(_on_back_pressed)
	zoom_in.pressed.connect(_zoom_in)
	zoom_out.pressed.connect(_zoom_out)


func _zoom_in() -> void:
	background.scale = Vector2.ONE * clampf(background.scale.x + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)


func _zoom_out() -> void:
	background.scale = Vector2.ONE * clampf(background.scale.x - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title/title_screen.tscn")
