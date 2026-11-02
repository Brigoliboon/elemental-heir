extends Node
## Runtime memory of area encounters. An encounter is rolled once per run and
## kept while the player moves between fighting areas, so a killed monster stays
## dead when the scene reloads. Entering a safe area (the village) clears the
## whole run, which lets every area roll a fresh encounter on the next visit.

var encounters: Dictionary = {}


## Clears every cached encounter. Safe areas call this on entry.
func reset_all() -> void:
	encounters.clear()


## Test/debug helper. Kept separate from reset_all so callers are explicit.
func reset() -> void:
	reset_all()


func has_encounter(area_id: StringName) -> bool:
	return encounters.has(area_id)


func get_encounter(area_id: StringName) -> Dictionary:
	return encounters.get(area_id, {})


func store_encounter(area_id: StringName, encounter: Dictionary) -> void:
	encounters[area_id] = encounter


## Marks one spawn slot dead. Returns true only when the state actually changed.
func mark_defeated(area_id: StringName, slot_index: int) -> bool:
	if not encounters.has(area_id):
		return false
	var encounter: Dictionary = encounters[area_id]
	var slots: Array = encounter.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: Dictionary = slots[slot_index]
	if bool(slot.get("defeated", false)):
		return false
	slot["defeated"] = true
	encounter["slots"] = slots
	return true


func defeated_count(area_id: StringName) -> int:
	var encounter := get_encounter(area_id)
	if encounter.is_empty():
		return 0
	var result := 0
	for slot in encounter.get("slots", []):
		if bool((slot as Dictionary).get("defeated", false)):
			result += 1
	return result


func living_count(area_id: StringName) -> int:
	var encounter := get_encounter(area_id)
	if encounter.is_empty():
		return 0
	var result := 0
	for slot in encounter.get("slots", []):
		if not bool((slot as Dictionary).get("defeated", false)):
			result += 1
	return result


func current_stage() -> int:
	# Every area in a region has its own stage; expose the highest visited one.
	var highest := 0
	for area_id in encounters.keys():
		var encounter: Dictionary = encounters[area_id]
		highest = maxi(highest, int(encounter.get("stage", 0)))
	return highest
