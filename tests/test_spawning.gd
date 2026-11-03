extends RefCounted
## Validates area encounter tables, runtime spawning, rarity rolls and the
## village respawn gate. Kills stay in SpawnState while the player moves between
## fighting areas and are cleared only by entering a safe zone.

const ENTRANCE_SCENE := "res://scenes/areas/forest/forest_entrance.tscn"
const FIGHT_SCENE := "res://scenes/areas/forest/forest_fight.tscn"
const ARENA_SCENE := "res://scenes/areas/forest/forest_guardian_arena.tscn"
const VILLAGE_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const ENTRANCE_DATA := "res://resources/spawning/forest_entrance.tres"
const FIGHT_DATA := "res://resources/spawning/forest_fight.tres"
const ARENA_DATA := "res://resources/spawning/forest_guardian_arena.tres"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var state := tree.root.get_node_or_null("SpawnState")
	if state == null:
		failures.append("SpawnState autoload is missing")
		return failures

	state.reset_all()
	_check_tables(failures)
	await _check_spawn_and_respawn_gate(tree, state, failures)
	await _check_guardian_arena(tree, state, failures)
	await _check_rarity_roll(tree, state, failures)
	state.reset_all()
	return failures


func _check_tables(failures: Array[String]) -> void:
	for path in [ENTRANCE_DATA, FIGHT_DATA, ARENA_DATA]:
		var data := load(path) as AreaSpawnData
		if data == null:
			failures.append("%s must load as AreaSpawnData" % path)
			continue
		if data.area_id.is_empty():
			failures.append("%s must define a stable area_id" % path)
		if data.region != &"forest":
			failures.append("%s must belong to the forest region" % path)
		if data.stage < 1:
			failures.append("%s must define a stage" % path)
		if not data.is_valid():
			failures.append("%s must have valid entries and scenes" % path)
		var counts := data.total_count_range()
		if counts.x <= 0 or counts.y < counts.x:
			failures.append("%s must define a positive spawn count" % path)

	var entrance := load(ENTRANCE_DATA) as AreaSpawnData
	var fight := load(FIGHT_DATA) as AreaSpawnData
	var arena := load(ARENA_DATA) as AreaSpawnData
	if entrance != null and fight != null and entrance.stage >= fight.stage:
		failures.append("forest entrance must be an earlier stage than the clearing")
	if fight != null and arena != null and fight.stage >= arena.stage:
		failures.append("the guardian arena must come after the clearing")
	if fight != null:
		if fight.entries.size() != 1 or fight.entries[0].monster_scene.resource_path != "res://entities/enemies/mob.tscn":
			failures.append("the clearing must spawn goblins only")
	if arena != null:
		if arena.entries.size() != 1 or arena.entries[0].monster_scene.resource_path != "res://entities/enemies/guardian.tscn":
			failures.append("the guardian arena must spawn the guardian only")


func _check_spawn_and_respawn_gate(
	tree: SceneTree,
	state: Node,
	failures: Array[String]
) -> void:
	var entrance := await _instantiate(tree, ENTRANCE_SCENE, failures)
	if entrance == null:
		return
	var handler := entrance.get_node_or_null("SpawnHandler") as SpawnHandler
	if handler == null or entrance.spawn_data == null:
		failures.append("forest entrance must expose a SpawnHandler and spawn data")
		entrance.queue_free()
		await tree.process_frame
		return

	var first_count := _living_enemies(entrance)
	var cached: Dictionary = state.get_encounter(handler.area_id)
	var slot_count := (cached.get("slots", []) as Array).size()
	if first_count == 0:
		failures.append("forest entrance must spawn monsters on the first visit")
	if first_count != slot_count - state.defeated_count(handler.area_id):
		failures.append("spawned monsters must match the cached encounter slots")
	if handler.current_stage != 1:
		failures.append("the spawn handler must expose the area stage")
	if handler.region != &"forest":
		failures.append("the spawn handler must expose the region")

	var victim := _first_enemy(entrance)
	if victim != null:
		victim.health.kill()
		await tree.process_frame
		if state.defeated_count(handler.area_id) != 1:
			failures.append("a spawned monster's death must be recorded")

	entrance.queue_free()
	await tree.process_frame
	await tree.process_frame

	# Re-entering a fighting area must not bring back a killed monster.
	var revisit := await _instantiate(tree, ENTRANCE_SCENE, failures)
	if revisit == null:
		return
	if _living_enemies(revisit) != first_count - 1:
		failures.append("re-entering a fighting area must not respawn defeated monsters")
	revisit.queue_free()
	await tree.process_frame
	await tree.process_frame

	# Entering the village is the safe-zone reset, so the next visit rerolls.
	var village := await _instantiate(tree, VILLAGE_SCENE, failures)
	if village == null:
		return
	if not village.safe_zone:
		failures.append("the village must be marked as a safe zone")
	if not state.encounters.is_empty():
		failures.append("entering the village must clear all encounter state")
	village.queue_free()
	await tree.process_frame
	await tree.process_frame

	var fresh := await _instantiate(tree, ENTRANCE_SCENE, failures)
	if fresh != null:
		if _living_enemies(fresh) == 0:
			failures.append("monsters must respawn after visiting the village")
		fresh.queue_free()
		await tree.process_frame


