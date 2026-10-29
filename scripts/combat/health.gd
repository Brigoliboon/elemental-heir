class_name Health
extends Node
## Shared health pool for the player and enemies.
##
## The owning entity configures this component from its data resource and forwards
## its public health API (`current_health`, `max_health`, `take_damage`, `is_alive`)
## here. Signals are emitted on behalf of the owner so HUD, feedback and death code
## can bind to either the entity or the component.
##
## Invulnerability (i-frames) is opt-in through `invulnerability_seconds`: while the
## timer runs, `take_damage()` returns false and deals no damage. Leave it at 0 for
## entities that should accept every hit.

signal damaged(amount: int, remaining: int)
signal healed(amount: int, remaining: int)
signal health_changed(current: int, maximum: int)
signal died

@export var max_health := 100
## Seconds of invulnerability granted after a successful hit. 0 disables i-frames.
@export var invulnerability_seconds := 0.0

var current_health := 0

var _invulnerable_left := 0.0
var _dead := false


func _ready() -> void:
	if current_health <= 0:
		current_health = maxi(1, max_health)
	set_process(false)


## Starts at full health with a new maximum. Negative invulnerability keeps the
## value already exported/set by the scene.
func configure(maximum: int, invulnerability := -1.0) -> void:
	max_health = maxi(1, maximum)
	if invulnerability >= 0.0:
		invulnerability_seconds = invulnerability
	reset()


## Restores full health and clears death/i-frame state without changing the maximum.
func reset() -> void:
	current_health = max_health
	_invulnerable_left = 0.0
	_dead = false
	set_process(false)
	health_changed.emit(current_health, max_health)


func is_alive() -> bool:
	return current_health > 0


func is_dead() -> bool:
	return _dead


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## Applies damage. Returns true when it landed. Dead or invulnerable targets ignore it.
func take_damage(amount: int) -> bool:
	if amount <= 0 or not is_alive() or is_invulnerable():
		return false

	var applied := mini(amount, current_health)
	current_health -= applied
	damaged.emit(applied, current_health)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		_dead = true
		died.emit()
	elif invulnerability_seconds > 0.0:
		_invulnerable_left = invulnerability_seconds
		set_process(true)
	return true


## Heals up to the maximum. Returns the amount actually restored.
func heal(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var before := current_health
	current_health = mini(current_health + amount, max_health)
	var restored := current_health - before
	if restored > 0:
		healed.emit(restored, current_health)
		health_changed.emit(current_health, max_health)
	return restored


## Kills the entity immediately, emitting `died` once.
func kill() -> void:
	if not is_alive():
		return
	var applied := current_health
	current_health = 0
	_dead = true
	damaged.emit(applied, 0)
	health_changed.emit(0, max_health)
	died.emit()


## Ends i-frames early (respawn, debug tools, deterministic tests).
func clear_invulnerability() -> void:
	_invulnerable_left = 0.0
	set_process(false)


## Changes the maximum, optionally keeping the current health percentage.
func set_max_health(value: int, keep_ratio := false) -> void:
	var ratio := float(current_health) / float(maxi(1, max_health))
	max_health = maxi(1, value)
	if keep_ratio:
		current_health = clampi(roundi(max_health * ratio), 1, max_health)
	else:
		current_health = mini(current_health, max_health)
	health_changed.emit(current_health, max_health)


func _process(delta: float) -> void:
	if _invulnerable_left <= 0.0:
		set_process(false)
		return
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)
	if _invulnerable_left == 0.0:
		set_process(false)
