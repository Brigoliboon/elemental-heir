extends Resource
class_name FootstepSet
## The surface a character walks on: its step sounds and how far apart they sit.
##
## Variants play in order, not at random. Two alternating recordings read as a real
## gait, while random picking can repeat the same foot twice and expose the loop.
##
## Scenes choose a set (`forest` grass, `stone` dungeon) and the character plays it
## as it travels, so a new surface is a new `.tres`, not a code change.

## Played in sequence and looped. Leave empty for silent footsteps.
@export var streams: Array[AudioStream] = []
## World pixels the character must cover between steps. Tying steps to distance
## keeps the cadence right whether the character walks or runs.
@export var stride_pixels := 90.0
## Added to the stream's own volume, in dB.
@export var volume_db := 0.0
## Pitch spread per step. Zero keeps the alternation exactly as recorded.
@export_range(0.0, 0.5, 0.01) var pitch_jitter := 0.0


## The n-th usable stream, wrapping. Null entries in the array are skipped so an
## unfinished set degrades to the sounds that exist instead of going quiet.
func stream_at(index: int) -> AudioStream:
	var valid: Array[AudioStream] = []
	for stream in streams:
		if stream != null:
			valid.append(stream)
	if valid.is_empty():
		return null
	return valid[index % valid.size()]


## Number of usable streams, which is what the sequence wraps on.
func variant_count() -> int:
	var count := 0
	for stream in streams:
		if stream != null:
			count += 1
	return count
