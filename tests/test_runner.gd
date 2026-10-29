extends Node
## Headless test entry point. Run with:
##   godot --headless --path . res://tests/test_runner.tscn

const TEST_SCRIPTS := [
	preload("res://tests/test_character_data.gd"),
	preload("res://tests/test_player_entity.gd"),
	preload("res://tests/test_mob_entity.gd"),
	preload("res://tests/test_depth_sort.gd"),
	preload("res://tests/test_scene_integrity.gd"),
	preload("res://tests/test_combat.gd"),
	preload("res://tests/test_health.gd"),
	preload("res://tests/test_death_respawn.gd"),
	preload("res://tests/test_block.gd"),
	preload("res://tests/test_block_damage.gd"),
]


func _ready() -> void:
	var failures: Array[String] = []
	for script in TEST_SCRIPTS:
		var suite: RefCounted = script.new()
		failures.append_array(await suite.run(get_tree()))

	if failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		print("%d TEST(S) FAILED" % failures.size())

	get_tree().quit(0 if failures.is_empty() else 1)
