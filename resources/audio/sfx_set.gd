extends Resource
class_name SfxSet
## The voice of one character or enemy: the streams it plays and how they mix.
##
## Data owns the sounds so a new enemy is a new `.tres`, not a code change. Every
## slot is a list of variants, and each trigger picks one at random, so a repeated
## swing or hit does not machine-gun the same sample. Any empty slot simply stays
## silent, so a set can be filled in gradually.

@export_group("Combat")
## Played when a swing starts. Keep several variants for a busy combo.
@export var attack: Array[AudioStream] = []
## Played when the character takes damage.
@export var hurt: Array[AudioStream] = []
## Played when a hit is absorbed by an active guard.
@export var block: Array[AudioStream] = []
## Played once when the character dies.
@export var death: Array[AudioStream] = []

@export_group("Idle")
## Occasional vocalization. Leave empty for silent idle.
@export var idle: Array[AudioStream] = []
## Randomized silence between idle vocalizations, in seconds. A range (rather
## than one fixed value) desynchronizes a crowd of enemies.
@export var idle_delay_min := 4.0
@export var idle_delay_max := 9.0
## Minimum time between any two idle vocalizations in the scene, so several
## enemies cannot chirp on the same frame.
@export var idle_shared_cooldown := 2.0

@export_group("Mix")
## Added to the stream's own volume, in dB.
@export var volume_db := 0.0
## Random pitch spread: 0.05 means +/-5%, which keeps repeated hits from sounding
## like the same sample firing over and over.
@export_range(0.0, 0.5, 0.01) var pitch_jitter := 0.05


## Shortest and longest idle delay, sorted so min never exceeds max.
func idle_delay_bounds() -> Vector2:
	var low := maxf(0.0, minf(idle_delay_min, idle_delay_max))
	var high := maxf(low, maxf(idle_delay_min, idle_delay_max))
	return Vector2(low, high)


## True when the slot has at least one real stream behind it.
func has_streams(kind: StringName) -> bool:
	for stream in _streams(kind):
		if stream != null:
			return true
	return false


## A random variant for `kind`. When `avoid` is set it is skipped if there is
## another choice, so the previous sound does not repeat back to back.
func pick(kind: StringName, avoid: AudioStream = null) -> AudioStream:
	var options: Array[AudioStream] = []
	for stream in _streams(kind):
		if stream != null:
			options.append(stream)
	if options.size() > 1 and avoid != null:
		options.erase(avoid)
	if options.is_empty():
		return null
	return options[randi() % options.size()]


func _streams(kind: StringName) -> Array:
	var list: Variant = get(kind)
	return list if list is Array else []
