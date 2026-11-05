class_name InventorySkillSlot
extends Button
## One owned-skill tile in the inventory skills page. Reuses the bag slot art so
## the grid matches the items page; the panel owns selection and the detail view.

signal skill_selected(skill: PlayerSkill)

var slot_index := -1
var skill: PlayerSkill


func bind_skill(index: int, skill_data: PlayerSkill) -> void:
	slot_index = index
	skill = skill_data
	icon = skill.icon if skill != null else null
	tooltip_text = skill.display_name if skill != null else ""
	button_pressed = false


func set_selected(selected: bool) -> void:
	button_pressed = selected


func _ready() -> void:
	toggle_mode = true
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if skill == null:
		return
	skill_selected.emit(skill)
