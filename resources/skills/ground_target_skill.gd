extends RadialSkill
class_name GroundTargetSkill
## Lands a radial hit on a position captured from the target.
##
## With [member lock_at_cast] enabled the impact point is captured when the cast
## starts, so the player can dodge by leaving the marked spot before the hit
## window. Disable it to keep following the target until the effect resolves.

@export_group("Targeting")
## Capture the target's position when the cast starts. False recaptures at impact.
@export var lock_at_cast := true
