extends Node
## Persistent player level/experience. Lives as the `PlayerProgress` autoload so
## progress survives area changes and app restarts.

const DEFAULT_SAVE_PATH := "user://player_progress.cfg"
const SECTION := "player"

var save_path := DEFAULT_SAVE_PATH
## Tests disable this so they never touch the player's real save file.
var persistence_enabled := true
var has_state := false
var level := 1
var experience := 0
var equipped: Array[String] = ["", "", "", "", "", "", "", ""]


func _ready() -> void:
	load_progress()


func load_progress() -> bool:
	if not persistence_enabled:
		return false
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return false
	level = maxi(1, int(config.get_value(SECTION, "level", 1)))
	experience = maxi(0, int(config.get_value(SECTION, "experience", 0)))
	var eq = config.get_value(SECTION, "equipped", equipped)
	if eq is Array:
		equipped = []
		for v in eq:
			equipped.append(str(v))
	while equipped.size() < 8:
		equipped.append("")
	has_state = true
	return true


func record(new_level: int, new_experience: int) -> void:
	new_level = maxi(1, new_level)
	new_experience = maxi(0, new_experience)
	if has_state and level == new_level and experience == new_experience:
		return
	level = new_level
	experience = new_experience
	has_state = true
	save_progress()


func save_progress() -> void:
	if not persistence_enabled:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "level", level)
	config.set_value(SECTION, "experience", experience)
	config.set_value(SECTION, "equipped", equipped)
	var err := config.save(save_path)
	if err != OK:
		push_warning("PlayerProgress could not save to %s (error %d)" % [save_path, err])


func reset(delete_save: bool = true) -> void:
	level = 1
	experience = 0
	has_state = false
	equipped = ["", "", "", "", "", "", "", ""]
	if delete_save and persistence_enabled and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
