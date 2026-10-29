extends Node
## Headless test entry point. Run with:
##   godot --headless --path . res://tests/test_runner.tscn

const TEST_SCRIPTS := [
	preload("res://tests/test_character_data.gd"),
	preload("res://tests/test_player_entity.gd"),
	preload("res://tests/test_mob_entity.gd"),
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
