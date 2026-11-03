class_name Shockwave
extends Node2D
## Short-lived expanding ring used by player area skills.
##
## Drawn procedurally so it needs no texture and can be tinted per skill. The
## shockwave lives in the ground plane: callers place it at the caster's feet and
## give it the same depth ordering as the caster.

## Final radius in world pixels.
var radius := 240.0
## Seconds from the first frame to the last.
var duration := 0.32
var color := Color(1.0, 0.72, 0.35, 1.0)
## Full circle for a shout; two side arcs for a ground slam.
var both_sides := false

var _elapsed := 0.0


func _ready() -> void:
	z_index = DepthSort.z_for_y(global_position.y) - 1
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var current := radius * eased
	var fade := 1.0 - t

	var ring := color
	ring.a = 0.85 * fade
	var inner := color
	inner.a = 0.35 * fade

	if both_sides:
		draw_arc(Vector2.ZERO, current, 0.0, TAU, 64, ring, 4.0 * fade + 1.0, true)
		draw_arc(Vector2.ZERO, current * 0.72, 0.0, TAU, 48, inner, 2.0, true)
	else:
		# Left and right half-arcs read as a shockwave running along the ground.
		draw_arc(Vector2.ZERO, current, -PI * 0.5, PI * 0.5, 32, ring, 4.0 * fade + 1.0, true)
		draw_arc(Vector2.ZERO, current, PI * 0.5, PI * 1.5, 32, ring, 4.0 * fade + 1.0, true)
		draw_arc(Vector2.ZERO, current * 0.72, -PI * 0.5, PI * 0.5, 24, inner, 2.0, true)
		draw_arc(Vector2.ZERO, current * 0.72, PI * 0.5, PI * 1.5, 24, inner, 2.0, true)
