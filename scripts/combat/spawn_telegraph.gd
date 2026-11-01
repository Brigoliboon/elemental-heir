class_name SpawnTelegraph
extends Node2D
## The warning ring drawn before a summoned monster appears. Purely cosmetic: the
## summoner owns the timer and spawns the monster when the telegraph finishes.

signal finished

@export var radius := 42.0
@export var duration := 0.5
@export var ring_color := Color(0.92, 0.32, 0.22, 0.85)
@export var fill_color := Color(0.92, 0.32, 0.22, 0.18)

var _elapsed := 0.0


func setup(new_radius: float, new_duration: float) -> void:
	radius = maxf(1.0, new_radius)
	duration = maxf(0.0, new_duration)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		finished.emit()
		queue_free()


func _draw() -> void:
	var progress := clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	# Collapse inward so the player can read the exact landing point.
	var current := radius * (1.0 - progress * 0.35)
	draw_circle(Vector2.ZERO, current, fill_color)
	draw_arc(Vector2.ZERO, current, 0.0, TAU, 40, ring_color, 3.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(ring_color, 0.35), 1.5)
