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
	preload("res://tests/test_stats.gd"),
	preload("res://tests/test_damage.gd"),
	preload("res://tests/test_leveling.gd"),
	preload("res://tests/test_stats_panel.gd"),
	preload("res://tests/test_player_progress.gd"),
	preload("res://tests/test_item_data.gd"),
	preload("res://tests/test_virtual_joystick.gd"),
	preload("res://tests/test_hud_bars.gd"),
	preload("res://tests/test_hud_buttons.gd"),
	preload("res://tests/test_hud_profile.gd"),
	preload("res://tests/test_hud_attack_state.gd"),
	preload("res://tests/test_attack_block_lock.gd"),
	preload("res://tests/test_world_map.gd"),
	preload("res://tests/test_background_props.gd"),
	preload("res://tests/test_hud_layout.gd"),
	preload("res://tests/test_title_layout.gd"),
]


func _ready() -> void:
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress != null:
		progress.persistence_enabled = false
		progress.reset(false)

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
