class_name AttackCombo
extends RefCounted
## Chains a character's attacks: the first press starts hit 1, a press late enough in the
## current hit queues the next one, and the combo wraps after the last hit.

signal combo_started
signal combo_ended

var _player: AnimationPlayer
var _config: CharacterData
var _index := 0
var _queued := false


func _init(player: AnimationPlayer, config: CharacterData) -> void:
	_player = player
	_config = config
	_player.animation_finished.connect(_on_animation_finished)


func is_attacking() -> bool:
	_abort_if_interrupted()
	return _index != 0


## Index of the hit playing now (1-based), or 0 when not attacking.
func current_hit() -> int:
	return _index


func press() -> void:
	_abort_if_interrupted()
	if _config.attacks.is_empty():
		return
	if _index == 0:
		_start(1)
		combo_started.emit()
		return
	var length := _player.current_animation_length
	if length > 0.0 and _player.current_animation_position >= length * _config.attack_queue_from:
		_queued = true


func _start(index: int) -> void:
	_index = index
	_queued = false
	_player.play(_config.attacks[index - 1].id, _config.attack_blend)


## Stops the chain immediately (death, respawn, scene transitions).
func cancel() -> void:
	if _index == 0:
		return
	_index = 0
	_queued = false
	combo_ended.emit()


## Clears the swing if another animation (guard, idle, death) replaced it. Without
## this the aborted attack never reports animation_finished, so the combo stays
## latched at hit 1 and the character refuses to move forever.
func _abort_if_interrupted() -> void:
	if _index == 0 or _player == null:
		return
	if _config.attacks.is_empty():
		cancel()
		return
	if _player.current_animation != _config.attacks[_index - 1].id:
		cancel()


func _on_animation_finished(anim_name: StringName) -> void:
	if _index == 0 or anim_name != _config.attacks[_index - 1].id:
		return
	if _queued:
		_start(_index % _config.attacks.size() + 1)
		return
	_index = 0
	_queued = false
	_player.play("idle", _config.recover_blend)
	combo_ended.emit()
