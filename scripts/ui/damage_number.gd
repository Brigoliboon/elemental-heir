extends Node2D
class_name DamageNumber

@onready var label: Label = $Label

func setup(amount: int, color: Color = Color(1.0, 0.3, 0.3)) -> void:
	label.text = str(amount)
	label.modulate = color
	var tween := create_tween()
	tween.tween_property(self, "position", position + Vector2(0, -60), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(queue_free)
