extends MonsterSkill
class_name RadialSkill
## Shared payload for skills that damage every target inside a circle.
##
## Subclasses decide where the circle lands: [AoESkill] centres it on the caster,
## [GroundTargetSkill] locks it to a captured target position. Damage, knockback
## and depth filtering live here so both kinds of area attack behave the same way.

@export_group("Area")
## Radius of the damage circle in world pixels.
@export var radius := 160.0
## Seconds the damage area stays active. Short values mean a single burst.
@export var active_seconds := 0.12

@export_group("Damage")
@export var damage_multiplier := 1.0
@export var knockback := 0.0
## Maximum feet-y difference from the impact point. 0 disables the check.
@export var hit_depth_tolerance := 40.0


func validate() -> String:
	var base := super()
	if base != "":
		return base
	if radius <= 0.0:
		return "radius must be greater than 0"
	if active_seconds <= 0.0:
		return "active_seconds must be greater than 0"
	if damage_multiplier <= 0.0:
		return "damage_multiplier must be greater than 0"
	return ""
