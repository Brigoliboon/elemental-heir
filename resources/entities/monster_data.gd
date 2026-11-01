extends EnemyData
class_name MonsterData
## Data for any monster, from a trash mob to a region Guardian.
##
## `EnemyData` still owns the stat block, rewards and voice. This resource adds the
## AI tuning, the skills the monster may choose from, and any always-on passives.
## Rank is presentation and difficulty only: every rank can equip the same skills.

enum Rank { NORMAL, GENERAL, GUARDIAN }

@export_group("Identity")
@export var rank: Rank = Rank.NORMAL

@export_group("AI")
## Base gap between auto-attacks and casts.
@export var attack_cooldown: float = 1.0
## Horizontal distance at which the monster stops and fights.
@export var attack_range: float = 135.0
## Closer than this and the monster backs off so sprites do not overlap.
@export var min_attack_space: float = 85.0
## Preferred spacing to the target while closing in.
@export var attack_space: float = 110.0
## Maximum feet-y difference for an attack to connect.
@export var depth_tolerance: float = 30.0
## Distance at which the monster notices the player.
@export var aggro_radius: float = 325.0
## Minimum gap between any two special casts, so skills do not fire back to back.
@export var global_cooldown: float = 0.8

@export_group("Skills")
## Always available when in range and off the attack timer.
@export var basic_attack: MonsterSkill
## Ranked abilities. Any mix is allowed; the AI gates them at runtime.
@export var skills: Array[MonsterSkill] = []

@export_group("Passives")
## Always-on or tick-driven effects, never chosen by the AI.
@export var passives: Array[MonsterPassive] = []

@export_group("Animation")
@export var idle_animation: StringName = &"default"
@export var walk_animation: StringName = &"walk"


## True when this monster can chase and fight. A monster without a basic attack
## cannot do anything, so the runtime warns about it on spawn.
func has_basic_attack() -> bool:
	return basic_attack != null


## Every skill, basic included, for validation and tooling.
func all_skills() -> Array[MonsterSkill]:
	var result: Array[MonsterSkill] = []
	if basic_attack != null:
		result.append(basic_attack)
	for skill in skills:
		if skill != null:
			result.append(skill)
	return result
