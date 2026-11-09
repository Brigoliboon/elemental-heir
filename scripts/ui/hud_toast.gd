class_name HudToast
extends Label
## Short, transient HUD message ("Inventory full").
##
## Lives in the shared area HUD and registers in the `hud_toast` group so world
## pickups can report a blocked collection without knowing the HUD layout.

@export var message_seconds := 1.6
@export var fade_seconds := 0.35

var _tween: Tween


func _ready() -> void:
	add_to_group("hud_toast")
	modulate.a = 0.0
	text = ""


## Shows `message` and fades it out. A new message replaces the current one.
func show_message(message: String) -> void:
	text = message
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(maxf(0.0, message_seconds))
	_tween.tween_property(self, "modulate:a", 0.0, maxf(0.01, fade_seconds))
