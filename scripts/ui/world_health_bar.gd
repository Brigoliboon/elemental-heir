class_name WorldHealthBar
extends Node2D
## Draws a small health bar above an entity in world space.
##
## The bar finds the `Health` node on its parent automatically, so any entity scene
## can reuse it by adding a Node2D child with this script. It follows the parent's
## transform but ignores sprite flipping.

@export var width := 72.0
@export var height := 8.0
@export var fill_color := Color(0.78, 0.18, 0.18, 1.0)
@export var background_color := Color(0.07, 0.05, 0.05, 0.85)
@export var border_color := Color(0.0, 0.0, 0.0, 0.9)
## Hidden while at full health, so idle enemies stay uncluttered.
@export var hide_when_full := true

var health: Health

var _current := 0
var _maximum := 1


func _ready() -> void:
	health = get_parent().get_node_or_null("Health") as Health
	if health == null:
		push_warning("%s has no Health sibling" % name)
		return
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	_current = current
	_maximum = maxi(1, maximum)
	visible = not (hide_when_full and _current >= _maximum)
	queue_redraw()


func _draw() -> void:
	var ratio := clampf(float(_current) / float(_maximum), 0.0, 1.0)
	var rect := Rect2(-width * 0.5, -height * 0.5, width, height)
	draw_rect(Rect2(rect.position - Vector2(1.0, 1.0), rect.size + Vector2(2.0, 2.0)), border_color, true)
	draw_rect(rect, background_color, true)
	if ratio > 0.0:
		draw_rect(Rect2(rect.position, Vector2(width * ratio, height)), fill_color, true)
