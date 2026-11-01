extends Node2D
class_name DamageNumber
## Floating damage text that rises off an entity and fades out.
##
## Spawned through `setup()` by the entity that took the hit. The spawner parents
## it to the world rather than to the entity, so a dying mob's corpse fade does
## not take its own last hit marker with it.

## Rise distance and lifetime of one number.
const RISE := 70.0
const LIFETIME := 0.75
## Horizontal spread so rapid hits on the same target do not stack into a blob.
const SPREAD := 14.0

@onready var label: Label = $Label


func setup(amount: int, color: Color = Color(1.0, 0.25, 0.25)) -> void:
	label.text = str(amount)
	label.modulate = color
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)

	# Grow out of the impact point instead of popping in at full size.
	scale = Vector2(0.7, 0.7)
	var drift := randf_range(-SPREAD, SPREAD)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", position + Vector2(drift, -RISE), LIFETIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME * 0.55) \
		.set_delay(LIFETIME * 0.45)
	tween.chain().tween_callback(queue_free)
