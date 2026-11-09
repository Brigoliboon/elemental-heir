extends RefCounted
## Validates the gold currency: saving/loading, enemy gold rolls and the HUD
## total.

const TEMP_SAVE := "user://test_gold_progress.cfg"
const AREA_SCENE := "res://scenes/areas/forest/forest_village_square.tscn"
const BOARLET_DATA := "res://resources/entities/boarlet.tres"
const BOARLET_SCENE := "res://entities/enemies/boarlet.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_check_disk_round_trip())
	failures.append_array(await _check_enemy_gold_roll(tree))
	failures.append_array(await _check_hud_total(tree))
	return failures


func _check_disk_round_trip() -> Array[String]:
	var failures: Array[String] = []
	var script := load("res://scripts/player_progress.gd")
	if script == null:
		failures.append("player_progress.gd did not load")
		return failures

	var store = script.new()
	store.save_path = TEMP_SAVE
	store.persistence_enabled = true
	store.reset(true)
	store.record(2, 10)
	store.add_gold(15)
	if store.gold != 15:
		failures.append("add_gold must raise the total")
	if store.spend_gold(20):
		failures.append("spend_gold must reject more gold than the player owns")
	if not store.spend_gold(5) or store.gold != 10:
		failures.append("spend_gold must deduct from the total")

	var loaded = script.new()
	loaded.save_path = TEMP_SAVE
	loaded.persistence_enabled = true
	if not loaded.load_progress():
		failures.append("gold must survive a save/reload round trip")
	if loaded.gold != 10:
		failures.append("loaded gold must match the saved total, got %d" % loaded.gold)

	loaded.reset(true)
	if loaded.gold != 0:
		failures.append("reset must clear gold")
	if FileAccess.file_exists(TEMP_SAVE):
		failures.append("reset(true) must delete the save file")
	store.free()
	loaded.free()
	return failures


func _check_enemy_gold_roll(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var data := (load(BOARLET_DATA) as MonsterData).duplicate() as MonsterData
	if data == null:
		failures.append("%s did not load" % BOARLET_DATA)
		return failures
	data.loot_table = []
	data.gold_min = 7
	data.gold_max = 7

	var container := Node2D.new()
	tree.root.add_child(container)
	var monster := (load(BOARLET_SCENE) as PackedScene).instantiate() as Monster
	if monster == null:
		failures.append("the boarlet scene did not instantiate")
		container.queue_free()
		await tree.process_frame
		return failures
	monster.config = data
	monster.loot_seed = 5
	monster.log_loot = false
	container.add_child(monster)
	monster.global_position = Vector2(900, 500)
	monster.take_damage(999999)
	await tree.process_frame
	await tree.process_frame

	var found := 0
	for child in container.get_children():
		var pickup := child as LootPickup
		if pickup != null and pickup.gold > 0:
			found += pickup.gold
	if found != 7:
		failures.append("killing an enemy with a gold range must drop gold inside it (got %d)" % found)

	container.queue_free()
	await tree.process_frame
	return failures


func _check_hud_total(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load" % AREA_SCENE)
		return failures
	PlayerProgress.reset(false)
	var area := packed.instantiate() as Area
	tree.root.add_child(area)
	await tree.process_frame

	var label := area.get_node_or_null("HUD/UI/PlayerHealth/GoldLabel") as Label
	if label == null:
		failures.append("the HUD needs a GoldLabel")
	else:
		if label.text != "Gold 0":
			failures.append("the HUD must start at Gold 0, got '%s'" % label.text)
		PlayerProgress.add_gold(42)
		if label.text != "Gold 42":
			failures.append("the HUD must follow the gold total, got '%s'" % label.text)

	area.queue_free()
	await tree.process_frame
	PlayerProgress.reset(false)
	return failures
