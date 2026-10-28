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
@export var keys: Array[Dictionary] = []
