class_name ProgressionData
extends Resource
## Global XP curve tuning from DESIGN_ROADMAP §2.4:
##   xp_to_next(level) = base_xp * level ^ exponent

@export var base_xp: int = 100
@export var exponent: float = 1.5
@export var max_level: int = 15


## XP required to advance from `level` to the next one. Returns 0 at the cap.
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	return maxi(1, roundi(float(base_xp) * pow(float(maxi(1, level)), exponent)))
