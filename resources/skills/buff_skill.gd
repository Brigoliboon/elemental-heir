extends MonsterSkill
class_name BuffSkill
## Applies one or more [StatBuff]s to the caster. A skill-level cooldown and the
## buff's own `seconds` are independent: the buff can outlast the cooldown.

@export_group("Buff")
@export var buffs: Array[StatBuff] = []
## Fraction of maximum health restored on cast. 0 heals nothing.
@export_range(0.0, 1.0) var heal_fraction := 0.0


func validate() -> String:
	if buffs.is_empty() and heal_fraction <= 0.0:
		return "buff skill has no buffs and no heal"
	for buff in buffs:
		if buff == null:
			return "buff list contains null"
	return ""
