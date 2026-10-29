class_name StatsPanel
extends PanelContainer
## Shared HUD panel for player and monster stat readouts.
##
## The panel remembers its last source so health/XP changes can refresh it while
## it stays open. It never writes gameplay state.

@onready var title_label: Label = $Margin/VBox/Title
@onready var body_label: Label = $Margin/VBox/Body
@onready var close_button: Button = $Margin/VBox/Close

var _character: Character
var _mob: Node


func _ready() -> void:
	close_button.pressed.connect(hide_panel)
	hide_panel()


func show_character(character: Character) -> void:
	if character == null or character.stats == null:
		return
	_character = character
	_mob = null
	_render_character()
	visible = true


func show_mob(mob: Node) -> void:
	if mob == null:
		return
	var stats := mob.get("stats") as Stats
	var config := mob.get("config") as EnemyData
	if stats == null or config == null:
		return
	_character = null
	_mob = mob
	_render_mob(mob, config, stats)
	visible = true


func hide_panel() -> void:
	visible = false


## Re-renders the current source without changing visibility.
func refresh() -> void:
	if _character != null and is_instance_valid(_character):
		_render_character()
	elif _mob != null and is_instance_valid(_mob):
		var stats := _mob.get("stats") as Stats
		var config := _mob.get("config") as EnemyData
		if stats != null and config != null:
			_render_mob(_mob, config, stats)


func is_showing_character() -> bool:
	return _character != null and is_instance_valid(_character)


func _render_character() -> void:
	var display_name := "Player"
	if _character.config != null:
		display_name = _character.config.character_name
	title_label.text = "Player - %s (Lv %d)" % [display_name, _character.level]

	var lines: Array[String] = [
		"HP: %d / %d" % [_character.current_health, _character.max_health],
	]
	var to_next := _character.experience_to_next_level()
	if to_next > 0:
		lines.append("XP: %d / %d" % [_character.experience, to_next])
	else:
		lines.append("XP: MAX")
	lines.append("")
	lines.append_array(_stat_lines(_character.stats))
	body_label.text = "\n".join(lines)


func _render_mob(mob: Node, config: EnemyData, stats: Stats) -> void:
	title_label.text = "Monster - %s (Lv %d)" % [config.enemy_name, config.level]
	var current := int(mob.get("current_health"))
	var maximum := int(mob.get("max_health"))
	var lines: Array[String] = [
		"HP: %d / %d" % [current, maximum],
		"XP Reward: %d" % config.xp_reward,
		"",
	]
	lines.append_array(_stat_lines(stats))
	body_label.text = "\n".join(lines)


func _stat_lines(stats: Stats) -> Array[String]:
	return [
		"Attack: %.0f" % stats.get_stat(Stats.ATTACK),
		"Defence: %.0f" % stats.get_stat(Stats.DEFENCE),
		"Move Speed: %.0f" % stats.get_stat(Stats.MOVE_SPEED),
		"Crit Rate: %.1f%%" % (stats.get_stat(Stats.CRIT_RATE) * 100.0),
		"Crit Damage: %.2fx" % stats.get_stat(Stats.CRIT_DAMAGE),
		"Cooldown Reduction: %.1f%%" % (stats.get_stat(Stats.COOLDOWN_REDUCTION) * 100.0),
	]
