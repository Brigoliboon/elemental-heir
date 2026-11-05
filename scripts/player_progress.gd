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
## Runtime-only health carry-over between areas. Never written to the save file.
var has_health := false
var health := 0
var equipped: Array[String] = ["", "", "", "", "", "", "", ""]
## Resource paths of the three primary skills, in slot order.
var equipped_skills: Array[String] = ["", "", ""]


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
	var eq_skills = config.get_value(SECTION, "equipped_skills", equipped_skills)
	if eq_skills is Array:
		equipped_skills = []
		for v in eq_skills:
			equipped_skills.append(str(v))
	while equipped_skills.size() < 3:
		equipped_skills.append("")
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


## Remembers health for the next area without persisting it across app restarts.
func record_health(current: int) -> void:
	has_health = true
	health = maxi(1, current)


## Clears carried health so the next area starts at full.
func reset_health() -> void:
	has_health = false
	health = 0


func save_progress() -> void:
	if not persistence_enabled:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "level", level)
	config.set_value(SECTION, "experience", experience)
	config.set_value(SECTION, "equipped", equipped)
	config.set_value(SECTION, "equipped_skills", equipped_skills)
	var err := config.save(save_path)
	if err != OK:
		push_warning("PlayerProgress could not save to %s (error %d)" % [save_path, err])


func reset(delete_save: bool = true) -> void:
	level = 1
	experience = 0
	has_state = false
	reset_health()
	equipped = ["", "", "", "", "", "", "", ""]
	equipped_skills = ["", "", ""]
	if delete_save and persistence_enabled and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
