class_name SkillAnimationOverride
extends Resource
## Per-monster animation swap for a skill shared with other monsters.
##
## The skill resource still owns the tuning (damage, cooldown, hit window), while
## this resource lets a general play a different clip without duplicating the
## whole skill. Leave `animation` empty to keep the skill's own clip.

## Skill id to match, for example `charge` or `enrage`.
@export var skill_id: StringName = &""
## Clip to play instead of the skill's `animation`.
@export var animation: StringName = &""
## Greater than zero overrides the skill's `animation_speed`.
@export var animation_speed := 0.0
