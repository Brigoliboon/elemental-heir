extends MonsterPassive
class_name AuraPassive
## Refreshes a set of stat buffs on nearby allies while the owner lives. A buff with
## `seconds == 0` is removed as soon as the ally leaves the radius or the aura dies.

@export_group("Aura")
@export var radius := 300.0
## How often membership is recomputed. Modifiers are refreshed, not stacked.
@export var tick_seconds := 0.5
@export var buffs: Array[StatBuff] = []
## Include the aura owner in the effect.
@export var affect_self := false


func validate() -> String:
	if buffs.is_empty():
		return "aura has no buffs"
	for buff in buffs:
		if buff == null:
			return "aura buff list contains null"
	return ""
