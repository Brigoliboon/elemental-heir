class_name AnimationSfx
extends Resource
## One-shot sound variants for a specific sprite animation.
##
## `SfxSet` keeps the shared attack/hurt/death slots; this resource adds sounds for
## individual clips such as `root_charge`, `enrage` or `call_herd`. The same clip
## name used by the SpriteFrames is the key, so an animation override and its
## sound travel together.

## Animation clip name, for example `root_charge`.
@export var animation: StringName = &"attack"
## Variants; one is picked at random and the previous sample is avoided.
@export var streams: Array[AudioStream] = []
