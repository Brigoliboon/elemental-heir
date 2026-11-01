extends Resource
class_name StatBuff
## One stat modifier that can be shared by skill buffs, summoned-monster buffs and
## auras. `seconds == 0` means the buff lasts until its owner removes it.

@export var stat: StringName = Stats.ATTACK
@export var flat := 0.0
@export var pct := 0.30
## Lifetime in seconds. 0 keeps the modifier until the source is cleared.
@export var seconds := 0.0
## Visual tell applied to the affected sprite. White leaves the tint untouched.
@export var tint := Color.WHITE
