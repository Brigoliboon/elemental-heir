class_name AttackData
extends Resource
## One hit of a combo. Each key is an offset from the guard pose:
## t = fraction of the clip, arm/fore/hand = near-arm rotation offsets (deg, negative raises
## the arm forward), sword = blade angle offset from the guard (deg, positive swings it
## forward and down), lean = extra torso lean at the waist (deg), px/py = pelvis shift
## (rig px, +x forward, +y down; feet stay planted). First and last keys are the guard pose.

## Animation name, e.g. "attack_1".
@export var id: StringName = &"attack"
## Clip length in seconds.
@export var length := 0.36
## Lock the sword to the hand at its guard grip (ignores the "sword" key values).
@export var rigid_sword := false
## Fraction of the clip (0..1) where the sword hitbox is live.
@export_range(0.0, 1.0) var hit_start := 0.3
@export_range(0.0, 1.0) var hit_end := 0.65
## Damage for this hit. 0 uses the character's attack_damage.
@export var damage := 0
@export var keys: Array[Dictionary] = []
