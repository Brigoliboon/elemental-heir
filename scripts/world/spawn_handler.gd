class_name SpawnHandler
extends Node
## Builds the encounter for its parent Area from an AreaSpawnData resource.
##
## The first visit to an area in the current run rolls the encounter and caches
## its slots in SpawnState. Later visits replay the same encounter and skip slots
## whose monster died, so clearing an area stays cleared until the player visits
## a safe area (the village resets SpawnState).

@export var spawn_data: AreaSpawnData
@export var spawn_parent: NodePath = ^".."
## Keep random spawns at least this far from the player's start position.
@export var min_player_distance := 240.0
## Keep random spawns from stacking on top of each other.
@export var min_slot_distance := 120.0
## How many times to reroll a position before accepting the last one.
@export var position_attempts := 32
## 0 randomises; a non-zero value makes encounter rolls reproducible.
@export var random_seed := 0

var current_stage := 0
var region: StringName = &""
var area_id: StringName = &""

var _area: Area
var _rng := RandomNumberGenerator.new()
var _slots: Array = []
var _encounter: Dictionary = {}


func _ready() -> void:
	# Spawning waits for Area._ready() so the ground band, player and viewport
	# are already laid out when positions are resolved.
	set_process(false)


## Called by Area once the background, HUD and player are ready.
func start() -> void:
	_area = get_parent() as Area
	if _area == null:
		push_warning("%s must be a child of an Area" % name)
		return
	if spawn_data == null:
		spawn_data = _area.spawn_data
	if spawn_data == null:
		return
	if not spawn_data.is_valid():
		push_warning("%s has an invalid AreaSpawnData" % name)
		return

	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()

	current_stage = spawn_data.stage
	region = spawn_data.region
	area_id = _resolve_area_id()

	if SpawnState.has_encounter(area_id):
		_encounter = SpawnState.get_encounter(area_id)
	else:
		_encounter = _roll_encounter()
		SpawnState.store_encounter(area_id, _encounter)

	_slots = _encounter.get("slots", [])
	_spawn_slots()


func _resolve_area_id() -> StringName:
	if not spawn_data.area_id.is_empty():
		return spawn_data.area_id
	var scene := get_tree().current_scene
	if scene != null and not scene.scene_file_path.is_empty():
		return StringName(scene.scene_file_path)
	return StringName(_area.name if _area != null else name)


func _roll_encounter() -> Dictionary:
	var slots: Array = []
	var used_positions: Array[Vector2] = []
	for entry in spawn_data.entries:
		if entry == null or entry.monster_scene == null:
			continue
		var count := entry.count_for(_rng)
		for index in count:
			var rarity := entry.rarity_override
			if rarity < 0:
				rarity = spawn_data.roll_rarity(_rng)
			var point := _roll_position(used_positions)
			used_positions.append(point)
			slots.append({
				"scene_path": entry.monster_scene.resource_path,
				"rarity": rarity,
				"x_ratio": point.x,
				"depth_ratio": point.y,
				"defeated": false,
			})
	return {
		"region": region,
		"stage": current_stage,
		"slots": slots,
	}


func _roll_position(used_positions: Array[Vector2]) -> Vector2:
	var player_x := _area.player.position.x if _area.player != null else 0.0
	var last := Vector2(_rng.randf_range(0.12, 0.88), _rng.randf_range(0.15, 0.85))
	for attempt in maxi(1, position_attempts):
		var point := Vector2(_rng.randf_range(0.12, 0.88), _rng.randf_range(0.15, 0.85))
		last = point
		var feet := _slot_world_position(point)
		if absf(feet.x - player_x) < min_player_distance:
			continue
		if _area.is_blocked(feet):
			continue
		var crowded := false
		for used in used_positions:
			if feet.distance_to(_slot_world_position(used)) < min_slot_distance:
				crowded = true
				break
		if not crowded:
			break
	return last


func _spawn_slots() -> void:
	for index in _slots.size():
		var slot: Dictionary = _slots[index]
		if bool(slot.get("defeated", false)):
			continue
		var scene_path := str(slot.get("scene_path", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("%s could not load spawn scene %s" % [name, scene_path])
			continue

		var node := packed.instantiate()
		var monster := node as Monster
		if monster == null:
			push_warning("%s spawn scene %s is not a Monster" % [name, scene_path])
			node.free()
			continue

		monster.spawn_rarity = int(slot.get("rarity", EnemyData.Rarity.NORMAL))
		var parent := _spawn_parent()
		parent.add_child(monster)
		var feet := _slot_world_position(Vector2(
			float(slot.get("x_ratio", 0.5)),
			float(slot.get("depth_ratio", 0.5))
		))
		monster.global_position = feet - Vector2(0.0, monster.depth_foot_offset * monster.scale.y)
		monster.died.connect(_on_monster_died.bind(index))


func _spawn_parent() -> Node:
	var parent := get_node_or_null(spawn_parent)
	if parent == null:
		parent = _area
	return parent


## Converts an encounter slot's normalised position into world space. The x ratio
## spans the walkable width and the depth ratio spans the ground band.
func _slot_world_position(point: Vector2) -> Vector2:
	if _area == null:
		return point
	var margin := _area.edge_margin * 2.0
	var right := maxf(margin, _area.world_width - _area.edge_margin * 2.0)
	var x := lerpf(margin, right, clampf(point.x, 0.0, 1.0))
	var feet_y := lerpf(_area.ground_far_y, _area.ground_near_y, clampf(point.y, 0.0, 1.0))
	return Vector2(x, feet_y)


func _on_monster_died(slot_index: int) -> void:
	SpawnState.mark_defeated(area_id, slot_index)


## Number of living spawn slots for this area (not counting summons).
func living_count() -> int:
	var result := 0
	for slot in _slots:
		if not bool((slot as Dictionary).get("defeated", false)):
			result += 1
	return result
