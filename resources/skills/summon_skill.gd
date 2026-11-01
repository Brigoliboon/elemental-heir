extends MonsterSkill
class_name SummonSkill
## Calls ordinary monster scenes into the fight. Summoning is an action, so it is a
## skill with a cooldown, an animation and a telegraph — not a passive.
##
## `max_alive` is the spam limiter: the skill becomes unavailable while that many
## of its summons are alive, no matter how short the cooldown is.

@export_group("Summon")
@export var summon_scene: PackedScene
## Maximum spawns attempted per cast.
@export var count := 3
## Hard cap on living summons from this skill. 0 means no cap.
@export var max_alive := 4
## Radius of the ring around the caster where summons appear.
@export var spawn_radius := 140.0
## Delay between the cast resolving and the summons appearing. 0 spawns instantly.
@export var spawn_telegraph := 0.5
## Stat buffs pushed onto every summoned monster. Permanent unless `seconds` is set.
@export var buffs: Array[StatBuff] = []
## When true, the summons are removed the moment their summoner dies.
@export var despawn_with_summoner := true


func validate() -> String:
	if summon_scene == null:
		return "summon_scene is not set"
	if count <= 0:
		return "count must be greater than 0"
	return ""
