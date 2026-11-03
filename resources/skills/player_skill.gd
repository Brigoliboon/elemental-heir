class_name PlayerSkill
extends AttackData
## A player action with its own clip, energy cost and cooldown.
##
## Extends [AttackData] because the warrior's clips are baked procedurally from key
## poses: a skill is a clip plus combat metadata. Adding one is a new `.tres`, not a
## code change. `id` doubles as the clip name in the character's AnimationPlayer.

@export_group("Identity")
@export var display_name: String = "Skill"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Character level required before the slot accepts this skill.
@export var unlock_level := 1

@export_group("Cost")
## Seconds before the skill can be used again.
@export var cooldown := 5.0
## Energy spent on cast. 0 makes the skill free.
@export var energy_cost := 0

@export_group("Cast")
## Playback speed for the clip. Below 1 slows the swing into a wind-up.
@export var animation_speed := 1.0
## True when the skill damages through the sword hitbox during its hit window.
@export var uses_sword := false
## Multiplies the attack stat for sword and area damage.
@export var damage_multiplier := 1.0
## Impact flash applied to targets. Transparent keeps the normal hit feedback.
@export var hit_flash_color := Color(0.0, 0.0, 0.0, 0.0)
@export var hit_flash_seconds := 0.22

@export_group("Audio")
## Cast sound variants, one picked at random. Leave empty to use the character's
## [SfxSet] entry for `id`, then the shared `attack` slot.
@export var cast_sounds: Array[AudioStream] = []


## Cooldown after the character's cooldown-reduction stat is applied. The cap
## keeps a stacked build from reaching zero and bypassing the cast lock.
func effective_cooldown(reduction: float) -> float:
	return maxf(0.05, cooldown * (1.0 - clampf(reduction, 0.0, 0.9)))


## Empty string when the skill is safe to bake into the animation library.
func validate() -> String:
	if id == &"":
		return "skill has no id"
	if length <= 0.0:
		return "length must be greater than 0"
	if keys.is_empty():
		return "skill has no key poses"
	if damage_multiplier <= 0.0:
		return "damage_multiplier must be greater than 0"
	if energy_cost < 0:
		return "energy_cost cannot be negative"
	if cooldown < 0.0:
		return "cooldown cannot be negative"
	for key in keys:
		for field in ["t", "arm", "fore", "hand", "sword", "lean", "px", "py"]:
			if not key.has(field):
				return "key at t=%s is missing '%s'" % [key.get("t", "?"), field]
	return ""
