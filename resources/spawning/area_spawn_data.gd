class_name AreaSpawnData
extends Resource
## Defines the encounter for one area stage: which monsters spawn, how many, and
## the rarity odds for each instance. Enemy scenes carry the MonsterData; this
## resource only decides the composition of the encounter.

@export_group("Identity")
## Stable id used by SpawnState to remember this area's encounter and kills.
@export var area_id: StringName = &""
@export var region: StringName = &"forest"
## Progression stage inside the region (entrance, clearing, ...).
@export var stage: int = 1
@export var display_name: String = ""

@export_group("Composition")
@export var entries: Array[AreaSpawnEntry] = []

@export_group("Rarity chances")
## Chances are normalised at runtime, so they do not have to add up to exactly 1.
@export_range(0.0, 1.0) var normal_chance := 0.90
@export_range(0.0, 1.0) var epic_chance := 0.08
@export_range(0.0, 1.0) var legendary_chance := 0.015
@export_range(0.0, 1.0) var anomaly_chance := 0.005


func roll_rarity(rng: RandomNumberGenerator) -> int:
	var weights := [
		maxf(0.0, normal_chance),
		maxf(0.0, epic_chance),
		maxf(0.0, legendary_chance),
		maxf(0.0, anomaly_chance),
	]
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return EnemyData.Rarity.NORMAL

	var roll := rng.randf() * total
	for index in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return index
	return EnemyData.Rarity.NORMAL


func total_count_range() -> Vector2i:
	var low := 0
	var high := 0
	for entry in entries:
		if entry == null:
			continue
		low += maxi(0, entry.min_count)
		high += maxi(entry.min_count, entry.max_count)
	return Vector2i(low, high)


func is_valid() -> bool:
	if entries.is_empty():
		return false
	for entry in entries:
		if entry == null or not entry.is_valid():
			return false
	return true
