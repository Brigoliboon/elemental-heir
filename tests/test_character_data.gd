extends RefCounted
## Validates that characters are configured through one merged CharacterData resource.


func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []

	var data := load("res://resources/characters/warrior.tres") as CharacterData
	if data == null:
		failures.append("warrior.tres did not load as CharacterData")
		return failures

	if data.character_name != "Sol":
		failures.append("warrior.tres character_name should be 'Sol'")
	if data.max_health <= 0:
		failures.append("warrior.tres max_health must be positive")
	if data.pivots_path == "" or not FileAccess.file_exists(data.pivots_path):
		failures.append("warrior.tres pivots_path is missing")
	if data.part_dir == "" or not DirAccess.dir_exists_absolute(data.part_dir):
		failures.append("warrior.tres part_dir is missing")
	if data.attacks.size() != 3:
		failures.append("warrior.tres should keep all 3 attacks")
	if not CharacterData.CharacterRole.has("ASSASSIN"):
		failures.append("CharacterRole must expose ASSASSIN (renamed from ARCHER)")
	if CharacterData.CharacterRole.has("ARCHER"):
		failures.append("CharacterRole must not keep the old ARCHER name")
	if data.hp_per_level <= 0 or data.attack_per_level <= 0 or data.defence_per_level <= 0:
		failures.append("CharacterData must define per-level stat growth")

	if ResourceLoader.exists("res://scripts/characters/character_config.gd"):
		failures.append("character_config.gd should be removed after the merge")
	if ResourceLoader.exists("res://resources/characters/warrior_t1_side.tres"):
		failures.append("warrior_t1_side.tres should be consolidated into warrior.tres")

	return failures
