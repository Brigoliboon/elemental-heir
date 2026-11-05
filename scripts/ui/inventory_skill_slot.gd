class_name InventorySkillSlot
extends Button
## One owned-skill tile in the inventory skills page. Reuses the bag slot art so
## the grid matches the items page; the panel owns selection and the detail view.

signal skill_selected(skill: PlayerSkill)

const DRAG_TYPE := &"inventory_skill"

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


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill == null or slot_index < 0:
		return null
	var preview := TextureRect.new()
	preview.texture = skill.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(64, 64)
	preview.size = Vector2(64, 64)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	return {"type": DRAG_TYPE, "skill_index": slot_index, "skill": skill}
