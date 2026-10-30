extends Resource
class_name SfxSet
## The voice of one character or enemy: the streams it plays and how they mix.
##
## Data owns the sounds so a new enemy is a new `.tres`, not a code change. Any
## unassigned stream simply stays silent, so a set can be filled in gradually.
## Triggering stays in code, because the entities already raise the right signals.

@export_group("Combat")
## Played when a swing starts.
@export var attack: AudioStream
## Played when the character takes damage.
@export var hurt: AudioStream
## Played once when the character dies.
@export var death: AudioStream

@export_group("Idle")
## Occasional vocalization. Leave empty for silent idle.
@export var idle: AudioStream
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


## Shortest idle delay, with the range normalized so min never exceeds max.
func idle_delay_bounds() -> Vector2:
	var low := maxf(0.0, minf(idle_delay_min, idle_delay_max))
	return Vector2(low, maxf(low, idle_delay_max))
