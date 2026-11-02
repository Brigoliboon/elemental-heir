class_name AreaSpawnEntry
extends Resource
## One monster type in an area spawn table. Every entry spawns between
## [member min_count] and [member max_count] instances.

@export var monster_scene: PackedScene

@export_group("Count")
@export var min_count: int = 1
@export var max_count: int = 1

@export_group("Rarity")
## -1 rolls the area rarity table; 0..3 forces a specific EnemyData.Rarity.
@export_range(-1, 3) var rarity_override: int = -1


func count_for(rng: RandomNumberGenerator) -> int:
	var low := maxi(0, min_count)
	var high := maxi(low, max_count)
	return rng.randi_range(low, high)


func is_valid() -> bool:
	return monster_scene != null and max_count >= 0
