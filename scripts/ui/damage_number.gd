extends Node2D
class_name DamageNumber

@onready var label: Label = $Label

func setup(amount: int, color: Color = Color(1.0, 0.25, 0.25)) -> void:
	label.text = str(amount)
	label.modulate = color
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)
	var tween := create_tween()
	tween.tween_property(self, "position", position + Vector2(0, -70), 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.75)
	tween.tween_callback(queue_free)
