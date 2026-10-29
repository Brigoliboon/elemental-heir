extends RefCounted
## Validates that player level/XP survive area changes and app restarts.


const TEMP_SAVE := "user://test_player_progress.cfg"
const AREA_SCENE := "res://scenes/areas/forest/forest_fight.tscn"


func run(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_check_disk_round_trip())
	failures.append_array(await _check_area_transition(tree))
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
	store.record(3, 25)
	if not FileAccess.file_exists(TEMP_SAVE):
		failures.append("PlayerProgress.record must write the save file")

	var loaded = script.new()
	loaded.save_path = TEMP_SAVE
	loaded.persistence_enabled = true
	if not loaded.load_progress():
		failures.append("PlayerProgress.load_progress must read an existing save")
	if loaded.level != 3 or loaded.experience != 25:
		failures.append("loaded progress must match the saved level and experience")

	loaded.reset(true)
	if FileAccess.file_exists(TEMP_SAVE):
		failures.append("PlayerProgress.reset(true) must delete the save file")
	store.free()
	loaded.free()
	return failures


func _check_area_transition(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var progress := tree.root.get_node_or_null("PlayerProgress")
	if progress == null:
		failures.append("PlayerProgress autoload is missing")
		return failures

	progress.persistence_enabled = false
	progress.reset(false)
	progress.record(4, 60)

	var packed := load(AREA_SCENE) as PackedScene
	if packed == null:
		failures.append("%s did not load for the progress test" % AREA_SCENE)
		return failures

	var first := packed.instantiate() as Area
	tree.root.add_child(first)
	await tree.process_frame
	if first.player.level != 4 or first.player.experience != 60:
		failures.append("an area must restore the saved level and experience")
	var xp_bar := first.get_node_or_null("HUD/UI/PlayerHealth/XPBar") as ProgressBar
	if xp_bar == null or not is_equal_approx(xp_bar.value, 60.0):
		failures.append("the HUD XP bar must show the restored experience")
	first.queue_free()
	await tree.process_frame

	var second := packed.instantiate() as Area
	tree.root.add_child(second)
	await tree.process_frame
	if second.player.level != 4 or second.player.experience != 60:
		failures.append("a second area must keep the saved level and experience")

	second.player.add_experience(10)
	await tree.process_frame
	if progress.level != 4 or progress.experience != 70:
		failures.append("XP gained in an area must be recorded for the next scene")

	second.queue_free()
	await tree.process_frame
	progress.reset(false)
	return failures
