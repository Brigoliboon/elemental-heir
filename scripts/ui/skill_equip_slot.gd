class_name SkillEquipSlot
extends Button
## A primary-skill slot on the inventory skills page. Accepts skill tiles dragged
## from the owned-skills grid, mirroring the equipment slots on the items page.

signal skill_dropped(slot_index: int, skill: PlayerSkill)

var slot_index := -1
var skill: PlayerSkill


func bind_skill(index: int, skill_data: PlayerSkill) -> void:
	slot_index = index
	skill = skill_data
	icon = skill.icon if skill != null else null
	tooltip_text = skill.display_name if skill != null else ""


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type") != InventorySkillSlot.DRAG_TYPE:
		return false
	return data.get("skill") is PlayerSkill


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data):
		return
	skill_dropped.emit(slot_index, data["skill"])
