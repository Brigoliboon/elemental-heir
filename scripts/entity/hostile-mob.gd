extends AnimatedSprite2D

@export var attack_chance: float = 0.9  # 2% chance per frame
@export var attack_duration: float = 1.0

var _attack_timer: float = 0.0
var _is_attacking: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	play("default")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if randf() <= attack_chance:
		await play("attack")
		if animation_finished:
			play("default")
