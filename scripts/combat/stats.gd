class_name Stats
extends Node
## Runtime stat block for any entity. Base values come from CharacterData or
## EnemyData at the entity's current level; equipment, buffs and passives push
## flat/percentage modifiers by source id. The pipeline is:
##   final = (base + flat) * (1 + pct)

signal stats_changed

const MAX_HEALTH := &"max_health"
const ATTACK := &"attack"
const DEFENCE := &"defence"
const MOVE_SPEED := &"move_speed"
const CRIT_RATE := &"crit_rate"
const CRIT_DAMAGE := &"crit_damage"
const COOLDOWN_REDUCTION := &"cooldown_reduction"

var level := 1

var _data: Resource
var _base: Dictionary = {}
## source_id -> { stat -> { "flat": float, "pct": float } }
var _modifiers: Dictionary = {}


## Rebuilds the base block from a data resource at `at_level`, keeping modifiers.
func configure(data: Resource, at_level: int = 1) -> void:
	_data = data
	level = maxi(1, at_level)
	_recompute_base()
	stats_changed.emit()


## Adds or replaces one stat modifier for a source. Repeated calls with the same
## source and stat overwrite the previous values.
func add_modifier(source_id: StringName, stat: StringName, flat: float, pct: float = 0.0) -> void:
	if not _modifiers.has(source_id):
		_modifiers[source_id] = {}
	_modifiers[source_id][stat] = {"flat": flat, "pct": pct}
	stats_changed.emit()


## Removes every modifier owned by a source (equipment swap, buff expiry, ...).
func remove_modifier(source_id: StringName) -> void:
	if _modifiers.erase(source_id):
		stats_changed.emit()


## Resolves the final value: (base + flat) * (1 + pct).
func get_stat(stat: StringName) -> float:
	var flat := 0.0
	var pct := 0.0
	for source in _modifiers.keys():
		var entry: Dictionary = _modifiers[source]
		if not entry.has(stat):
			continue
		var modifier: Dictionary = entry[stat]
		flat += float(modifier["flat"])
		pct += float(modifier["pct"])
	return (float(_base.get(stat, 0.0)) + flat) * (1.0 + pct)


## Base value before modifiers. Exposed for tests and UI inspection.
func get_base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))


func _recompute_base() -> void:
	_base.clear()
	if _data is CharacterData:
		var data := _data as CharacterData
		var growth := float(level - 1)
		_base[MAX_HEALTH] = float(data.max_health) + float(data.hp_per_level) * growth
		_base[ATTACK] = float(data.attack_damage) + float(data.attack_per_level) * growth
		_base[DEFENCE] = float(data.defence) + float(data.defence_per_level) * growth
		_base[MOVE_SPEED] = data.move_speed
		_base[CRIT_RATE] = data.crit_rate
		_base[CRIT_DAMAGE] = data.crit_damage
		_base[COOLDOWN_REDUCTION] = data.cooldown_reduction
	elif _data is EnemyData:
		var data := _data as EnemyData
		_base[MAX_HEALTH] = float(data.max_health)
		_base[ATTACK] = float(data.attack_damage)
		_base[DEFENCE] = float(data.defence)
		_base[MOVE_SPEED] = data.move_speed
		_base[CRIT_RATE] = data.crit_rate
		_base[CRIT_DAMAGE] = data.crit_damage
		_base[COOLDOWN_REDUCTION] = data.cooldown_reduction
