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
## Idle vocalizations pause while the owner is moving, attacking or dead.
var idle_enabled := true

var _players: Array[AudioStreamPlayer2D] = []
var _next_player := 0
var _idle_timer := 0.0


func _ready() -> void:
	_build_pool()
	_schedule_idle()


## Attaches a voice and restarts the idle schedule.
func bind(new_set: SfxSet) -> void:
	sfx_set = new_set
	_schedule_idle()


func play_attack() -> void:
	_play(&"attack", sfx_set.attack if sfx_set != null else null)


func play_hurt() -> void:
	_play(&"hurt", sfx_set.hurt if sfx_set != null else null)


func play_death() -> void:
	# A corpse does not keep vocalizing.
	idle_enabled = false
	_play(&"death", sfx_set.death if sfx_set != null else null)


func _process(delta: float) -> void:
	if sfx_set == null or sfx_set.idle == null:
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
	_play(&"idle", sfx_set.idle)


## Picks the next gap from the set's randomized range.
func _schedule_idle() -> void:
	if sfx_set == null or sfx_set.idle == null:
		_idle_timer = 0.0
		return
	var bounds := sfx_set.idle_delay_bounds()
	_idle_timer = randf_range(bounds.x, bounds.y)


func _play(kind: StringName, stream: AudioStream) -> void:
	if stream == null or not is_inside_tree():
		return
	_build_pool()
	if _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = sfx_set.volume_db if sfx_set != null else 0.0
	var jitter := sfx_set.pitch_jitter if sfx_set != null else 0.0
	player.pitch_scale = randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()
	played.emit(kind)


func _build_pool() -> void:
	if not _players.is_empty():
		return
	for i in POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)
