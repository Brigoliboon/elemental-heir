extends Resource
class_name MonsterPassive
## Always-on or tick-driven effect. Passives are never chosen by the AI: if it needs
## an animation, a cooldown or a telegraph, it belongs in a [MonsterSkill] instead.

@export var id: StringName = &"passive"


func validate() -> String:
	return ""
