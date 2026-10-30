extends Resource
class_name ItemData

enum ItemType { WEAPON, ARMOUR, ACCESSORY, CONSUMABLE, MATERIAL }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var item_type: ItemType = ItemType.WEAPON
@export var item_group: StringName = &""
@export var rarity: Rarity = Rarity.COMMON
@export var icon: Texture2D
@export var max_stack: int = 1
@export var class_restriction: Array[CharacterData.CharacterRole] = []
@export var description: String = ""


func can_be_used_by(role: CharacterData.CharacterRole) -> bool:
	if class_restriction.is_empty():
		return true
	return class_restriction.has(role)
