extends PointLight2D

## Random lantern flicker. Attach directly to the PointLight2D.
## The exported range is a multiplier on the light's starting energy.

@export var min_energy: float = 0.7   ## Lowest brightness drop (x base energy)
@export var max_energy: float = 1.3   ## Highest brightness spike (x base energy)
@export var flicker_speed: float = 0.05 ## Seconds between new random targets
@export var smoothing: float = 30.0   ## How quickly energy slides to the target

var _base_energy: float = 1.0
var _target_energy: float = 1.0
var _time_passed: float = 0.0

func _ready() -> void:
	_base_energy = energy
	_target_energy = energy

func _process(delta: float) -> void:
	_time_passed += delta
	if _time_passed >= flicker_speed:
		_time_passed = 0.0
		_target_energy = _base_energy * randf_range(min_energy, max_energy)
	energy = lerpf(energy, _target_energy, clampf(delta * smoothing, 0.0, 1.0))
