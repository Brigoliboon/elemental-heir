extends Resource
class_name LootEntry
## One row of an enemy loot table.
##
## [member drop_chance] is rolled independently for this entry on every table
## pass, so the percentages read exactly like a designer's drop table:
## 0.4 means "drops 40% of the time".
##
## [member weight] is only used when a roll has to pick exactly one entry, such
## as the guaranteed rare-or-better roll for Legendary enemies or the unique roll
## for Anomalies. Higher weight is picked more often.

@export var item: ItemData
## Relative weight for guaranteed single-pick rolls. Ignored by normal rolls.
@export var weight: float = 1.0
@export var min_count: int = 1
@export var max_count: int = 1
## Independent chance this entry drops on each normal table pass.
@export_range(0.0, 1.0) var drop_chance: float = 1.0
## Marked entries satisfy the Anomaly rarity's guaranteed unique drop.
@export var unique: bool = false


## Rolls the stack size for a successful drop.
func roll_count(rng: RandomNumberGenerator) -> int:
	var low := maxi(1, min_count)
	var high := maxi(low, max_count)
	return rng.randi_range(low, high)


## Why this entry cannot be rolled, or an empty string when it is usable.
func validation_error() -> String:
	if item == null:
		return "loot entry has no item"
	if min_count <= 0 or max_count <= 0:
		return "loot entry %s has a non-positive count" % item.id
	if max_count < min_count:
		return "loot entry %s has max_count below min_count" % item.id
	return ""
