class_name SelfBuffSkill
extends PlayerSkill
## A self-cast buff that also slows nearby enemies.
##
## The buff payload is split in two because they resolve differently: [StatBuff]s
## go through [Stats], while damage reduction, knockback immunity and reflection
## are defensive state owned by [Character]. Iron Will and War Cry are both this
## class with different data, so a new tank or shout skill needs no new code.

@export_group("Buff")
## Timed stat changes. Each buff's own `seconds` controls its lifetime.
@export var buffs: Array[StatBuff] = []
## Seconds the defensive part lasts. Independent of each buff's `seconds`.
@export var duration := 6.0
## Incoming damage multiplier while active. 0.6 takes 40% less damage.
@export_range(0.0, 1.0) var damage_taken_multiplier := 1.0
## Ignore knockback impulses while active.
@export var knockback_immune := false
## Evolution tier 2+: fraction of maximum health restored on cast.
@export_range(0.0, 1.0) var tier2_heal_fraction := 0.0
## Evolution tier 3+: fraction of damage taken reflected at the attacker.
@export_range(0.0, 1.0) var tier3_reflect_fraction := 0.0

@export_group("Pulse")
## Enemies inside this radius are slowed on cast. 0 disables the pulse.
@export var slow_radius := 0.0
## Movement multiplier for slowed enemies. 0.5 halves their speed.
@export_range(0.05, 1.0) var slow_factor := 1.0
@export var slow_seconds := 0.0
## Colour of the expanding ring drawn at the caster's feet.
@export var pulse_color := Color(1.0, 0.85, 0.4, 1.0)


func validate() -> String:
	var problem := super()
	if problem != "":
		return problem
	if duration <= 0.0:
		return "duration must be greater than 0"
	if buffs.is_empty() and is_equal_approx(damage_taken_multiplier, 1.0) and not knockback_immune:
		return "buff skill has no effect"
	for buff in buffs:
		if buff == null:
			return "buff list contains null"
	if slow_radius > 0.0 and (slow_seconds <= 0.0 or slow_factor >= 1.0):
		return "slow pulse needs slow_seconds and a slow_factor below 1"
	return ""
