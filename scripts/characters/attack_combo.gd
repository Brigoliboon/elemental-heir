class_name AttackCombo
extends RefCounted
## Chains a character's attacks: the first press starts hit 1, a press late enough in the
## current hit queues the next one, and the combo wraps after the last hit.

signal combo_started
signal combo_ended

var _player: AnimationPlayer
var _config: CharacterConfig
var _index := 0
var _queued := false


func _init(player: AnimationPlayer, config: CharacterConfig) -> void:
	_player = player
	_config = config
	_player.animation_finished.connect(_on_animation_finished)


func is_attacking() -> bool:
	return _index != 0


## Index of the hit playing now (1-based), or 0 when not attacking.
func current_hit() -> int:
	return _index


func press() -> void:
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
