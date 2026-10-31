extends Area2D
## Triggers a scene change when the player enters its collision shape.

@export_file("*.tscn") var target_scene := ""

var _armed := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Avoid firing when a scene spawns the player inside this area.
	get_tree().create_timer(0.5).timeout.connect(func(): _armed = true)

func _on_body_entered(body: Node) -> void:
	if not _armed:
		return
	if not body.is_in_group("player"):
		return
	if target_scene == "":
		return
	_armed = false
	get_tree().change_scene_to_file.call_deferred(target_scene)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_armed = true
