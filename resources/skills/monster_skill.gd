extends Resource
class_name MonsterSkill
## Base contract for one action a monster can choose. The subclass carries the
## payload (melee hitbox, buff, summon, ...); everything here is what the AI needs
## to decide whether the skill is usable and how to play it.
##
## Skills are resources, so the same `.tres` can be shared by a normal, a general
## and a guardian. Rank never filters skills.

@export_group("Identity")
@export var id: StringName = &"skill"

@export_group("Availability")
## Seconds between casts, scaled by the monster's cooldown reduction.
@export var cooldown := 4.0
## Ground distance in which the skill may start.
@export var min_range := 0.0
## 0 or less means no upper limit, which is what self-cast buffs and summons want.
@export var max_range := 160.0
## Usable only while the monster's health ratio is at or below this value.
## 1.0 means always; 0.5 gates the skill to phase two.
@export_range(0.0, 1.0) var health_below := 1.0
## Lifetime cast cap. 0 means unlimited, 1 means once per fight.
@export var max_casts := 0

@export_group("Selection")
## Higher priority wins; ties are broken by weight.
@export var priority := 0
@export var weight := 1.0

@export_group("Animation")
@export var animation: StringName = &"attack"
@export var animation_speed := 1.0
## Fraction of the clip where the skill's effect resolves.
@export_range(0.0, 1.0) var hit_start := 0.35
@export_range(0.0, 1.0) var hit_end := 0.65


func is_basic() -> bool:
	return false


## Scheduler gates shared by every skill. Summon caps are checked separately
## because they depend on the current living count.
func is_available(
	cooldown_left: float,
	casts: int,
	health_ratio: float,
	distance: float
) -> bool:
	if cooldown_left > 0.0:
		return false
	if max_casts > 0 and casts >= max_casts:
		return false
	if health_ratio > health_below:
		return false
	if distance < min_range:
		return false
	# A non-positive max_range means "no range limit" (self-cast buffs, summons).
	if max_range > 0.0 and distance > max_range:
		return false
	return true


## Cooldown after `cooldown_reduction` (0..1).
func effective_cooldown(cooldown_reduction: float) -> float:
	return maxf(0.0, cooldown * (1.0 - clampf(cooldown_reduction, 0.0, 0.9)))


## Asks the subclass to validate itself. Returns a human-readable problem, or "".
func validate() -> String:
	return ""
