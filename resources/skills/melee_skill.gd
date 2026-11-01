extends MonsterSkill
class_name MeleeSkill
## A swing that drives the monster's existing AttackHitbox. The skill only swaps
## the hitbox geometry, damage multiplier and knockback for the duration of the cast.

@export_group("Melee")
@export var damage_multiplier := 1.0
@export var knockback := 0.0
## Hitbox offset from the monster origin, mirrored with facing.
@export var hitbox_offset := Vector2(70.0, 15.0)
@export var hitbox_size := Vector2(176.0, 154.0)
## Maximum feet-y difference for this skill to connect. 0 disables the check.
@export var hit_depth_tolerance := 40.0


func validate() -> String:
	if damage_multiplier <= 0.0:
		return "damage_multiplier must be greater than 0"
	return ""
