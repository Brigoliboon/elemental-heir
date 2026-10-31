extends Node2D
class_name SfxComponent
## Plays an [SfxSet] for one character or enemy through a small pool of positional
## players, so sounds pan and fall off with distance and overlapping hits do not
## cut each other off.
##
## Callers keep the "when": attack start, damage, death. This node owns the "how":
## pooling, pitch jitter, and the idle vocalization schedule.

## Emitted whenever a stream actually starts. Tests and debug overlays use it.
signal played(kind: StringName)

## Positional players created up front; enough for a hit landing on the same frame
## as a swing and an idle vocal.
const POOL_SIZE := 4

## When any idle vocalization last played, in milliseconds since engine start.
## Shared by every component so a crowd cannot vocalize in unison.
static var _last_idle_msec := -1_000_000

var sfx_set: SfxSet
## Surface the owner walks on. Set by the scene; null keeps footsteps silent.
var footsteps: FootstepSet
## Idle vocalizations pause while the owner is moving, attacking or dead.
var idle_enabled := true

var _players: Array[AudioStreamPlayer2D] = []
var _next_player := 0
var _idle_timer := 0.0
## Next index in the footstep sequence, so steps alternate 1, 2, 1, 2 ...
var _footstep_index := 0
## Last stream played per kind, so a variant does not repeat back to back.
var _last_picked: Dictionary = {}
## Kinds already reported as missing, so a mob that attacks every second does not
## flood the log with the same warning.
var _missing_warned: Dictionary = {}


func _ready() -> void:
	_build_pool()
	_schedule_idle()


## Attaches a voice and restarts the idle schedule.
func bind(new_set: SfxSet) -> void:
	sfx_set = new_set
	_last_picked.clear()
	_schedule_idle()


func play_attack() -> void:
	_play_variant(&"attack")


func play_hurt() -> void:
	_play_variant(&"hurt")


func play_block() -> void:
	_play_variant(&"block")


func play_death() -> void:
	# A corpse does not keep vocalizing.
	idle_enabled = false
	_play_variant(&"death")


## Plays the next step in the surface's sequence, wrapping. Steps are sequential
## rather than random so a two-sample gait does not repeat the same foot.
func play_footstep() -> void:
	if footsteps == null:
		return
	var stream := footsteps.stream_at(_footstep_index)
	_footstep_index = (_footstep_index + 1) % maxi(1, footsteps.variant_count())
	if stream == null:
		return
	_play(&"footstep", stream, footsteps.volume_db, footsteps.pitch_jitter)


func _process(delta: float) -> void:
	if sfx_set == null or not sfx_set.has_streams(&"idle"):
		_idle_timer = 0.0
		return
	if _idle_timer <= 0.0:
		return
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_schedule_idle()
	if not idle_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_idle_msec < int(maxf(0.0, sfx_set.idle_shared_cooldown) * 1000.0):
		return
	_last_idle_msec = now
	_play_variant(&"idle")


## Picks the next gap from the set's randomized range.
func _schedule_idle() -> void:
	if sfx_set == null or not sfx_set.has_streams(&"idle"):
		_idle_timer = 0.0
		return
	var bounds := sfx_set.idle_delay_bounds()
	_idle_timer = randf_range(bounds.x, bounds.y)


## Chooses a random variant for `kind`, avoiding an immediate repeat.
func _play_variant(kind: StringName) -> void:
	if sfx_set == null:
		_warn_missing(kind)
		return
	var stream := sfx_set.pick(kind, _last_picked.get(kind))
	if stream != null:
		_last_picked[kind] = stream
	_play(kind, stream, sfx_set.volume_db, sfx_set.pitch_jitter)


func _play(kind: StringName, stream: AudioStream, volume_db: float, jitter: float) -> void:
	if stream == null:
		_warn_missing(kind)
		return
	if not is_inside_tree():
		return
	_build_pool()
	if _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()
	played.emit(kind)


## Silence is the hardest failure to spot, so every empty slot says so once, loudly
## enough to show up in `adb logcat` on a device.
func _warn_missing(kind: StringName) -> void:
	if _missing_warned.has(kind):
		return
	_missing_warned[kind] = true
	var owner_path := String(name)
	var owner := get_parent()
	if owner != null:
		owner_path = "%s/%s" % [owner.name, name]
	if sfx_set == null:
		push_warning("SFX: %s wanted '%s' but has no SfxSet bound" % [owner_path, kind])
		return
	push_warning("SFX: no '%s' stream on %s for %s" % [kind, sfx_set.resource_path, owner_path])


func _build_pool() -> void:
	if not _players.is_empty():
		return
	for i in POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)
