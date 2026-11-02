class_name GroundTargetMarker
extends Node2D
## Procedural telegraph for a [GroundTargetSkill]. Draws a pulsing circle exactly
## the size of the impact area, then flashes when the hit lands.

const FLASH_SECONDS := 0.16

## Radius of the impact area in world pixels.
var radius := 160.0
## Base colour. The marker drives alpha so the fill never hides the ground art.
var color := Color(1.0, 0.35, 0.2, 1.0)

var _elapsed := 0.0
var _flash_left := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
	queue_redraw()


## Turns the telegraph into a bright impact flash and frees the node once it ends.
func flash() -> void:
	if _flash_left > 0.0:
		return
	_flash_left = FLASH_SECONDS
	queue_redraw()
	var tree := get_tree()
	if tree != null:
		tree.create_timer(FLASH_SECONDS).timeout.connect(queue_free)


func is_flashing() -> bool:
	return _flash_left > 0.0


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * 1.5)

	var fill := color
	fill.a = 0.08 + 0.07 * pulse
	draw_circle(Vector2.ZERO, radius, fill)

	var ring := color
	ring.a = 0.70 + 0.25 * pulse
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, ring, 3.0, true)

	var inner := color
	inner.a = 0.20 + 0.15 * pulse
	draw_arc(Vector2.ZERO, radius * (0.55 + 0.30 * pulse), 0.0, TAU, 48, inner, 1.5, true)

	if _flash_left > 0.0:
		var t := _flash_left / FLASH_SECONDS
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.95, 0.82, 0.30 * t))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.80 * t), 2.0, true)
