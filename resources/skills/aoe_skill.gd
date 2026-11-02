extends RadialSkill
class_name AoESkill
## A radial burst centred on the caster when the hit window opens.
##
## Use this for novas, stomps, roars and other self-centred area attacks. The
## circle is placed at the caster's feet when the effect resolves, so a moving
## monster carries the burst with it until the hit frame.

@export_group("Placement")
## Offset from the caster's feet. X is mirrored with facing; (0, 0) is a nova.
@export var offset := Vector2.ZERO