func _check_guardian_arena(
	tree: SceneTree,
	state: Node,
	failures: Array[String]
) -> void:
	state.reset_all()
	var arena := await _instantiate(tree, ARENA_SCENE, failures)
	if arena == null:
		return

	if arena.spawn_data == null or arena.spawn_data.area_id != &"forest_guardian_arena":
		failures.append("the guardian arena must wire its own spawn data")
	if arena.exit_left_scene != FIGHT_SCENE:
		failures.append("the guardian arena must return to the clearing")

	var monsters: Array[Monster] = []
	for child in arena.get_children():
		if child is Monster:
			monsters.append(child as Monster)
	if monsters.size() != 1:
		failures.append("the guardian arena must spawn exactly one guardian")
	elif monsters[0].config == null or monsters[0].config.enemy_name != "Hollowhart Guardian":
		failures.append("the guardian arena must spawn the Hollowhart Guardian")

	arena.queue_free()
	await tree.process_frame
	await tree.process_frame
	state.reset_all()


func _check_rarity_roll(
	tree: SceneTree,
	state: Node,
	failures: Array[String]
) -> void:
	var data := AreaSpawnData.new()
	data.area_id = &"test_rarity_area"
	data.region = &"forest"
	data.stage = 9
	data.normal_chance = 0.0
	data.epic_chance = 0.0
	data.legendary_chance = 0.0
	data.anomaly_chance = 1.0

	var entry := AreaSpawnEntry.new()
	entry.monster_scene = load("res://entities/enemies/boarlet.tscn") as PackedScene
	entry.min_count = 1
	entry.max_count = 1
	entry.rarity_override = EnemyData.Rarity.ANOMALY
	data.entries.append(entry)

	var packed := load(ENTRANCE_SCENE) as PackedScene
	var area := packed.instantiate() as Area
	area.spawn_data = data
	tree.root.add_child(area)
	await tree.process_frame
	await tree.process_frame

	var monster := _first_enemy(area)
	if monster == null:
		failures.append("a forced-rarity entry must still spawn its monster")
	else:
		if monster.effective_rarity() != EnemyData.Rarity.ANOMALY:
			failures.append("a spawn entry must honour rarity_override")
		if monster.max_health != 200:
			failures.append("anomaly rarity must scale max health by 4x")
		if monster.stats.get_stat(Stats.ATTACK) <= 8.0:
			failures.append("anomaly rarity must scale attack")
		if monster.base_tint == Color.WHITE:
			failures.append("rare spawns must use a visible tint")
		var name_label := monster.get_node_or_null("NameLabel") as Label
		if name_label == null:
			failures.append("monsters must show a name label")
		else:
			if name_label.text != "Boarlet":
				failures.append("the name label must use EnemyData.enemy_name")
			if name_label.get_theme_color("font_color") != EnemyData.rarity_tint(EnemyData.Rarity.ANOMALY):
				failures.append("the name label must use the spawn rarity color")

	# A normal roll still obeys the table.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 20:
		if data.roll_rarity(rng) != EnemyData.Rarity.ANOMALY:
			failures.append("a 100% anomaly table must never roll another rarity")
			break

	area.queue_free()
	await tree.process_frame
	state.reset_all()


func _instantiate(tree: SceneTree, path: String, failures: Array[String]) -> Area:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("%s did not load for the spawn test" % path)
		return null
	var area := packed.instantiate() as Area
	if area == null:
		failures.append("%s did not instantiate as an Area" % path)
		return null
	tree.root.add_child(area)
	await tree.process_frame
	await tree.process_frame
	for child in area.get_children():
		if child is Monster:
			(child as Monster).set_physics_process(false)
	return area


func _living_enemies(area: Area) -> int:
	var count := 0
	for child in area.get_children():
		if child is Monster and not (child as Monster).is_dead():
			count += 1
	return count


func _first_enemy(area: Area) -> Monster:
	for child in area.get_children():
		if child is Monster:
			return child as Monster
	return null
