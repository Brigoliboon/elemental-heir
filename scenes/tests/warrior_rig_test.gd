extends Node2D
## Test bench for the warrior side rig: on-screen buttons and keys drive a Character.

const CHARACTER_MARGIN := 130.0

@onready var character: Character = $CharacterRoot
@onready var idle_button: Button = %IdleButton
@onready var walk_button: Button = %WalkButton
@onready var facing_button: Button = %FacingButton
@onready var back_button: Button = %BackButton
@onready var left_button: Button = %LeftButton
@onready var right_button: Button = %RightButton
@onready var attack_button: Button = %AttackButton
@onready var block_button: Button = %BlockButton

var _left_held := false
var _right_held := false


func _ready() -> void:
	idle_button.pressed.connect(character.play_manual.bind("idle"))
	walk_button.pressed.connect(character.play_manual.bind("walk"))
	facing_button.pressed.connect(character.toggle_facing)
	back_button.pressed.connect(_on_back_pressed)
	left_button.button_down.connect(func() -> void: _left_held = true)
	left_button.button_up.connect(func() -> void: _left_held = false)
	right_button.button_down.connect(func() -> void: _right_held = true)
	right_button.button_up.connect(func() -> void: _right_held = false)
	attack_button.pressed.connect(character.attack)
	block_button.button_down.connect(func() -> void: character.block(true))
	block_button.button_up.connect(func() -> void: character.block(false))
	character.facing_changed.connect(_update_facing_label)
	_update_facing_label(character.facing_right)


func _process(delta: float) -> void:
	var direction := 0
	if _left_held or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= 1
	if _right_held or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += 1
	character.move(direction, delta)
	_clamp_character()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_J or event.keycode == KEY_Z:
			if event.pressed:
				character.attack()
		if event.keycode == KEY_K:
			character.block(event.pressed)


func _clamp_character() -> void:
	var viewport_width := get_viewport_rect().size.x
	var limit := maxf(CHARACTER_MARGIN, viewport_width - CHARACTER_MARGIN)
	character.position.x = clampf(character.position.x, CHARACTER_MARGIN, limit)


func _update_facing_label(facing_right: bool) -> void:
	facing_button.text = "Facing: Right" if facing_right else "Facing: Left"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title/title_screen.tscn")
