class_name GroundSlamSkill
extends PlayerSkill
## A stomp that damages and knocks down every enemy around the caster.
##
## The shockwave is centred on the feet when the hit window opens, so it hits both
## sides without a facing check. Generals and Guardians ignore the knockdown; see
## [method Monster.can_be_knocked_down].

@export_group("Shockwave")
## Radius of the damage circle in world pixels.
@export var radius := 240.0
## Seconds the damage area stays active. Short values mean a single burst.
@export var active_seconds := 0.12
@export var knockback := 180.0
## Maximum feet-y difference from the caster. 0 disables the depth check.
@export var hit_depth_tolerance := 46.0
## Colour of the expanding shockwave ring.
@export var pulse_color := Color(1.0, 0.72, 0.35, 1.0)

@export_group("Knockdown")
## Drop small enemies for a moment after the hit.
@export var knockdown := true
@export var knockdown_seconds := 1.2


func validate() -> String:
	var problem := super()
	if problem != "":
		return problem
	if radius <= 0.0:
		return "radius must be greater than 0"
	if active_seconds <= 0.0:
		return "active_seconds must be greater than 0"
	if knockdown and knockdown_seconds <= 0.0:
		return "knockdown_seconds must be greater than 0"
	return ""
