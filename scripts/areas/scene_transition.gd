extends Area2D
## Triggers a scene change when the player enters its collision shape.

@export_file("*.tscn") var target_scene := ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if target_scene == "":
		return
	get_tree().change_scene_to_file.call_deferred(target_scene)
